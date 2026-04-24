```bash
#!/bin/bash
# Minimal Bash Coding Agent (Ollama + Gemma 4) - Pure Ubuntu tools only (no Python)

URL="http://localhost:11434/api/generate"
MODEL="gemma4"
HIST="/tmp/ca_$$.txt"
trap 'rm -f "$HIST"' EXIT

cat >"$HIST" <<'EOP'
You are a minimal coding agent. You have exactly one tool: run shell commands.
Use it by replying with this exact format and nothing after it:

<execute>
your command here
</execute>

Reason first if needed. After I reply with ===OBSERVATION=== continue your work.
When finished, reply normally without any <execute> block.
EOP

while true; do
  read -rp $'\nYou: ' input
  [[ $input =~ ^(quit|exit|q)$ ]] && break
  echo -e "\nUser: $input" >> "$HIST"

  while true; do
    # Pure sed JSON escaping (no Python, works on standard Ubuntu)
    escaped=$(sed -e 's/\\\\/\\\\\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g' \
              -e 's/\r/\\r/g' -e 's/\t/\\t/g' "$HIST")

    resp=$(curl -s "$URL" -H "Content-Type: application/json" \
      -d "{\"model\":\"$MODEL\",\"prompt\":\"$escaped\",\"stream\":false}" \
      | sed -n 's/.*"response":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g;s/\\"/"/g')

    echo -e "\nAgent:\n$resp"
    echo -e "\nAgent: $resp" >> "$HIST"

    if [[ $resp =~ \<execute\>(.*)\<\/execute\> ]]; then
      cmd="${BASH_REMATCH[1]}"
      echo -e "\n→ $cmd"
      out=$(timeout 30s bash -c "$cmd" 2>&1 || echo "[failed]")
      echo -e "\n===OBSERVATION===\n$out\n===================\n"
      echo -e "\n===OBSERVATION===\n$out\n===================\n" >> "$HIST"
      continue
    fi
    break
  done
done
```

**Done.** Same exact functionality as before, now 100% Python-free. Uses only `bash`, `curl`, `sed`, `timeout` — all standard on Ubuntu. Save, `chmod +x`, run. Enjoy the ultra-minimal agent!


```bash
#!/bin/bash
u=http://localhost:11434/api/chat;m=gemma4;h=/tmp/ca$$.json
trap 'rm -f "$h"' EXIT
cat >"$h" <<'EOT'
[{"role":"system","content":"Minimal coding agent. You have ONE tool: execute_command to run shell commands."}]
EOT
t='[{"type":"function","function":{"name":"execute_command","description":"Run a shell command","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}}]'

while read -rp $'\nYou: ' i;do [[ \( i =\~ ^(q|quit|exit) \) ]]&&break
jq --arg i "$i" '.+[{"role":"user","content":$i}]' "$h" >"$h.t"&&mv "$h.t" "$h"
while :;do r=$(curl -s "\( u" -H "Content-Type: application/json" -d " \)(jq -n --argjson msgs "$(cat "$h")" --argjson t "$t" --arg m "$m" '{model:$m,messages:$msgs,tools:$t,stream:false}')")
c=$(echo "$r"|jq -r '.message.content//""');echo -e "\nAgent:\n$c"
jq -c '.+[{"role":"assistant","content":$c}]' --arg c "$c" "$h" >"$h.t"&&mv "$h.t" "$h"
if echo "$r"|jq -e '.message.tool_calls[0]' >/dev/null;then
cmd=$(echo "$r"|jq -r '.message.tool_calls[0].function.arguments.command')
echo -e "\n→ \( cmd";o= \)(timeout 30s bash -c "$cmd" 2>&1||echo "[failed]")
jq --arg o "$o" '.+[{"role":"tool","content":$o}]' "$h" >"$h.t"&&mv "$h.t" "$h"
continue;fi;break;done;done
```

```bash
#!/bin/bash
u=http://localhost:11434/api/chat;m=gemma4;h=/tmp/ca$$.json;trap 'rm -f "$h"' EXIT;cat>"$h"<<E;t='[{"type":"function","function":{"name":"execute_command","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}}]'
[{"role":"system","content":"Minimal coding agent. Only use execute_command tool."}]
E
while read -rp $'\nYou: ' i;do[[ \( i =\~ ^(q|quit|exit) \) ]]&&break;jq --arg i "$i" '.+[{"role":"user","content":$i}]' "$h">"$h.t"&&mv "$h.t" "\( h";while :;do r= \)(curl -s "\( u" -H "Content-Type: application/json" -d " \)(jq -n --argjson m "\( m" --argjson msgs " \)(cat "$h")" --argjson t "$t" '{model:$m,messages:$msgs,tools:\( t,stream:false}')");c= \)(echo "$r"|jq -r '.message.content//""');echo -e "\nAgent:\n$c";jq -c '.+[{"role":"assistant","content":$c}]' --arg c "$c" "$h">"$h.t"&&mv "$h.t" "$h";if echo "\( r"|jq -e '.message.tool_calls[0]' >/dev/null;then cmd= \)(echo "$r"|jq -r '.message.tool_calls[0].function.arguments.command');echo -e "\n→ \( cmd";o= \)(timeout 30s bash -c "$cmd" 2>&1||echo "[failed]");jq --arg o "$o" '.+[{"role":"tool","content":$o}]' "$h">"$h.t"&&mv "$h.t" "$h";continue;fi;break;done;done

```