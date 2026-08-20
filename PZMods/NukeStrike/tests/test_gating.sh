#!/bin/sh
# Runs test_gating.lua in every game mode and checks the results against the
# expected matrix. Run from the repository root.
#
# Unlike Permadeath Lock, this mod is meant to work in single player too, so the
# single player row has BOTH halves live: one Lua state is the server and the
# player at the same time.
set -e

expected="dedicated server=true client=false
coophost server=true client=true
client server=false client=true
singleplayer server=true client=true"

actual=""
for mode in dedicated coophost client singleplayer; do
    actual="$actual$(lua5.1 PZMods/NukeStrike/tests/test_gating.lua $mode)
"
done

actual=$(printf '%s' "$actual" | sed '/^$/d')

if [ "$actual" = "$expected" ]; then
    printf '%s\n\nall modes gate correctly\n' "$actual"
else
    printf 'FAILED\n\nexpected:\n%s\n\nactual:\n%s\n' "$expected" "$actual"
    exit 1
fi
