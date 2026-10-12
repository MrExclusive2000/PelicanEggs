#!/usr/bin/env bash
# ExclsvSCUM Discord feed. Started by the SCUM egg next to the game when the egg's
# DISCORD_WEBHOOK_URL variable is set; stops when the game stops.
#
#   bash discord-relay.sh <SCUM pid>
#
# Posts to the webhook, batched every few seconds (Discord allows about 30 posts a minute):
#   - server online / stopped                                  (feed: status)
#   - anti-cheat strikes, kicks, bans and spectate flags       (feed: flags)
#   - player reports sent with !report                         (feed: reports)
# DISCORD_FEED picks which ("status,flags,reports" by default). Mentions such as @everyone
# are never turned into pings. Nothing here reads or changes the game; it only reads the
# mods' log files.

SCUM_PID=${1:?usage: discord-relay.sh <SCUM pid>}
URL=${DISCORD_WEBHOOK_URL:-}
FEED=",${DISCORD_FEED:-status,flags,reports},"
NAME=${DISCORD_NAME:-${SERVER_NAME:-SCUM server}}
BATCH_SECONDS=${DISCORD_BATCH_SECONDS:-5}
MAX_CHARS=1800

HERE=$(cd "$(dirname "$0")" && pwd)
MODS=$(dirname "$HERE")
# Started from the server folder by the egg.
GAME_LOG=${SCUM_LOG:-$PWD/SCUM/Saved/Logs/SCUM.log}
ANTICHEAT_LOG=$MODS/ScumAntiCheat/anticheat.log
REPORTS_LOG=$MODS/PlayerTools/reports.log

say() { echo "[ExclsvDiscord] $*"; }

case "$URL" in
    https://discord.com/api/webhooks/*|https://discordapp.com/api/webhooks/*|https://ptb.discord.com/api/webhooks/*|https://canary.discord.com/api/webhooks/*) ;;
    *) say "DISCORD_WEBHOOK_URL is not a Discord webhook URL; the feed is off."; exit 0 ;;
esac
command -v curl >/dev/null 2>&1 || { say "curl is not available in this container; the feed is off."; exit 0; }

wants() { [[ $FEED == *",$1,"* ]]; }

# JSON string body: escape backslashes, quotes and newlines; drop other control characters.
json() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=$(printf '%s' "$s" | tr -d '\000-\011\013-\037')
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}

post() {
    local text=$1 code attempt
    [ -z "$text" ] && return
    local body="{\"username\":\"$(json "$NAME")\",\"content\":\"$(json "$text")\",\"allowed_mentions\":{\"parse\":[]}}"
    for attempt in 1 2 3; do
        code=$(printf '%s' "$body" | curl -sS -m 10 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data-binary @- "$URL" 2>/dev/null)
        case "$code" in
            2*) return 0 ;;
            429) sleep $((attempt * 2)) ;;
            *) say "Discord answered HTTP ${code:-error}; message dropped."; return 1 ;;
        esac
    done
    say "Discord kept rate-limiting; message dropped."
}

# Discord markdown would mangle names with * _ ~ ` | >; show lines as plain text.
plain() {
    local s=$1
    s=${s//\`/\'}
    printf '%s' "$s"
}

FLAG_PATTERN='\[strike [0-9]+/[0-9]+\]|\bKicked\b|\bBanned\b|has now been kicked|\bSUSPECT\b|\bSPECTATE\b|while aiming at least|snapped [0-9]+ degrees|has admin rights but|ran an admin command but|Watchlisted player online'

buffer=""
flush() {
    [ -n "$buffer" ] && post "$buffer"
    buffer=""
}
add() {
    local line=$1
    if [ $(( ${#buffer} + ${#line} + 1 )) -gt $MAX_CHARS ]; then
        flush
    fi
    line=${line:0:$MAX_CHARS}
    buffer=${buffer:+$buffer$'\n'}$line
}

wants status && post ":hourglass_flowing_sand: **$NAME** is starting."

# One tail per log, each line tagged with its source. --pid ends them when the game stops.
# Only the game log's "online" line is passed on; its other chatter never reaches bash.
feed() {
    tail -n0 -F "$GAME_LOG" --pid="$SCUM_PID" 2>/dev/null | grep --line-buffered -m1 'LogSCUM: Global Stats:' | sed -u 's/^/G /' &
    tail -n0 -F "$ANTICHEAT_LOG" --pid="$SCUM_PID" 2>/dev/null | sed -u 's/^/A /' &
    tail -n0 -F "$REPORTS_LOG" --pid="$SCUM_PID" 2>/dev/null | sed -u 's/^/R /' &
    wait
}

# read -t can time out halfway through a line; what it read so far is kept in $part and
# carried over, so the rest of the line is not mistaken for a new one.
carry=""
while true; do
    if IFS= read -r -t "$BATCH_SECONDS" part; then
        line=$carry$part
        carry=""
        line=${line%$'\r'}
        text=${line:2}
        [ -z "$text" ] && continue
        case "$line" in
            "G "*) wants status && add ":white_check_mark: **$NAME** is online." ;;
            "A "*) wants flags && [[ $text =~ $FLAG_PATTERN ]] && add ":shield: \`$(plain "$text")\`" ;;
            "R "*) wants reports && add ":loudspeaker: Report: \`$(plain "$text")\`" ;;
        esac
    else
        [ $? -gt 128 ] || break   # > 128: timed out, so send what is waiting; otherwise the game stopped
        carry=$carry$part
        flush
    fi
done < <(feed)

flush
wants status && post ":octagonal_sign: **$NAME** has stopped."
exit 0
