#!/bin/sh
# Runs test_gating.lua in every game mode and checks the results against the
# expected matrix. Run from the repository root.
set -e

# A co-op Host appears as two rows because it really is two Lua states. Exactly
# one of them must run the server half; both running it is the fault that let a
# single death be judged twice, with opposite answers.
expected="dedicated server=true client=false
coophost-server server=true client=false
coophost-client server=false client=true
client server=false client=true
singleplayer server=false client=false"

actual=""
for mode in dedicated coophost-server coophost-client client singleplayer; do
    actual="$actual$(lua5.1 PZMods/PermadeathLock/tests/test_gating.lua $mode)
"
done

actual=$(printf '%s' "$actual" | sed '/^$/d')

if [ "$actual" = "$expected" ]; then
    printf '%s\n\nall modes gate correctly\n' "$actual"
else
    printf 'FAILED\n\nexpected:\n%s\n\nactual:\n%s\n' "$expected" "$actual"
    exit 1
fi
