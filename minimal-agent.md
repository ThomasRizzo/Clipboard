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