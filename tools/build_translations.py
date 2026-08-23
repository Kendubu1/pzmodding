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
MOD = os.path.join(ROOT, "PZMods", "PermadeathLock")
TAIL = os.path.join("media", "lua", "shared", "Translate", "EN")
SOURCE = os.path.join(MOD, "common", TAIL)
TARGETS = [os.path.join(MOD, "common", TAIL), os.path.join(MOD, "42", TAIL)]

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


def main():
    names = sorted(n for n in os.listdir(SOURCE) if n.endswith("_EN.txt"))
    if not names:
        raise SystemExit("no *_EN.txt found in " + SOURCE)

    for name in names:
        entries = parse(os.path.join(SOURCE, name))
        with open(os.path.join(SOURCE, name), encoding="utf-8") as handle:
            text = handle.read()

        # Sandbox_EN.txt -> Sandbox.json
        stem = name[: -len("_EN.txt")]
        body = json.dumps(dict(entries), indent=4, ensure_ascii=False) + "\n"

        for target in TARGETS:
            os.makedirs(target, exist_ok=True)
            with open(os.path.join(target, name), "w", encoding="utf-8") as handle:
                handle.write(text)
            with open(os.path.join(target, stem + ".json"), "w", encoding="utf-8") as handle:
                handle.write(body)

        print("%-18s %2d keys -> %s_EN.txt + %s.json" % (stem, len(entries), stem, stem))
    return 0


if __name__ == "__main__":
    sys.exit(main())
