#!/usr/bin/env bash
# Runs discord-relay.sh against a fake game process, fake logs and a fake curl.
#   bash mods/PelicanConsole/tests/discord-relay.sh
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)/discord-relay.sh
ROOT=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] && cat "$ROOT/posts.txt"; rm -rf "$ROOT"' EXIT
MODS=$ROOT/SCUM/Binaries/Win64/ue4ss/Mods
mkdir -p "$ROOT/SCUM/Saved/Logs" "$MODS/PelicanConsole" "$MODS/ScumAntiCheat" "$MODS/PlayerTools" "$ROOT/bin"
cp "$SRC" "$MODS/PelicanConsole/"
: > "$ROOT/SCUM/Saved/Logs/SCUM.log"; : > "$MODS/ScumAntiCheat/anticheat.log"; : > "$MODS/PlayerTools/reports.log"
cat > "$ROOT/bin/curl" <<'CURL'
#!/usr/bin/env bash
cat >> "$POSTS"; echo >> "$POSTS"; printf 204
CURL
chmod +x "$ROOT/bin/curl"
export POSTS=$ROOT/posts.txt PATH="$ROOT/bin:$PATH" DISCORD_BATCH_SECONDS=1 SERVER_NAME='Exclsv "UK"'

failures=0; count=0
check() { count=$((count + 1)); if ! eval "$2"; then failures=$((failures + 1)); echo "FAIL: $1"; fi; }

run() {   # run <seconds the fake game lives> <script that writes the logs>
    : > "$POSTS"
    sleep "$1" & local game=$!
    (cd "$ROOT" && bash "$MODS/PelicanConsole/discord-relay.sh" $game) > "$ROOT/relay.out" 2>&1 & local relay=$!
    sleep 1.5; eval "$2"; wait $game; wait $relay
}

export DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/123/abc-DEF
run 6 '
    echo "LogSCUM: Global Stats: 1 players" >> "$ROOT/SCUM/Saved/Logs/SCUM.log"
    echo "LogSCUM: Global Stats: 2 players" >> "$ROOT/SCUM/Saved/Logs/SCUM.log"
    printf "20:01:00 [ExclsvAntiCheat] Packet: moved 900 m in 1 s [strike 1/3]\r\n" >> "$MODS/ScumAntiCheat/anticheat.log"
    echo "20:01:06 [ExclsvAntiCheat] Settings reloaded (action=kick)." >> "$MODS/ScumAntiCheat/anticheat.log"
    echo "20:02:00 [ExclsvAntiCheat] Kicked Pa\`cket: 3 strikes." >> "$MODS/ScumAntiCheat/anticheat.log"
    echo "2026-10-12 20:03 Bob reports @everyone Eve: \"flying\" \\ car" >> "$MODS/PlayerTools/reports.log"
'
posts=$(cat "$POSTS")
check "starting posted with the server name (quotes escaped)" '[[ $posts == *"\"username\":\"Exclsv \\\"UK\\\"\""* && $posts == *"is starting."* ]]'
check "online posted once" '[ "$(grep -o "is online" "$POSTS" | wc -l)" -eq 1 ]'
check "strike posted, carriage return dropped" '[[ $posts == *"[strike 1/3]\`"* ]]'
check "reload noise left out" '[[ $posts != *"Settings reloaded"* ]]'
check "backtick in a name cannot break the code block" '[[ $posts == *"Kicked Pa'"'"'cket"* ]]'
check "report posted, quotes and backslash escaped" '[[ $posts == *"Report: \`2026-10-12 20:03 Bob reports @everyone Eve: \\\"flying\\\" \\\\ car\`"* ]]'
check "mentions never ping" '[[ $posts == *"\"allowed_mentions\":{\"parse\":[]}"* ]]'
check "lines batched (strike and kick in one post)" 'grep -q "strike 1/3.*Kicked" "$POSTS"'
check "stopped posted after the game ends" '[[ $(tail -n1 "$POSTS") == *"has stopped."* ]]'
check "every post is valid JSON" 'while IFS= read -r p; do [ -z "$p" ] || printf "%s" "$p" | python3 -c "import json,sys; json.load(sys.stdin)" || exit 1; done < "$POSTS"'

export DISCORD_FEED=flags
run 4 'echo "x Bob reports Eve" >> "$MODS/PlayerTools/reports.log"; echo "x [ExclsvAntiCheat] SPECTATE Eve: aim" >> "$MODS/ScumAntiCheat/anticheat.log"'
posts=$(cat "$POSTS")
check "DISCORD_FEED=flags: only flags" '[[ $posts == *SPECTATE* && $posts != *reports* && $posts != *starting* && $posts != *stopped* ]]'
unset DISCORD_FEED

export DISCORD_WEBHOOK_URL=https://evil.example.com/api/webhooks/1/x
run 2 ':'
check "non-Discord URL refused, nothing posted" '[ ! -s "$POSTS" ] && grep -q "not a Discord webhook URL" "$ROOT/relay.out"'

# The egg's real startup command, with a fake wine: the relay starts with the game, logs that
# appear later are followed, the game's exit code is passed on and the relay gets to say goodbye.
EGG=$(cd "$(dirname "$0")/../../.." && pwd)/scum/egg-scum.yaml
python3 -c "import re,sys,yaml; c=yaml.safe_load(open(sys.argv[1]))['startup_commands']['Default']; print(re.sub(r'\{\{[A-Z_]+\}\}','1',c))" "$EGG" > "$ROOT/startup.sh"
rm -f "$ROOT/SCUM/Saved/Logs/SCUM.log" "$MODS/ScumAntiCheat/anticheat.log" "$MODS/PlayerTools/reports.log"
cat > "$ROOT/bin/wine" <<'WINE'
#!/usr/bin/env bash
sleep 2; echo "LogSCUM: Global Stats: 0" >> SCUM/Saved/Logs/SCUM.log
sleep 1; echo "t [ExclsvAntiCheat] Banned Eve (added to BannedUsers.ini): aimbot." >> SCUM/Binaries/Win64/ue4ss/Mods/ScumAntiCheat/anticheat.log
sleep 3; exit 3
WINE
chmod +x "$ROOT/bin/wine"
: > "$POSTS"
export DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/123/abc-DEF
(cd "$ROOT" && timeout 30 bash startup.sh < /dev/null > /dev/null 2>&1); code=$?
posts=$(cat "$POSTS")
check "egg: game exit code passed on" '[ "$code" -eq 3 ]'
check "egg: starting, online, flag and stopped all posted" '[[ $posts == *"is starting."* && $posts == *"is online."* && $posts == *"Banned Eve"* && $posts == *"has stopped."* ]]'
unset DISCORD_WEBHOOK_URL
: > "$POSTS"
# Save backups on start: SCUM.db (and its -wal) copied, only the newest 14 kept.
SAVES="$ROOT/SCUM/Saved/SaveFiles"
mkdir -p "$SAVES/ExclsvBackups"
printf 'db' > "$SAVES/SCUM.db"; printf 'wal' > "$SAVES/SCUM.db-wal"
for day in $(seq -w 1 15); do
    printf 'old' > "$SAVES/ExclsvBackups/SCUM-2026-01-$day-0000.db"; printf 'old' > "$SAVES/ExclsvBackups/SCUM-2026-01-$day-0000.db-wal"
    touch -d "2026-01-$day" "$SAVES/ExclsvBackups/SCUM-2026-01-$day-0000.db"
done
(cd "$ROOT" && timeout 30 bash startup.sh < /dev/null > "$ROOT/start.out" 2>&1); code=$?
check "egg: no webhook, no relay, same exit code" '[ "$code" -eq 3 ] && [ ! -s "$POSTS" ]'
newest=$(ls -1t "$SAVES/ExclsvBackups"/SCUM-*.db | head -1)
check "egg: save backed up on start, with its -wal" '[ "$(cat "$newest")" = db ] && [ "$(cat "$newest-wal")" = wal ] && grep -q "Save backed up to SaveFiles/ExclsvBackups/" "$ROOT/start.out"'
check "egg: only the newest 14 backups kept, -wal files with them" '[ "$(ls -1 "$SAVES/ExclsvBackups"/SCUM-*.db | wc -l)" -eq 14 ] && [ ! -e "$SAVES/ExclsvBackups/SCUM-2026-01-01-0000.db" ] && [ ! -e "$SAVES/ExclsvBackups/SCUM-2026-01-02-0000.db-wal" ] && [ -e "$SAVES/ExclsvBackups/SCUM-2026-01-15-0000.db" ]'

echo
echo "$count checks, $failures failed"
[ "$failures" -eq 0 ]
