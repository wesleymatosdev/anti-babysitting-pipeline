# Anti-babysitting pipeline

Small, deterministic support code for Hermes's autonomous Kanban supervisor.

`wesley-priorities` in Hermes Kanban is the source of truth. The monitor emits a stable snapshot of the board's event cursor, status counts, and non-completed cards. Hermes cron hashes that output and wakes its supervisor only when the board changes, avoiding repeated paid model calls when nothing happened.

## Files

- `scripts/kanban-monitor.sh` — read-only SQLite monitor. Override `KANBAN_DB` in tests; otherwise it resolves the active Hermes home and `wesley-priorities` board.
- `tests/test-kanban-monitor.sh` — proves identical state is byte-stable and that a task event changes the snapshot.

## Verification

    bash -n scripts/kanban-monitor.sh tests/test-kanban-monitor.sh
    bash tests/test-kanban-monitor.sh

## Safety boundary

The monitor is read-only. The cron supervisor may commit code, push branches, and open a bot-account staging PR. It must never merge, deploy, publish, mutate live Hermes runtime, or promote a bot-staged contribution through `wesleymatosdev` without Wesley's explicit approval.
