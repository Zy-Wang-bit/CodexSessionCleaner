#!/usr/bin/env python3
"""Delete local Codex session records and related logs.

This tool edits Codex's local storage under ~/.codex. It is intentionally
conservative at the CLI boundary: delete defaults to dry-run unless --yes is
provided.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


THREAD_ID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
AUTO_CURRENT_THREAD = object()


class SessionDeleteError(RuntimeError):
    pass


@dataclass
class DeleteResult:
    thread_id: str
    dry_run: bool
    thread_ids: list[str] = field(default_factory=list)
    found: bool = False
    files: list[Path] = field(default_factory=list)
    state_deletes: dict[str, int] = field(default_factory=dict)
    log_deletes: int = 0
    index_lines_removed: int = 0
    global_state_changed: bool = False
    vacuumed: list[Path] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class SessionRow:
    thread_id: str
    title: str
    updated_at: int | None
    rollout_path: Path | None
    cwd: Path | None
    agent_role: str | None
    agent_nickname: str | None
    parent_thread_id: str | None
    parent_title: str | None
    archived: bool


def list_sessions(codex_home: Path, limit: int = 50, include_archived: bool = False) -> list[SessionRow]:
    codex_home = Path(codex_home).expanduser()
    state_db = codex_home / "state_5.sqlite"
    if not state_db.exists():
        return []

    where = "" if include_archived else "WHERE t.archived = 0"
    sql = f"""
        SELECT
            t.id,
            t.title,
            t.updated_at,
            t.rollout_path,
            t.cwd,
            t.agent_role,
            t.agent_nickname,
            e.parent_thread_id,
            p.title AS parent_title,
            t.archived
        FROM threads t
        LEFT JOIN thread_spawn_edges e ON e.child_thread_id = t.id
        LEFT JOIN threads p ON p.id = e.parent_thread_id
        {where}
        ORDER BY t.updated_at DESC, t.id DESC
        LIMIT ?
    """
    with sqlite3.connect(state_db) as conn:
        conn.row_factory = sqlite3.Row
        if not _table_exists(conn, "threads"):
            return []
        rows = conn.execute(sql, (limit,)).fetchall()

    return [
        SessionRow(
            thread_id=row["id"],
            title=row["title"],
            updated_at=row["updated_at"],
            rollout_path=Path(row["rollout_path"]) if row["rollout_path"] else None,
            cwd=Path(row["cwd"]) if row["cwd"] else None,
            agent_role=row["agent_role"],
            agent_nickname=row["agent_nickname"],
            parent_thread_id=row["parent_thread_id"],
            parent_title=row["parent_title"],
            archived=bool(row["archived"]),
        )
        for row in rows
    ]


def delete_session(
    codex_home: Path,
    thread_id: str,
    *,
    dry_run: bool = True,
    assume_yes: bool = False,
    current_thread_id: str | None | object = AUTO_CURRENT_THREAD,
    force_current: bool = False,
    vacuum: bool = True,
) -> DeleteResult:
    codex_home = Path(codex_home).expanduser()
    _validate_thread_id(thread_id)

    if current_thread_id is AUTO_CURRENT_THREAD:
        current_thread_id = os.environ.get("CODEX_THREAD_ID")

    result = DeleteResult(thread_id=thread_id, dry_run=dry_run)
    thread_ids = _thread_subtree_ids(codex_home, thread_id, result)
    result.thread_ids = thread_ids

    if not dry_run and not force_current and current_thread_id in thread_ids:
        raise SessionDeleteError(
            "Refusing to delete the current Codex thread. Re-run with --force-current if you have closed it elsewhere."
        )
    if not dry_run and not assume_yes:
        raise SessionDeleteError("Refusing to delete without explicit confirmation.")

    rollout_paths = _rollout_paths_from_state(codex_home, thread_ids, result)
    result.files = _discover_files(codex_home, thread_ids, rollout_paths)

    _plan_or_delete_state_rows(codex_home, thread_ids, dry_run, result)
    _plan_or_delete_logs(codex_home, thread_ids, dry_run, result)
    _plan_or_rewrite_session_index(codex_home, thread_ids, dry_run, result)
    _plan_or_rewrite_global_state(codex_home, thread_ids, dry_run, result)

    if not dry_run:
        for path in result.files:
            _unlink_if_exists(path, result)
        _remove_empty_session_dirs(codex_home)
        if vacuum:
            _vacuum_databases(codex_home, result)

    result.found = (
        bool(result.files)
        or any(count > 0 for count in result.state_deletes.values())
        or result.log_deletes > 0
        or result.index_lines_removed > 0
        or result.global_state_changed
    )
    return result


def _validate_thread_id(thread_id: str) -> None:
    if not THREAD_ID_RE.match(thread_id):
        raise SessionDeleteError(f"Invalid Codex thread id: {thread_id}")


def _thread_subtree_ids(codex_home: Path, thread_id: str, result: DeleteResult) -> list[str]:
    state_db = codex_home / "state_5.sqlite"
    if not state_db.exists():
        return [thread_id]
    seen = {thread_id}
    ordered = [thread_id]
    frontier = [thread_id]
    try:
        with sqlite3.connect(state_db) as conn:
            if not _table_exists(conn, "thread_spawn_edges"):
                return ordered
            while frontier:
                placeholders = _placeholders(frontier)
                rows = conn.execute(
                    f"""
                    SELECT child_thread_id
                    FROM thread_spawn_edges
                    WHERE parent_thread_id IN ({placeholders})
                    ORDER BY child_thread_id
                    """,
                    tuple(frontier),
                ).fetchall()
                frontier = []
                for row in rows:
                    child_id = row[0]
                    if child_id in seen:
                        continue
                    seen.add(child_id)
                    ordered.append(child_id)
                    frontier.append(child_id)
    except sqlite3.Error as exc:
        result.warnings.append(f"Could not read thread spawn edges from {state_db}: {exc}")
    return ordered


def _rollout_paths_from_state(codex_home: Path, thread_ids: list[str], result: DeleteResult) -> list[Path]:
    state_db = codex_home / "state_5.sqlite"
    if not state_db.exists():
        return []
    try:
        with sqlite3.connect(state_db) as conn:
            if not _table_exists(conn, "threads"):
                return []
            placeholders = _placeholders(thread_ids)
            rows = conn.execute(
                f"SELECT rollout_path FROM threads WHERE id IN ({placeholders})",
                tuple(thread_ids),
            ).fetchall()
    except sqlite3.Error as exc:
        result.warnings.append(f"Could not read {state_db}: {exc}")
        return []
    return [Path(row[0]) for row in rows if row[0]]


def _discover_files(codex_home: Path, thread_ids: list[str], rollout_paths: Iterable[Path]) -> list[Path]:
    candidates: set[Path] = {path.expanduser() for path in rollout_paths}
    for thread_id in thread_ids:
        for root, pattern in (
            (codex_home / "sessions", f"*{thread_id}*.jsonl"),
            (codex_home / "archived_sessions", f"*{thread_id}*"),
            (codex_home / "shell_snapshots", f"{thread_id}.*"),
        ):
            if root.exists():
                candidates.update(path for path in root.rglob(pattern) if path.is_file())
    return sorted(path for path in candidates if path.exists())


def _plan_or_delete_state_rows(codex_home: Path, thread_ids: list[str], dry_run: bool, result: DeleteResult) -> None:
    state_db = codex_home / "state_5.sqlite"
    if not state_db.exists():
        return

    placeholders = _placeholders(thread_ids)
    specs = [
        ("thread_dynamic_tools", f"thread_id IN ({placeholders})", tuple(thread_ids)),
        ("thread_goals", f"thread_id IN ({placeholders})", tuple(thread_ids)),
        ("stage1_outputs", f"thread_id IN ({placeholders})", tuple(thread_ids)),
        (
            "thread_spawn_edges",
            f"parent_thread_id IN ({placeholders}) OR child_thread_id IN ({placeholders})",
            tuple(thread_ids) + tuple(thread_ids),
        ),
        ("threads", f"id IN ({placeholders})", tuple(thread_ids)),
    ]
    try:
        with sqlite3.connect(state_db) as conn:
            for table, where, params in specs:
                if not _table_exists(conn, table):
                    continue
                count = _count_where(conn, table, where, params)
                result.state_deletes[table] = count
                if count and not dry_run:
                    conn.execute(f"DELETE FROM {table} WHERE {where}", params)
    except sqlite3.Error as exc:
        raise SessionDeleteError(f"Could not update {state_db}: {exc}") from exc


def _plan_or_delete_logs(codex_home: Path, thread_ids: list[str], dry_run: bool, result: DeleteResult) -> None:
    logs_db = codex_home / "logs_2.sqlite"
    if not logs_db.exists():
        return
    try:
        with sqlite3.connect(logs_db) as conn:
            if not _table_exists(conn, "logs"):
                return
            placeholders = _placeholders(thread_ids)
            result.log_deletes = _count_where(conn, "logs", f"thread_id IN ({placeholders})", tuple(thread_ids))
            if result.log_deletes and not dry_run:
                conn.execute(f"DELETE FROM logs WHERE thread_id IN ({placeholders})", tuple(thread_ids))
    except sqlite3.Error as exc:
        raise SessionDeleteError(f"Could not update {logs_db}: {exc}") from exc


def _plan_or_rewrite_session_index(codex_home: Path, thread_ids: list[str], dry_run: bool, result: DeleteResult) -> None:
    index_path = codex_home / "session_index.jsonl"
    if not index_path.exists():
        return

    thread_id_set = set(thread_ids)
    kept_lines: list[str] = []
    removed = 0
    with index_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                kept_lines.append(line)
                continue
            if row.get("id") in thread_id_set:
                removed += 1
            else:
                kept_lines.append(line)

    result.index_lines_removed = removed
    if removed and not dry_run:
        _atomic_write_text(index_path, "".join(kept_lines))


def _plan_or_rewrite_global_state(codex_home: Path, thread_ids: list[str], dry_run: bool, result: DeleteResult) -> None:
    state_path = codex_home / ".codex-global-state.json"
    if not state_path.exists():
        return

    try:
        original = json.loads(state_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        result.warnings.append(f"Could not parse {state_path}: {exc}")
        return

    cleaned = original
    changed = False
    for thread_id in thread_ids:
        cleaned, item_changed = _remove_thread_id_from_json(cleaned, thread_id)
        changed = changed or item_changed
    result.global_state_changed = changed
    if changed and not dry_run:
        _atomic_write_text(state_path, json.dumps(cleaned, indent=2, sort_keys=True) + "\n")


def _remove_thread_id_from_json(value: Any, thread_id: str) -> tuple[Any, bool]:
    if isinstance(value, dict):
        changed = False
        cleaned: dict[str, Any] = {}
        for key, item in value.items():
            if key == thread_id or item == thread_id:
                changed = True
                continue
            new_item, item_changed = _remove_thread_id_from_json(item, thread_id)
            changed = changed or item_changed
            cleaned[key] = new_item
        return cleaned, changed
    if isinstance(value, list):
        changed = False
        cleaned_list: list[Any] = []
        for item in value:
            if item == thread_id:
                changed = True
                continue
            new_item, item_changed = _remove_thread_id_from_json(item, thread_id)
            changed = changed or item_changed
            cleaned_list.append(new_item)
        return cleaned_list, changed
    return value, False


def _unlink_if_exists(path: Path, result: DeleteResult) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError as exc:
        result.warnings.append(f"Could not delete {path}: {exc}")


def _remove_empty_session_dirs(codex_home: Path) -> None:
    root = codex_home / "sessions"
    if not root.exists():
        return
    for path in sorted(root.rglob("*"), key=lambda item: len(item.parts), reverse=True):
        if path.is_dir():
            try:
                path.rmdir()
            except OSError:
                pass


def _vacuum_databases(codex_home: Path, result: DeleteResult) -> None:
    for path in (codex_home / "state_5.sqlite", codex_home / "logs_2.sqlite"):
        if not path.exists():
            continue
        try:
            conn = sqlite3.connect(path)
            try:
                conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                conn.execute("VACUUM")
                conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            finally:
                conn.close()
            result.vacuumed.append(path)
        except sqlite3.Error as exc:
            result.warnings.append(f"Could not vacuum {path}: {exc}")


def _table_exists(conn: sqlite3.Connection, table: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table,),
    ).fetchone()
    return row is not None


def _count_where(conn: sqlite3.Connection, table: str, where: str, params: tuple[Any, ...]) -> int:
    return int(conn.execute(f"SELECT COUNT(*) FROM {table} WHERE {where}", params).fetchone()[0])


def _placeholders(values: Iterable[Any]) -> str:
    return ", ".join("?" for _ in values)


def _atomic_write_text(path: Path, content: str) -> None:
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def _default_codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME", "~/.codex")).expanduser()


def _format_session(row: SessionRow) -> str:
    updated = str(row.updated_at) if row.updated_at is not None else "-"
    archived = " archived" if row.archived else ""
    path = str(row.rollout_path) if row.rollout_path else "-"
    return f"{row.thread_id}  {updated}  {row.title}{archived}\n    {path}"


def _session_to_dict(row: SessionRow) -> dict[str, Any]:
    return {
        "id": row.thread_id,
        "title": row.title,
        "updated_at": row.updated_at,
        "rollout_path": str(row.rollout_path) if row.rollout_path else None,
        "cwd": str(row.cwd) if row.cwd else None,
        "agent_role": row.agent_role,
        "agent_nickname": row.agent_nickname,
        "parent_thread_id": row.parent_thread_id,
        "parent_title": row.parent_title,
        "archived": row.archived,
    }


def _delete_result_to_dict(result: DeleteResult) -> dict[str, Any]:
    return {
        "thread_id": result.thread_id,
        "thread_ids": result.thread_ids,
        "descendant_thread_ids": result.thread_ids[1:],
        "dry_run": result.dry_run,
        "found": result.found,
        "files": [str(path) for path in result.files],
        "state_deletes": result.state_deletes,
        "log_deletes": result.log_deletes,
        "index_lines_removed": result.index_lines_removed,
        "global_state_changed": result.global_state_changed,
        "vacuumed": [str(path) for path in result.vacuumed],
        "warnings": result.warnings,
    }


def _print_delete_result(result: DeleteResult) -> None:
    mode = "DRY-RUN" if result.dry_run else "DELETED"
    print(f"{mode} {result.thread_id}")
    print(f"found: {str(result.found).lower()}")
    print(f"files: {len(result.files)}")
    for path in result.files:
        print(f"  {path}")
    if result.state_deletes:
        print("state_5.sqlite:")
        for table, count in result.state_deletes.items():
            print(f"  {table}: {count}")
    print(f"logs_2.sqlite logs: {result.log_deletes}")
    print(f"session_index.jsonl lines: {result.index_lines_removed}")
    print(f"global state changed: {str(result.global_state_changed).lower()}")
    if result.vacuumed:
        print("vacuumed:")
        for path in result.vacuumed:
            print(f"  {path}")
    for warning in result.warnings:
        print(f"warning: {warning}", file=sys.stderr)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Delete local Codex sessions and related logs.")
    parser.add_argument("--codex-home", type=Path, default=_default_codex_home(), help="Codex home directory.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List local Codex sessions.")
    list_parser.add_argument("--limit", type=int, default=50)
    list_parser.add_argument("--include-archived", action="store_true")
    list_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")

    delete_parser = subparsers.add_parser("delete", help="Delete one local Codex session.")
    delete_parser.add_argument("--id", required=True, dest="thread_id", help="Codex thread/session id.")
    delete_parser.add_argument("--dry-run", action="store_true", help="Show what would be removed.")
    delete_parser.add_argument("--yes", action="store_true", help="Actually delete. Without this, delete is dry-run.")
    delete_parser.add_argument("--force-current", action="store_true", help="Allow deleting CODEX_THREAD_ID.")
    delete_parser.add_argument("--skip-vacuum", action="store_true", help="Skip SQLite VACUUM after deletion.")
    delete_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "list":
            rows = list_sessions(args.codex_home, limit=args.limit, include_archived=args.include_archived)
            if args.json:
                print(json.dumps([_session_to_dict(row) for row in rows], ensure_ascii=False))
                return 0
            for row in rows:
                print(_format_session(row))
            return 0

        if args.command == "delete":
            dry_run = args.dry_run or not args.yes
            result = delete_session(
                args.codex_home,
                args.thread_id,
                dry_run=dry_run,
                assume_yes=args.yes,
                force_current=args.force_current,
                vacuum=not args.skip_vacuum,
            )
            if args.json:
                print(json.dumps(_delete_result_to_dict(result), ensure_ascii=False))
                return 0
            _print_delete_result(result)
            if dry_run and not args.yes:
                print("No changes made. Re-run with --yes to delete.")
            return 0
    except SessionDeleteError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    parser.error("unknown command")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
