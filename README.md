# Codex Session Cleaner

Local macOS utility for inspecting and permanently removing Codex sessions from
`~/.codex`.

The app automatically scans the default Codex home, groups sessions by project,
keeps sub-agent sessions nested under their parent session, supports an inspect
step before deletion, and then deletes rollout files, local indexes, SQLite
thread rows, related logs, shell snapshots, archived copies, and pinned-state
references.

## Install

Download the latest `CodexSessionCleaner.dmg` from GitHub Releases, open it, and
drag `CodexSessionCleaner.app` to Applications.

The local DMG is ad-hoc signed for personal distribution. If macOS blocks the
first launch, right-click the app and choose Open.

## Run

```bash
./script/build_and_run.sh
```

The script builds and launches:

```text
dist/CodexSessionCleaner.app
```

To build the DMG installer:

```bash
./script/package_dmg.sh
```

## CLI

The app wraps the same Python deletion core:

```bash
python3 codex_session_delete.py list --limit 20
python3 codex_session_delete.py delete --id <thread-id> --dry-run
python3 codex_session_delete.py delete --id <thread-id> --yes
```

Deletion is permanent. Use dry-run first for any session whose contents you may
still need.
