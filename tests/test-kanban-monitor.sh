#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONITOR="$ROOT/scripts/kanban-monitor.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DB="$TMP/kanban.db"

sqlite3 "$DB" <<'SQL'
CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  priority INTEGER DEFAULT 0,
  assignee TEXT,
  current_run_id INTEGER,
  consecutive_failures INTEGER NOT NULL DEFAULT 0,
  last_failure_error TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE task_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
INSERT INTO tasks(id,status,priority,created_at) VALUES('t_ready','ready',100,1);
INSERT INTO task_events(task_id,kind,created_at) VALUES('t_ready','created',1);
SQL

first="$(KANBAN_DB="$DB" "$MONITOR")"
second="$(KANBAN_DB="$DB" "$MONITOR")"
[[ "$first" == "$second" ]] || { printf 'monitor output is not deterministic\n' >&2; exit 1; }
[[ "$first" == *'event_max|1'* ]] || { printf 'missing event cursor\n' >&2; exit 1; }
[[ "$first" == *'task|t_ready|ready|100'* ]] || { printf 'missing ready task\n' >&2; exit 1; }

sqlite3 "$DB" <<'SQL'
UPDATE tasks SET status='running', current_run_id=7 WHERE id='t_ready';
INSERT INTO task_events(task_id,kind,created_at) VALUES('t_ready','claimed',2);
SQL
third="$(KANBAN_DB="$DB" "$MONITOR")"
[[ "$third" != "$first" ]] || { printf 'state change did not change monitor output\n' >&2; exit 1; }
[[ "$third" == *'event_max|2'* ]] || { printf 'event cursor did not advance\n' >&2; exit 1; }
[[ "$third" == *'task|t_ready|running|100||7|0|'* ]] || { printf 'running state missing\n' >&2; exit 1; }

# WAL-mode DB: a readonly open can transiently fail with CANTOPEN while the
# -shm/-wal sidecars are absent or locked by a concurrent writer. The monitor
# must still produce a complete snapshot (via retry or copy fallback), exit 0,
# and never report board_state=missing for a DB that exists.
cp "$DB" "$TMP/wal.db"
sqlite3 "$TMP/wal.db" "PRAGMA journal_mode=wal;" >/dev/null
sqlite3 "$TMP/wal.db" "INSERT INTO task_events(task_id,kind,created_at) VALUES('t_ready','claimed',3);
UPDATE tasks SET current_run_id=8 WHERE id='t_ready';" >/dev/null
wal_out="$(KANBAN_DB="$TMP/wal.db" "$MONITOR")"
[[ "$wal_out" == *'event_max|3'* ]] || { printf 'WAL-mode snapshot missing event cursor\n' >&2; exit 1; }
[[ "$wal_out" == *'task|t_ready|running|100||8|0|'* ]] || { printf 'WAL-mode snapshot missing running state\n' >&2; exit 1; }
# A committed WAL write without a checkpoint must still be visible to the
# fallback path if the readonly open fails.
rm -f "$TMP/wal.db-shm" "$TMP/wal.db-wal"
# Recreate a wal sidecar pair by opening rw once; then hide the shm again and
# make the directory read-only so sqlite cannot recreate it.
sqlite3 "$TMP/wal.db" "SELECT 1;" >/dev/null
chmod 555 "$TMP"
ro_out="$(KANBAN_DB="$TMP/wal.db" "$MONITOR")"
ro_exit=$?
chmod 755 "$TMP"
[[ "$ro_exit" -eq 0 ]] || { printf 'monitor exited non-zero on unreadable dir\n' >&2; exit 1; }
[[ "$ro_out" == *'task|t_ready|running|100||8|0|'* ]] || { printf 'fallback snapshot incomplete\n' >&2; exit 1; }
[[ "$ro_out" != *'board_state=unreadable'* ]] || { printf 'fallback should have recovered the snapshot\n' >&2; exit 1; }

# A corrupt/garbage DB file must degrade gracefully, never exit non-zero.
printf 'not a database at all' > "$TMP/junk.db"
junk_out="$(KANBAN_DB="$TMP/junk.db" "$MONITOR")" || { printf 'monitor exited non-zero on junk DB\n' >&2; exit 1; }
[[ "$junk_out" == *'board_state=unreadable'* ]] || { printf 'junk DB should report board_state=unreadable\n' >&2; exit 1; }

printf 'kanban-monitor tests: PASS\n'