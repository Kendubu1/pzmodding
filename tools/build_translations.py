"""Build the mod's translation files from one source.

    python3 tools/build_translations.py

Build 42.15 changed the format. Up to 42.14 a translation file was a Lua table
in `Name_EN.txt`; from 42.15 it is a flat JSON object in `Name.json`, in the
same folder, with the language suffix dropped from the filename:

    42.14 and earlier   Translate/EN/Sandbox_EN.txt    Sandbox_EN = { ... }
    42.15 and later     Translate/EN/Sandbox.json      { "key": "text", ... }

A build only reads its own format and ignores the other, and being wrong is
silent - the game renders the key instead of the sentence and logs nothing. So
both are shipped, and both are generated here from the .txt so they cannot
drift: the .txt files under common/ are the source, everything else is output.

Outputs, per file:
    common/media/lua/shared/Translate/EN/Name_EN.txt   (the source itself)
    common/media/lua/shared/Translate/EN/Name.json
    42/media/lua/shared/Translate/EN/Name_EN.txt
    42/media/lua/shared/Translate/EN/Name.json
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAIL = os.path.join("media", "lua", "shared", "Translate", "EN")


def mod(*parts):
    return os.path.join(ROOT, "PZMods", *parts)


# One entry per mod: where the .txt source lives, and which folders get built
# output. A Build 41 folder gets .txt only - Build 41 cannot read the JSON - so
# it is listed as a plain target and the writer skips the .json there.
#
# This mirrors what a large dual-build mod ships: both formats side by side in
# 42/, and .txt alone in the Build 41 tree.
MODS = [
    {
        "name": "PermadeathLock",
        "source": mod("PermadeathLock", "Contents", "mods", "PermadeathLock", "common", TAIL),
        "both": [
            mod("PermadeathLock", "Contents", "mods", "PermadeathLock", "common", TAIL),
            mod("PermadeathLock", "Contents", "mods", "PermadeathLock", "42", TAIL),
        ],
        "txt_only": [],
    },
    {
        # JunkJet is still shipped for Build 41 as well, so common/ stays plain
        # .txt - that is the tree Build 41 reads - and 42/ carries both.
        "name": "JunkJet",
        "source": mod("JunkJet", "common", TAIL),
        "both": [mod("JunkJet", "42", TAIL)],
        "txt_only": [mod("JunkJet", "common", TAIL)],
    },
]

# One `key = "value",` pair. The value may contain escaped quotes; nothing in
# these files spans a line.
ENTRY = re.compile(r'^\s*\[?"?([A-Za-z_][A-Za-z0-9_.]*)"?\]?\s*=\s*"(.*)"\s*,?\s*$')


def parse(path):
    """Read a Name_EN.txt into an ordered list of (key, value)."""
    entries = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if not stripped or stripped.startswith("--") or stripped.endswith("{") \
                    or stripped == "}":
                continue
            match = ENTRY.match(line)
            if match is None:
                raise SystemExit("%s: cannot parse line:\n  %s" % (path, stripped))
            entries.append((match.group(1), match.group(2)))
    return entries


def build(spec):
    source = spec["source"]
    if not os.path.isdir(source):
        print("%s: no %s, skipped" % (spec["name"], os.path.relpath(source, ROOT)))
        return

    names = sorted(n for n in os.listdir(source) if n.endswith("_EN.txt"))
    if not names:
        print("%s: no *_EN.txt in %s, skipped" % (spec["name"], os.path.relpath(source, ROOT)))
        return

    print(spec["name"])
    for name in names:
        entries = parse(os.path.join(source, name))
        with open(os.path.join(source, name), encoding="utf-8") as handle:
            text = handle.read()

        # Sandbox_EN.txt -> Sandbox.json
        stem = name[: -len("_EN.txt")]
        body = json.dumps(dict(entries), indent=4, ensure_ascii=False) + "\n"

        for target in spec["both"] + spec["txt_only"]:
            os.makedirs(target, exist_ok=True)
            with open(os.path.join(target, name), "w", encoding="utf-8") as handle:
                handle.write(text)

        for target in spec["both"]:
            with open(os.path.join(target, stem + ".json"), "w", encoding="utf-8") as handle:
                handle.write(body)

        print("  %-14s %2d keys -> %s_EN.txt + %s.json" % (stem, len(entries), stem, stem))


def main():
    for spec in MODS:
        build(spec)
    return 0


if __name__ == "__main__":
    sys.exit(main())
