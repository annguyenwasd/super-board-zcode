#!/usr/bin/env python3
"""super-board-settings.py — merge into .zcode/config.json without losing anything.

    super-board-settings.py zcode-hooks <.zcode/config.json> <snippet.json> [...] [--dry-run]

`zcode-hooks` adds each hook command from the snippets once per event + matcher
(install.sh and onboard's protect-main step) into a ZCode workspace config:
ZCode wraps them one level deeper
(`hooks.events.<Event>`) and runs config-file hooks only when `hooks.enabled`
is true, so that flag is set whenever new hook commands were added (an existing
`enabled: false` survives a no-op re-run). Before merging, the pre-ZCode
Claude-Code residue is migrated away: pack-owned guard commands still in the
dead top-level `hooks.<Event>` shape, or under `hooks.events` matchers naming
tools ZCode lacks (MultiEdit, NotebookEdit), are removed so the merge re-adds
them in the live shape; hooks belonging to other tools are never touched.
`allow` adds permission rules to
`permissions.allow` once each (onboard's Permissions step, after the user
approved the printed diff). All keep every existing key, back the file up
(`config.json.bak-<ts>`) before writing, write
atomically, and leave an invalid JSON file untouched. `--dry-run` prints what
would be removed (`- <line>`) and added (`+ <line>`) and writes nothing.

Exit: 0 ok (including "already present"), 2 the target file is invalid, 64 usage.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys
import time

# Pack-owned hooks: super-board's own guard scripts. Anything else (another
# tool's hooks) is never removed.
PACK_GUARD_RE = re.compile(r"guard-[A-Za-z0-9_.-]*\.py|cleanup-wt\.py")
# Tools ZCode does not have; a matcher naming them is Claude-Code-era residue.
DEAD_TOOL_RE = re.compile(r"MultiEdit|NotebookEdit")


def pack_owned(command: str) -> bool:
    return bool(PACK_GUARD_RE.search(command))


def load(path: str):
    if not os.path.exists(path):
        return {}
    try:
        data = json.load(open(path))
    except ValueError as e:
        print(f"    ✗ {path} is not valid JSON ({e}); left untouched — merge by hand", file=sys.stderr)
        sys.exit(2)
    if not isinstance(data, dict):
        print(f"    ✗ {path} is not a JSON object; left untouched", file=sys.stderr)
        sys.exit(2)
    return data


def save(path: str, data: dict) -> None:
    if os.path.exists(path):
        backup = f"{path}.bak-{time.strftime('%Y%m%d%H%M%S')}"
        shutil.copy2(path, backup)
        print(f"    ✓ backup: {backup}")
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def merge_events(events: dict, snippets: list[dict]) -> list[str]:
    added = []
    for event, entries in [kv for s in snippets for kv in s["hooks"].items()]:
        current = events.setdefault(event, [])
        for entry in entries:
            matcher = entry.get("matcher")
            target = next((e for e in current if e.get("matcher") == matcher), None)
            if target is None:
                target = {"matcher": matcher} if matcher is not None else {}
                target["hooks"] = []
                current.append(target)
            have = {h.get("command") for e in current if e.get("matcher") == matcher
                    for h in e.get("hooks", [])}
            for h in entry["hooks"]:
                if h["command"] not in have:
                    target.setdefault("hooks", []).append(h)
                    have.add(h["command"])
                    added.append(f"{event} {matcher or '*'}: {h['command']}")
    return added


def migrate(settings: dict) -> list[str]:
    """Remove pack-owned hooks still in Claude-Code shapes; foreign hooks stay.

    Two residue shapes: (1) top-level `hooks.<Event>` lists beside `hooks.events`
    — ZCode only reads `hooks.events.<Event>`, so those entries are dead; (2)
    `hooks.events` entries whose matcher names tools ZCode lacks (MultiEdit,
    NotebookEdit). Pack-owned commands (guard-*.py, cleanup-wt.py) are stripped
    so the merge re-adds them in the live shape; returns the removed commands.
    """
    removed: list[str] = []
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return removed

    def strip(entry: dict) -> bool:
        """Drop pack-owned hook commands from one entry. False = entry is empty."""
        hook_list = entry.get("hooks")
        if not isinstance(hook_list, list):
            return True
        pack, kept = [], []
        for h in hook_list:
            (pack if isinstance(h, dict) and pack_owned(h.get("command", "")) else kept).append(h)
        if not pack:
            return True
        removed.extend(h.get("command", "") for h in pack)
        if not kept:
            return False
        entry["hooks"] = kept
        return True

    for event, entries in list(hooks.items()):
        if event == "events" or not isinstance(entries, list):
            continue
        kept = [e for e in entries if not (isinstance(e, dict) and strip(e) is False)]
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    events = hooks.get("events")
    if isinstance(events, dict):
        for event, entries in events.items():
            if not isinstance(entries, list):
                continue
            kept = []
            for entry in entries:
                if isinstance(entry, dict) and DEAD_TOOL_RE.search(entry.get("matcher") or ""):
                    if strip(entry):
                        kept.append(entry)
                else:
                    kept.append(entry)
            events[event] = kept
    return removed


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    args = [a for a in argv if a != "--dry-run"]
    if len(args) < 3 or args[0] != "zcode-hooks":
        print(__doc__, file=sys.stderr)
        return 64
    verb, path, rest = args[0], args[1], args[2:]
    settings = load(path)
    events = settings.setdefault("hooks", {}).setdefault("events", {})
    removed = migrate(settings)
    added = merge_events(events, [json.load(open(p)) for p in rest])
    if added:
        settings["hooks"]["enabled"] = True
    noun = "zcode hook command(s)"
    if not added and not removed:
        print("    ✓ already present — nothing to change")
        return 0
    if dry:
        for r in removed:
            print(f"- {r}")
        for a in added:
            print(f"+ {a}")
        return 0
    save(path, settings)
    if removed:
        print(f"    ✓ migrated: removed {len(removed)} pre-ZCode hook entries")
    print(f"    ✓ {len(added)} {noun} added")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
