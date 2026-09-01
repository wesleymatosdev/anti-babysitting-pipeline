#!/usr/bin/env bash
set -euo pipefail

HERMES_ROOT="${HERMES_HOME:-$HOME/.hermes}"
DB="${KANBAN_DB:-$HERMES_ROOT/kanban/boards/wesley-priorities/kanban.db}"

if [[ ! -f "$DB" ]]; then
  printf 'board_state=missing\npath=%s\n' "$DB"
  exit 0
fi

sqlite3 -readonly -batch -noheader -separator '|' "$DB" <<'SQL'
SELECT 'event_max', COALESCE(MAX(id), 0) FROM task_events;
SELECT 'status_count', status, COUNT(*)
FROM tasks
GROUP BY status
ORDER BY status;
SELECT 'task', id, status, priority, COALESCE(assignee, ''),
       COALESCE(current_run_id, ''), consecutive_failures,
       REPLACE(REPLACE(COALESCE(last_failure_error, ''), char(10), ' '), '|', '/')
FROM tasks
WHERE status NOT IN ('done', 'archived')
ORDER BY priority DESC, created_at ASC, id ASC;
SQL
