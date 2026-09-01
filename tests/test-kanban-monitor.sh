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

printf 'kanban-monitor tests: PASS\n'
