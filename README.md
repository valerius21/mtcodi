# pi-guard

Claude Code plugin. When auto mode denies a Bash call, a Pi agent in a sibling herdr pane reads the transcript, judges the command, and either runs it unchanged (verdict `EXECUTED` plus output) or refuses (`REJECTED` plus reason). The hook then wakes Claude with the verdict.

Outside herdr (`HERDR_ENV` unset) the hook does nothing and the plain denial stands.

## Prerequisites

- herdr with its socket API (`herdr pane list` works from the Claude pane)
- `pi` on PATH
- `jq`

## Install

```
/plugin install pi-guard --marketplace valerius21/mtcodi
```

Answer `y` to add the marketplace, then pick a scope. If you previously wired `pi-guard.sh` by hand in `~/.claude/settings.json`, remove that PermissionDenied entry, or the guard fires twice per denial.

## Setup skill

The plugin ships a `setup` skill. Ask an agent to "set up pi-guard" and it checks herdr, Pi and jq, installs the plugin, removes a hand-wired duplicate hook, and tells you how to verify the first denial.

## Where it writes

`$TMPDIR/pi-guard/`: `events.jsonl` (raw hook payloads), `<id>.task.md` (the brief Pi gets), `<id>.verdict` (Pi's answer).

## Known limits

- Two simultaneous denials can spawn two guard panes.
- herdr needs a few seconds to detect Pi as an agent on first start.
- A slow Pi verdict blocks Claude for up to the 900 s hook timeout.
