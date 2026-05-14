import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from codex_session_delete import SessionDeleteError, delete_session, main


TARGET_ID = "019e2477-3d14-7893-8861-bc77cf5de165"
OTHER_ID = "019e2476-5750-78e3-8181-ffe6e8ddc474"
UNRELATED_ID = "019e0000-aaaa-7000-8000-000000000001"


class CodexSessionDeleteTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.codex_home = Path(self.tmp.name)
        self.rollout_dir = self.codex_home / "sessions" / "2026" / "05" / "14"
        self.rollout_dir.mkdir(parents=True)
        self.rollout_path = self.rollout_dir / f"rollout-2026-05-14T11-10-54-{TARGET_ID}.jsonl"
        self.rollout_path.write_text('{"type":"message","content":"secret"}\n', encoding="utf-8")
        self.other_rollout_path = self.rollout_dir / f"rollout-2026-05-14T11-09-55-{OTHER_ID}.jsonl"
        self.other_rollout_path.write_text('{"type":"message","content":"keep"}\n', encoding="utf-8")
        self.unrelated_rollout_path = self.rollout_dir / f"rollout-2026-05-14T11-08-44-{UNRELATED_ID}.jsonl"
        self.unrelated_rollout_path.write_text('{"type":"message","content":"unrelated"}\n', encoding="utf-8")

        snapshots = self.codex_home / "shell_snapshots"
        snapshots.mkdir()
        self.snapshot_path = snapshots / f"{TARGET_ID}.1778728254740736000.sh"
        self.snapshot_path.write_text("export SECRET=value\n", encoding="utf-8")
        (snapshots / f"{OTHER_ID}.1778728195923723000.sh").write_text("keep\n", encoding="utf-8")
        (snapshots / f"{UNRELATED_ID}.1778728195923723001.sh").write_text("unrelated\n", encoding="utf-8")

        archived = self.codex_home / "archived_sessions"
        archived.mkdir()
        self.archived_path = archived / f"rollout-2026-05-14T11-10-54-{TARGET_ID}.jsonl"
        self.archived_path.write_text('{"archived":"secret"}\n', encoding="utf-8")
        (archived / f"rollout-2026-05-14T11-09-55-{OTHER_ID}.jsonl").write_text("keep\n", encoding="utf-8")
        (archived / f"rollout-2026-05-14T11-08-44-{UNRELATED_ID}.jsonl").write_text("unrelated\n", encoding="utf-8")

        self._create_state_db()
        self._create_logs_db()
        self._create_index()
        self._create_global_state()

    def tearDown(self):
        self.tmp.cleanup()

    def test_dry_run_reports_targets_without_modifying_storage(self):
        result = delete_session(
            self.codex_home,
            TARGET_ID,
            dry_run=True,
            assume_yes=True,
            current_thread_id=None,
        )

        self.assertTrue(result.dry_run)
        self.assertEqual(result.state_deletes["threads"], 2)
        self.assertEqual(result.log_deletes, 2)
        self.assertIn(self.rollout_path, result.files)
        self.assertIn(self.other_rollout_path, result.files)
        self.assertIn(self.snapshot_path, result.files)
        self.assertIn(self.archived_path, result.files)
        self.assertTrue(self.rollout_path.exists())
        self.assertTrue(self.other_rollout_path.exists())
        self.assertTrue(self.snapshot_path.exists())
        self.assertTrue(self.archived_path.exists())
        self.assertEqual(self._count("state_5.sqlite", "threads", TARGET_ID), 1)
        self.assertEqual(self._count("logs_2.sqlite", "logs", TARGET_ID), 1)
        self.assertIn(TARGET_ID, (self.codex_home / "session_index.jsonl").read_text(encoding="utf-8"))

    def test_delete_removes_session_content_logs_and_indexes(self):
        result = delete_session(
            self.codex_home,
            TARGET_ID,
            dry_run=False,
            assume_yes=True,
            current_thread_id=None,
        )

        self.assertFalse(result.dry_run)
        self.assertFalse(self.rollout_path.exists())
        self.assertFalse(self.snapshot_path.exists())
        self.assertFalse(self.archived_path.exists())
        self.assertFalse(self.other_rollout_path.exists())
        self.assertTrue(self.unrelated_rollout_path.exists())
        self.assertEqual(self._count("state_5.sqlite", "threads", TARGET_ID), 0)
        self.assertEqual(self._count("state_5.sqlite", "threads", OTHER_ID), 0)
        self.assertEqual(self._count("state_5.sqlite", "threads", UNRELATED_ID), 1)
        self.assertEqual(self._count("state_5.sqlite", "thread_dynamic_tools", TARGET_ID), 0)
        self.assertEqual(self._count("state_5.sqlite", "thread_goals", TARGET_ID), 0)
        self.assertEqual(self._count("state_5.sqlite", "stage1_outputs", TARGET_ID), 0)
        self.assertEqual(self._spawn_edge_count(TARGET_ID), 0)
        self.assertEqual(self._count("logs_2.sqlite", "logs", TARGET_ID), 0)
        self.assertEqual(self._count("logs_2.sqlite", "logs", OTHER_ID), 0)
        self.assertEqual(self._count("logs_2.sqlite", "logs", UNRELATED_ID), 1)
        self.assertNotIn(TARGET_ID, (self.codex_home / "session_index.jsonl").read_text(encoding="utf-8"))
        self.assertNotIn(OTHER_ID, (self.codex_home / "session_index.jsonl").read_text(encoding="utf-8"))
        global_state = json.loads((self.codex_home / ".codex-global-state.json").read_text(encoding="utf-8"))
        self.assertNotIn(TARGET_ID, global_state["pinned-thread-ids"])
        self.assertNotIn(OTHER_ID, global_state["pinned-thread-ids"])
        self.assertIn(UNRELATED_ID, global_state["pinned-thread-ids"])

    def test_delete_refuses_current_thread_without_force(self):
        with self.assertRaises(SessionDeleteError):
            delete_session(
                self.codex_home,
                TARGET_ID,
                dry_run=False,
                assume_yes=True,
                current_thread_id=TARGET_ID,
            )

    def test_delete_missing_thread_is_clear_noop(self):
        result = delete_session(
            self.codex_home,
            "019e0000-0000-7000-8000-000000000000",
            dry_run=False,
            assume_yes=True,
            current_thread_id=None,
        )

        self.assertFalse(result.found)
        self.assertEqual(result.state_deletes.get("threads", 0), 0)
        self.assertTrue(self.rollout_path.exists())

    def test_cli_list_json_exposes_app_contract(self):
        with self._capture_stdout() as output:
            exit_code = main(["--codex-home", str(self.codex_home), "list", "--limit", "10", "--json"])

        self.assertEqual(exit_code, 0)
        rows = json.loads(output.getvalue())
        self.assertEqual(rows[0]["id"], TARGET_ID)
        self.assertEqual(rows[0]["title"], "delete me")
        self.assertEqual(rows[0]["rollout_path"], str(self.rollout_path))
        self.assertEqual(rows[0]["cwd"], str(self.codex_home / "project-a"))
        child = next(row for row in rows if row["id"] == OTHER_ID)
        self.assertEqual(child["agent_role"], "worker")
        self.assertEqual(child["agent_nickname"], "Ada")
        self.assertEqual(child["parent_thread_id"], TARGET_ID)
        self.assertEqual(child["parent_title"], "delete me")

    def test_cli_delete_json_exposes_app_contract(self):
        with self._capture_stdout() as output:
            exit_code = main(
                [
                    "--codex-home",
                    str(self.codex_home),
                    "delete",
                    "--id",
                    TARGET_ID,
                    "--dry-run",
                    "--json",
                ]
            )

        self.assertEqual(exit_code, 0)
        payload = json.loads(output.getvalue())
        self.assertTrue(payload["dry_run"])
        self.assertEqual(payload["thread_id"], TARGET_ID)
        self.assertEqual(payload["thread_ids"], [TARGET_ID, OTHER_ID])
        self.assertEqual(payload["state_deletes"]["threads"], 2)
        self.assertEqual(payload["log_deletes"], 2)

    def _create_state_db(self):
        with sqlite3.connect(self.codex_home / "state_5.sqlite") as conn:
            conn.executescript(
                """
                CREATE TABLE threads (
                    id TEXT PRIMARY KEY,
                    rollout_path TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    source TEXT NOT NULL DEFAULT '',
                    model_provider TEXT NOT NULL DEFAULT '',
                    cwd TEXT NOT NULL DEFAULT '',
                    title TEXT NOT NULL,
                    sandbox_policy TEXT NOT NULL DEFAULT '',
                    approval_mode TEXT NOT NULL DEFAULT '',
                    archived INTEGER NOT NULL DEFAULT 0,
                    agent_role TEXT,
                    agent_nickname TEXT
                );
                CREATE TABLE thread_dynamic_tools (
                    thread_id TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL,
                    input_schema TEXT NOT NULL,
                    PRIMARY KEY(thread_id, position)
                );
                CREATE TABLE thread_goals (
                    thread_id TEXT PRIMARY KEY NOT NULL,
                    goal_id TEXT NOT NULL,
                    objective TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL
                );
                CREATE TABLE stage1_outputs (
                    thread_id TEXT PRIMARY KEY,
                    source_updated_at INTEGER NOT NULL,
                    raw_memory TEXT NOT NULL,
                    rollout_summary TEXT NOT NULL,
                    generated_at INTEGER NOT NULL
                );
                CREATE TABLE thread_spawn_edges (
                    parent_thread_id TEXT NOT NULL,
                    child_thread_id TEXT NOT NULL PRIMARY KEY,
                    status TEXT NOT NULL
                );
                """
            )
            project_a = self.codex_home / "project-a"
            project_a.mkdir()
            project_missing = self.codex_home / "missing-project"
            conn.execute(
                "INSERT INTO threads (id, rollout_path, created_at, updated_at, cwd, title) VALUES (?, ?, 1, 2, ?, ?)",
                (TARGET_ID, str(self.rollout_path), str(project_a), "delete me"),
            )
            conn.execute(
                "INSERT INTO threads (id, rollout_path, created_at, updated_at, cwd, title, agent_role, agent_nickname) VALUES (?, ?, 1, 2, ?, ?, 'worker', 'Ada')",
                (OTHER_ID, str(self.other_rollout_path), str(project_missing), "keep me"),
            )
            conn.execute(
                "INSERT INTO threads (id, rollout_path, created_at, updated_at, cwd, title) VALUES (?, ?, 1, 1, ?, ?)",
                (UNRELATED_ID, str(self.unrelated_rollout_path), str(project_a), "unrelated"),
            )
            conn.execute(
                "INSERT INTO thread_dynamic_tools VALUES (?, 0, 'tool', 'desc', '{}')",
                (TARGET_ID,),
            )
            conn.execute(
                "INSERT INTO thread_goals VALUES (?, 'goal', 'objective', 'active', 1, 2)",
                (TARGET_ID,),
            )
            conn.execute(
                "INSERT INTO stage1_outputs VALUES (?, 1, 'memory', 'summary', 2)",
                (TARGET_ID,),
            )
            conn.execute(
                "INSERT INTO thread_spawn_edges VALUES (?, ?, 'completed')",
                (TARGET_ID, OTHER_ID),
            )

    def _create_logs_db(self):
        with sqlite3.connect(self.codex_home / "logs_2.sqlite") as conn:
            conn.executescript(
                """
                CREATE TABLE logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts INTEGER NOT NULL,
                    ts_nanos INTEGER NOT NULL,
                    level TEXT NOT NULL,
                    target TEXT NOT NULL,
                    thread_id TEXT,
                    estimated_bytes INTEGER NOT NULL DEFAULT 0
                );
                """
            )
            conn.execute(
                "INSERT INTO logs (ts, ts_nanos, level, target, thread_id) VALUES (1, 0, 'INFO', 'codex', ?)",
                (TARGET_ID,),
            )
            conn.execute(
                "INSERT INTO logs (ts, ts_nanos, level, target, thread_id) VALUES (1, 0, 'INFO', 'codex', ?)",
                (OTHER_ID,),
            )
            conn.execute(
                "INSERT INTO logs (ts, ts_nanos, level, target, thread_id) VALUES (1, 0, 'INFO', 'codex', ?)",
                (UNRELATED_ID,),
            )

    def _create_index(self):
        rows = [
            {"id": TARGET_ID, "thread_name": "delete me", "updated_at": "2026-05-14T03:11:16Z"},
            {"id": OTHER_ID, "thread_name": "keep me", "updated_at": "2026-05-14T03:12:13Z"},
            {"id": UNRELATED_ID, "thread_name": "unrelated", "updated_at": "2026-05-14T03:10:13Z"},
        ]
        (self.codex_home / "session_index.jsonl").write_text(
            "".join(json.dumps(row) + "\n" for row in rows),
            encoding="utf-8",
        )

    def _create_global_state(self):
        state = {
            "pinned-thread-ids": [TARGET_ID, OTHER_ID, UNRELATED_ID],
            "nested": {"last": TARGET_ID, "keep": OTHER_ID, "unrelated": UNRELATED_ID},
        }
        (self.codex_home / ".codex-global-state.json").write_text(
            json.dumps(state),
            encoding="utf-8",
        )

    def _count(self, db_name, table, thread_id):
        column = "id" if table == "threads" else "thread_id"
        with sqlite3.connect(self.codex_home / db_name) as conn:
            return conn.execute(f"SELECT COUNT(*) FROM {table} WHERE {column} = ?", (thread_id,)).fetchone()[0]

    def _spawn_edge_count(self, thread_id):
        with sqlite3.connect(self.codex_home / "state_5.sqlite") as conn:
            return conn.execute(
                """
                SELECT COUNT(*) FROM thread_spawn_edges
                WHERE parent_thread_id = ? OR child_thread_id = ?
                """,
                (thread_id, thread_id),
            ).fetchone()[0]

    class _capture_stdout:
        def __enter__(self):
            import io
            import sys

            self._original = sys.stdout
            self._output = io.StringIO()
            sys.stdout = self._output
            return self._output

        def __exit__(self, exc_type, exc, tb):
            import sys

            sys.stdout = self._original
            return False


if __name__ == "__main__":
    unittest.main()
