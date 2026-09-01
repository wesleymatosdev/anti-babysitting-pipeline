#!/usr/bin/env bash
set -euo pipefail

HERMES_ROOT="${HERMES_HOME:-$HOME/.hermes}"
DB="${KANBAN_DB:-$HERMES_ROOT/kanban/boards/wesley-priorities/kanban.db}"

if [[ ! -f "$DB" ]]; then
  printf 'board_state=missing\npath=%s\n' "$DB"
  exit 0
fi

run_snapshot_query() {
  # $1 = database file to read; stderr suppressed — degraded paths emit
  # board_state=unreadable instead of leaking sqlite parse noise.
  sqlite3 -readonly -batch -noheader -separator '|' "$1" 2>/dev/null <<'SQL'
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
}

# The live board DB is WAL-mode and sits next to a running dispatcher that
# checkpoints and holds the -shm/-wal sidecars. A plain `sqlite3 -readonly`
# open needs those sidecars and can fail with CANTOPEN (14) while they are
# missing or locked; even the copy fallback can race a checkpoint. Retry the
# whole ladder a few times so a transient contention window never flips the
# monitor hash and wakes the paid agent. The monitor never exits non-zero and
# never mutates the live board.

attempt_read() {
  local out=""
  # 1. Direct readonly open, with brief retries.
  for _ in 1 2 3; do
    if out="$(run_snapshot_query "$DB")" && [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      return 0
    fi
    sleep 0.3
  done
  # 2. Private filesystem copy of the main DB file. Sidecars are copied only
  #    when present; a sidecar-less copy reflects the last WAL checkpoint,
  #    which may lag by a few events — acceptable for a change-detector that
  #    re-runs every tick, versus failing outright. Never opens the live DB
  #    read-write; never touches the original.
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/kanban-monitor.XXXXXX")"
  local rc=1
  if cp "$DB" "$tmpdir/kanban.db" 2>/dev/null \
     && [[ -f "$DB-shm" ]] && cp "$DB-shm" "$tmpdir/kanban.db-shm" 2>/dev/null \
     && [[ -f "$DB-wal" ]] && cp "$DB-wal" "$tmpdir/kanban.db-wal" 2>/dev/null \
     && out="$(run_snapshot_query "$tmpdir/kanban.db")" && [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    rc=0
  fi
  rm -rf "$tmpdir"
  return "$rc"
}

out=""
for _ in 1 2 3; do
  if out="$(attempt_read)"; then
    break
  fi
  out=""
  sleep 1
done

if [[ -z "$out" ]]; then
  printf 'board_state=unreadable\npath=%s\n' "$DB"
  exit 0
fi

printf '%s\n' "$out"