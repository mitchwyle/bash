
#!/usr/bin/env bash
# check-author-pubs.sh
# Cron-friendly RSS watcher for new story/book announcements.
# Only mails when something new appears.

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIGURATION – edit these
# ---------------------------------------------------------------------------

TO="you@example.com"
FROM="rss-watcher@$(hostname -s)"

# Array of RSS / Atom feed URLs
FEEDS=(
  "https://www.rifters.com/crawl/?feed=rss2"                          # Peter Watts
  "https://approachingpavonis.blogspot.com/feeds/posts/default"       # Alastair Reynolds
  "https://www.jamessacorey.com/feed/"                                # James S.A. Corey
  "https://marthawells.dreamwidth.org/data/rss"                       # Martha Wells
  # more authors added here
)

# Smarter filter: announcement-style phrases (case-insensitive).
# Applied first to <title>, then (only if needed) to the whole item.
# Leave empty (INTERESTING='') to accept every new item.
INTERESTING='(
  new[[:space:]]+(story|novella|novel|book|fiction|piece|tale)|
  (just[[:space:]]+)?(published|released|out[[:space:]]+now|available[[:space:]]+now)|
  (free[[:space:]]+(story|fiction|read|download)|story[[:space:]]+is[[:space:]]+(free|online|available))|
  (my[[:space:]]+new|announcing|publication[[:space:]]+of|now[[:space:]]+available)|
  (out[[:space:]]+in|appeared[[:space:]]+in|published[[:space:]]+in)[[:space:]]+(the[[:space:]]+)?[A-Za-z]
)'

STATE_DIR="${HOME}/.cache/author-rss"
STATE_FILE="${STATE_DIR}/seen_ids.txt"

# Temporary working directory
TMPDIR="${TMPDIR:-/tmp}"
WORKDIR=$(mktemp -d "${TMPDIR}/rsscheck.XXXXXX")
trap 'rm -rf "$WORKDIR"' EXIT

NEW_ITEMS_FILE="${WORKDIR}/new_items.txt"
: > "$NEW_ITEMS_FILE"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

send_mail() {
  local subject="$1"
  local body="$2"
  {
    echo "From: $FROM"
    echo "To: $TO"
    echo "Subject: $subject"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/plain; charset=utf-8"
    echo
    echo "$body"
  } | sm
}

# Extract a unique ID for an <item> or <entry>. Prefer <guid>, then <id>, then <link>
item_id() {
  local item="$1"
  local id
  id=$(echo "$item" | grep -oP '(?<=<guid[^>]*>)[^<]+' | head -1)
  [[ -z "$id" ]] && id=$(echo "$item" | grep -oP '(?<=<id[^>]*>)[^<]+' | head -1)
  [[ -z "$id" ]] && id=$(echo "$item" | grep -oP '(?<=<link[^>]*>)[^<]+' | head -1)
  [[ -z "$id" ]] && id=$(echo "$item" | grep -oP 'href="[^"]+"' | head -1 | cut -d'"' -f2)
  echo "${id:-unknown}"
}

# Pretty-print the interesting bits of an item for the email body
format_item() {
  local item="$1"
  local title link pubdate desc

  title=$(echo "$item" | grep -oP '(?<=<title[^>]*>)[^<]+' | head -1 \
          | sed 's/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g')
  link=$(echo "$item"  | grep -oP '(?<=<link[^>]*>)[^<]+' | head -1)
  [[ -z "$link" ]] && link=$(echo "$item" | grep -oP 'href="[^"]+"' | head -1 | cut -d'"' -f2)
  pubdate=$(echo "$item" | grep -oP '(?<=<pubDate[^>]*>)[^<]+' | head -1)
  [[ -z "$pubdate" ]] && pubdate=$(echo "$item" | grep -oP '(?<=<published[^>]*>)[^<]+' | head -1)
  [[ -z "$pubdate" ]] && pubdate=$(echo "$item" | grep -oP '(?<=<updated[^>]*>)[^<]+' | head -1)
  desc=$(echo "$item"  | grep -oP '(?<=<description[^>]*>)[^<]+' | head -1)
  [[ -z "$desc" ]] && desc=$(echo "$item" | grep -oP '(?<=<summary[^>]*>)[^<]+' | head -1)
  [[ -z "$desc" ]] && desc=$(echo "$item" | grep -oP '(?<=<content[^>]*>)[^<]+' | head -1)

  cat <<EOF
Title:   $title
Link:    $link
Date:    $pubdate

$desc

----------------------------------------
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

for feed in "${FEEDS[@]}"; do
  feedfile="$WORKDIR/$(echo "$feed" | md5sum | cut -c1-12).xml"
  if ! curl -sS --max-time 30 -A "author-rss-checker/1.0" -o "$feedfile" "$feed"; then
    echo "Warning: failed to fetch $feed" >&2
    continue
  fi

  # Split the feed into individual <item> or <entry> blocks
  # (handles both RSS 2.0 and Atom reasonably well)
  awk '
    /<(item|entry)[ >]/ { initem=1; buf=$0; next }
    initem { buf = buf "\n" $0 }
    /<\/(item|entry)>/ {
      if (initem) {
        print buf
        print "====ITEM_END===="
        initem=0
        buf=""
      }
    }
  ' "$feedfile" | while IFS= read -r -d '====ITEM_END====' item; do
    [[ -z "${item//[[:space:]]/}" ]] && continue

    id=$(item_id "$item")
    [[ "$id" == "unknown" ]] && continue

    # Already seen?
    if grep -Fxq "$id" "$STATE_FILE"; then
      continue
    fi

    # Decide whether this item is an announcement
    interesting=false
    if [[ -z "$INTERESTING" ]]; then
      interesting=true
    else
      # Prefer the title – far fewer false positives
      title=$(echo "$item" | grep -oP '(?<=<title[^>]*>)[^<]+' | head -1)
      if echo "$title" | grep -qiE "$INTERESTING"; then
        interesting=true
      # Fall back to the whole item only if the title didn't match
      elif echo "$item" | grep -qiE "$INTERESTING"; then
        interesting=true
      fi
    fi

    # Always record the ID so we never look at it again
    echo "$id" >> "$STATE_FILE"

    if $interesting; then
      format_item "$item" >> "$NEW_ITEMS_FILE"
    fi
  done
done

# Deduplicate the state file (keep it tidy)
sort -u "$STATE_FILE" -o "$STATE_FILE"

# Send mail only if we found something
if [[ -s "$NEW_ITEMS_FILE" ]]; then
  subject="New publication announcement(s) – $(date +%Y-%m-%d)"
  body=$(cat "$NEW_ITEMS_FILE")
  send_mail "$subject" "$body"
fi
