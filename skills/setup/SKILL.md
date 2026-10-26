---
name: setup
description: Guide an agent through installing and verifying the pi-guard plugin (herdr, Pi, jq, hook registration, duplicate-hook cleanup, first-denial check). Use when asked to set up, install, or troubleshoot pi-guard.
---

# pi-guard setup

Walk through the steps in order. Stop and report at the first step that fails; do not install tools for the person without saying what you are about to run.

## 1. Confirm the environment

- `echo $HERDR_ENV` must print `1`. If not, the session is not inside a herdr pane. The hook exits silently outside herdr, so pi-guard cannot work here. Tell the person to start Claude inside herdr.
- `herdr pane list` must print JSON with a `result.panes` array. If it errors, the herdr socket API is not reachable from this pane.
- `command -v pi jq` must print both paths. Missing `jq`: `brew install jq` (macOS) or `apt install jq` (Debian/Ubuntu). Missing `pi`: install Pi per its own docs; do not guess an install command.

## 2. Install the plugin

Ask the person to run at the Claude prompt:

```
/plugin install pi-guard --marketplace valerius21/mtcodi
```

They answer `y` to add the marketplace and pick a scope (user scope is right for a per-machine tool). Then confirm with `claude plugin list` that `pi-guard` appears.

## 3. Remove a hand-wired duplicate

If `~/.claude/settings.json` already has a `PermissionDenied` entry whose command ends in `pi-guard.sh`, remove that entry. With both the plugin and the settings entry present, every denial spawns the guard twice. Show the person the diff before saving.

## 4. Verify

The hook only fires on a real auto-mode denial of a Bash call, so there is no synthetic test. Instead:

- Start a session in auto mode inside herdr and work normally.
- After the first denial, check `$TMPDIR/pi-guard/`: `events.jsonl` holds the raw hook payload, `<id>.task.md` the brief Pi received, `<id>.verdict` Pi's answer starting with `EXECUTED` or `REJECTED`.
- A new pane labelled `pi <your pane label>` should sit to the right of the Claude pane in the same tab.
- Claude's transcript should show a message starting with `pi guard (pane ...)` carrying the verdict.

If `<id>.verdict` is missing, the hook's stderr shows the last 30 lines of the Pi pane instead; read them to see where Pi stopped.

## Known limits

- Two simultaneous denials can spawn two guard panes.
- herdr needs a few seconds to detect Pi as an agent on first start.
- A slow Pi verdict blocks Claude for up to the 900 s hook timeout.
