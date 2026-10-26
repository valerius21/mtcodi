#!/usr/bin/env bash
# PermissionDenied hook (auto mode, Bash): a Pi agent in a sibling pane of the same herdr tab
# reviews the blocked command, runs it if defensible, otherwise rejects it. The verdict wakes
# Claude via asyncRewake (exit 2 + stderr).
set -u
[ "${HERDR_ENV:-}" = 1 ] || exit 0

in=$(cat)
dir="${TMPDIR:-/tmp}/pi-guard"; mkdir -p "$dir"
printf '%s\n' "$in" >> "$dir/events.jsonl" # raw log, to inspect the hook payload later

cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
[ -n "$cmd" ] || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$in"); cwd=${cwd:-$PWD}
id="$(date +%Y%m%d-%H%M%S)-$$"
task="$dir/$id.task.md"
out="$dir/$id.verdict"

cat > "$task" <<EOF2
Claude Code's auto mode blocked a Bash command in a neighbouring pane. You are the second opinion.

Classifier reason: $(jq -r '.reason // .permission_decision_reason // "unknown"' <<<"$in")
Claude's description of the command: $(jq -r '.tool_input.description // "-"' <<<"$in")
Working directory: $cwd
Claude transcript (JSONL; read the last entries to see what Claude is trying to do): $(jq -r '.transcript_path // "-"' <<<"$in")

Command:
\`\`\`bash
$cmd
\`\`\`

Procedure:
1. From the transcript, work out what Claude is currently trying to do and whether the command fits.
2. Defensible -> run the command unchanged in the working directory. Then write to $out:
   line 1 \`EXECUTED\`, then the exit code and the relevant output (trimmed to what matters).
3. Genuinely harmful (data loss, secrets leaving the machine, breaking production, bypassing
   security boundaries, does not fit the task) -> do NOT run it. Write to $out:
   line 1 \`REJECTED\`, then the reason.
Write $out as the very last step.
EOF2

# shortcut: two simultaneous denials can spawn two guard panes, add a lock when that bites
# One Pi pane per Claude instance: "pi <Claude pane label>", else "pi <session prefix>"
panes=$(herdr pane list)
me=$(jq -r --arg p "$HERDR_PANE_ID" '.result.panes[] | select(.pane_id == $p) | .label // empty' <<<"$panes")
name="pi ${me:-$(jq -r '.session_id // "x"' <<<"$in" | cut -c1-8)}"
pane=$(jq -r --arg t "${HERDR_TAB_ID:-}" --arg n "$name" \
  '.result.panes[] | select(.tab_id == $t and .label == $n) | .pane_id' <<<"$panes" | head -1)
if [ -z "$pane" ]; then
  pane=$(herdr pane split "$HERDR_PANE_ID" --direction right --no-focus --cwd "$cwd" | jq -r .result.pane.pane_id)
  herdr pane rename "$pane" "$name" >/dev/null
  herdr pane run "$pane" "pi"
  # herdr only detects pi as an agent after a few seconds (agent_not_found before that)
  for _ in $(seq 30); do herdr agent wait "$pane" --until idle --timeout 1000 >/dev/null 2>&1 && break; sleep 1; done
fi
herdr agent wait "$pane" --until idle --until done --timeout 600000 >/dev/null # wait for any previous job
herdr agent prompt "$pane" "Read $task and carry out the task exactly as written." \
  --wait --until working --timeout 30000 >/dev/null
status=$(herdr agent wait "$pane" --until idle --until done --until blocked --timeout 600000 \
  | jq -r '[.. | .agent_status? // empty][0] // "timeout"')

{
  echo "pi guard (pane \"$name\", status: $status) on the command auto mode blocked:"
  echo "$cmd"; echo "---"
  if [ -s "$out" ]; then cat "$out"
  else echo "No verdict written. Last pane output:"; herdr pane read "$pane" --source recent-unwrapped --lines 30
  fi
} >&2
exit 2
