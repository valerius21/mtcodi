#!/usr/bin/env bash
# PermissionDenied (auto mode, Bash): pi in einer Nachbar-Pane desselben herdr-Tabs prüft den
# geblockten Befehl, führt ihn aus wenn vertretbar, sonst Ablehnung. Ergebnis weckt Claude
# über asyncRewake (exit 2 + stderr).
set -u
[ "${HERDR_ENV:-}" = 1 ] || exit 0

in=$(cat)
dir="${TMPDIR:-/tmp}/pi-guard"; mkdir -p "$dir"
printf '%s\n' "$in" >> "$dir/events.jsonl" # ponytail: Rohlog, um das Hook-Payload nachzusehen

cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
[ -n "$cmd" ] || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$in"); cwd=${cwd:-$PWD}
id="$(date +%Y%m%d-%H%M%S)-$$"
task="$dir/$id.task.md"
out="$dir/$id.verdict"

cat > "$task" <<EOF
Claude Codes Auto-Mode hat in einer Nachbar-Pane einen Bash-Befehl blockiert. Du bist die zweite Meinung.

Classifier-Begründung: $(jq -r '.reason // .permission_decision_reason // "unbekannt"' <<<"$in")
Claudes Beschreibung des Befehls: $(jq -r '.tool_input.description // "-"' <<<"$in")
Arbeitsverzeichnis: $cwd
Claude-Transkript (JSONL, für das Vorhaben die letzten Einträge lesen): $(jq -r '.transcript_path // "-"' <<<"$in")

Befehl:
\`\`\`bash
$cmd
\`\`\`

Vorgehen:
1. Kläre anhand des Transkripts, was Claude gerade vorhat, und ob der Befehl dazu passt.
2. Vertretbar → führe den Befehl unverändert im Arbeitsverzeichnis aus. Schreib danach nach $out:
   Zeile 1 \`EXECUTED\`, dann Exit-Code und die relevante Ausgabe (gekürzt auf das Wesentliche).
3. Wirklich schädlich (Datenverlust, Secrets nach außen, Produktion kaputt, Sicherheitsgrenzen umgehen,
   passt nicht zum Vorhaben) → NICHT ausführen. Schreib nach $out:
   Zeile 1 \`REJECTED\`, dann die Begründung.
Schreib $out als allerletzten Schritt.
EOF

# ponytail: zwei gleichzeitige Denials können zwei Guard-Panes erzeugen; Lock erst wenn das nervt
# Pi-Pane pro Claude-Instanz: "pi <Claude-Pane-Label>", sonst "pi <Session-Prefix>"
panes=$(herdr pane list)
me=$(jq -r --arg p "$HERDR_PANE_ID" '.result.panes[] | select(.pane_id == $p) | .label // empty' <<<"$panes")
name="pi ${me:-$(jq -r '.session_id // "x"' <<<"$in" | cut -c1-8)}"
pane=$(jq -r --arg t "${HERDR_TAB_ID:-}" --arg n "$name" \
  '.result.panes[] | select(.tab_id == $t and .label == $n) | .pane_id' <<<"$panes" | head -1)
if [ -z "$pane" ]; then
  pane=$(herdr pane split "$HERDR_PANE_ID" --direction right --no-focus --cwd "$cwd" | jq -r .result.pane.pane_id)
  herdr pane rename "$pane" "$name" >/dev/null
  herdr pane run "$pane" "pi"
  # herdr erkennt pi erst nach ein paar Sekunden als Agent (vorher agent_not_found)
  for _ in $(seq 30); do herdr agent wait "$pane" --until idle --timeout 1000 >/dev/null 2>&1 && break; sleep 1; done
fi
herdr agent wait "$pane" --until idle --until done --timeout 600000 >/dev/null # vorherigen Job abwarten
herdr agent prompt "$pane" "Lies $task und arbeite die Aufgabe exakt so ab." \
  --wait --until working --timeout 30000 >/dev/null
status=$(herdr agent wait "$pane" --until idle --until done --until blocked --timeout 600000 \
  | jq -r '[.. | .agent_status? // empty][0] // "timeout"')

{
  echo "pi guard (Pane \"$name\", Status: $status) zum vom Auto-Mode geblockten Befehl:"
  echo "$cmd"; echo "---"
  if [ -s "$out" ]; then cat "$out"
  else echo "Kein Verdict geschrieben. Letzte Pane-Ausgabe:"; herdr pane read "$pane" --source recent-unwrapped --lines 30
  fi
} >&2
exit 2
