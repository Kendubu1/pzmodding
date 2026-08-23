"""Find out which folder Project Zomboid actually reads translations from.

    python3 tools/translation_probe.py --stamp     # before testing
    python3 tools/translation_probe.py --clear     # after, before publishing

A multi-version mod can put its translations in three places, and the game
reads exactly one of them. Which one is not answerable from the repo: getting
it wrong is silent, the game renders the key instead of the sentence and logs
nothing about it. Guessing has cost several rounds already.

So instead of guessing: --stamp puts a different marker in each copy. Boot the
game and look at a Fate Token's tooltip, or the sandbox page name. Whichever
marker appears names the folder the game read - and the other two can then be
deleted for good.

  Fate Token [42]      -> the version folder wins
  Fate Token [common]  -> common/ wins
  Fate Token [root]    -> the bare mod root wins
  no marker at all     -> none of them is read, and the cause is elsewhere

--clear strips the markers again. Run it before publishing.
"""
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(ROOT, "PZMods", "PermadeathLock")
TAIL = os.path.join("media", "lua", "shared", "Translate", "EN")

# common/ is the canonical copy: the other two are rebuilt from it.
COPIES = [
    ("common", os.path.join(MOD, "common", TAIL)),
    ("42", os.path.join(MOD, "42", TAIL)),
    ("root", os.path.join(MOD, TAIL)),
]
CANONICAL = COPIES[0][1]

# Matches with or without a leading space: the page-name marker is appended
# ("Fate Token [42]") and the tooltip marker is prepended ("[42] Death..."),
# and a pattern that only caught the first left the second to accumulate.
MARKER = re.compile(r" ?\[(?:root|common|42)\] ?")


def strip(text):
    return MARKER.sub("", text)


def rewrite(path, fn):
    with open(path, encoding="utf-8") as handle:
        before = handle.read()
    after = fn(strip(before))
    if after != before:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(after)


def sync():
    """Rebuild every copy from the canonical one, markers removed."""
    for _, folder in COPIES:
        os.makedirs(folder, exist_ok=True)
        for name in sorted(os.listdir(CANONICAL)):
            if not name.endswith(".txt"):
                continue
            target = os.path.join(folder, name)
            if os.path.abspath(target) != os.path.abspath(os.path.join(CANONICAL, name)):
                shutil.copyfile(os.path.join(CANONICAL, name), target)
            rewrite(target, lambda text: text)


def stamp(label, folder):
    # The sandbox page name, which shows in the settings screen...
    rewrite(os.path.join(folder, "Sandbox_EN.txt"),
            lambda text: text.replace('Sandbox_PermadeathLock = "Fate Token"',
                                      'Sandbox_PermadeathLock = "Fate Token [%s]"' % label))
    # ...and the item tooltip, which shows in an inventory.
    rewrite(os.path.join(folder, "Tooltip_EN.txt"),
            lambda text: text.replace('Tooltip_FateToken = "',
                                      'Tooltip_FateToken = "[%s] ' % label))


def main():
    if "--stamp" not in sys.argv and "--clear" not in sys.argv:
        print(__doc__)
        return 1

    sync()
    if "--stamp" in sys.argv:
        for label, folder in COPIES:
            stamp(label, folder)
        print("Stamped. Copy the mod folder over, boot, and look at a Fate Token's")
        print("tooltip or the sandbox page name. The marker names the winning folder.")
    else:
        print("Markers cleared; all three copies rebuilt from common/.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
