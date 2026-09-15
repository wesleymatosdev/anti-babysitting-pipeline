#!/bin/bash
# Sandbox driver: runs the REAL kanban-stall-watch.sh against a fake HOME with a
# stub hermes CLI. Verifies grace, cooldown, counting, and STALLED TWICE surfacing.
set -u
FH=/tmp/stall-sandbox
rm -rf $FH/fakehome $FH/empty_ws $FH/calls.txt
mkdir -p $FH/fakehome/.hermes/hermes-agent/venv/bin $FH/fakehome/.hermes/cron/output $FH/fakehome/.hermes/logs $FH/empty_ws
cp $FH/stub-hermes.sh $FH/fakehome/.hermes/hermes-agent/venv/bin/hermes
chmod +x $FH/fakehome/.hermes/hermes-agent/venv/bin/hermes
cp ~/.hermes/scripts/kanban-stall-watch.sh $FH/kanban-stall-watch.sh
export FAKHOME=$FH
export KANBAN_STALL_BASE=$FH/fakehome/.hermes
export KANBAN_STALL_GRACE_S=0
S=$FH/kanban-stall-watch.sh
LASTF=$KANBAN_STALL_BASE/cron/output/kanban-stall-last.txt

echo "=== RUN 1 (grace 0 -> first stall: comment+reclaim recorded, stall#1, LAST gains line, no TWICE) ==="
out1=$(bash $S)
[ -z "$out1" ] && echo "PASS: stdout empty on first stall" || echo "FAIL: unexpected stdout: $out1"
echo "calls:"; cat $FH/calls.txt
echo "counts:"; cat $KANBAN_STALL_BASE/cron/output/kanban-stall-counts.txt
echo "LAST:"; cat "$LASTF"
grep -q "^t_test1234 [0-9]*$" "$LASTF" && echo "PASS: LAST has '<tid> <epoch>' line" || echo "FAIL: LAST missing task line"

echo "=== RUN 2 (45min cooldown should block: no new calls, no TWICE) ==="
before=$(wc -l < $FH/calls.txt)
out2=$(bash $S)
after=$(wc -l < $FH/calls.txt)
[ "$before" = "$after" ] && echo "PASS: cooldown blocked (calls unchanged at $after)" || echo "FAIL: cooldown did not block ($before -> $after)"
[ -z "$out2" ] && echo "PASS: no spurious STALLED TWICE on cooldown tick" || echo "FAIL: stdout on cooldown tick: $out2"
echo "counts after run2 (expect only stall#1):"; cat $KANBAN_STALL_BASE/cron/output/kanban-stall-counts.txt

echo "=== RUN 3 (cooldown line removed -> stall again -> STALLED TWICE on stdout) ==="
: > "$LASTF"
out3=$(bash $S)
case "$out3" in
  *"STALLED TWICE: kanban task t_test1234"*) echo "PASS: STALLED TWICE surfaced";;
  *) echo "FAIL: STALLED TWICE not printed; stdout was: $out3";;
esac
echo "counts final (expect stall#1 and stall#2):"; cat $KANBAN_STALL_BASE/cron/output/kanban-stall-counts.txt
echo "calls final:"; cat $FH/calls.txt
