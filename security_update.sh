#!/bin/bash

# Shhh bang, I see a lot of people talking about using a #!/usr/bin/env bash
# and I will ask about this in class

# Standard error mitigation, a little unclear on the specifics am flagging to ask
# about in class
set -euo pipefail

# Was going to use ./ but ended up having log files in multiple places
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$PROJECT_DIR/updates.log"
LASTRUN="$PROJECT_DIR/lastrun"

# Lets make a function for logging
# Lets make it verbose and log at the same time using tee
log ()
{
    # $* joins all the passed arguments
    printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*" | tee -a "$LOG_FILE"
}

log "Starting check"

# Lets check the distro
if [[ ! -r /etc/os-release ]]; then
    log "Cannot read /etc/os-release" >&2 # To an error stream
    exit 1
fi

source /etc/os-release

# Only Ubuntu may add Debian if I get enough time
if [[ "${ID:-}" != "ubuntu" ]]; then
    # We know that ubuntu supplies an ID: that is short but maybe in another case
    # it won't so lets create an unknown fallback
    log "Sorry, Unsupported Distribution: ${ID:-unknown}" >&2
    exit 1
fi

# Okay so we're staging some thing here in hopes of adding additional support later
# A lot might have to change for say Debian but that's yet to be seen
DISTRO="$ID"
CODENAME="${VERSION_CODENAME:-}"
FEED_URL="https://ubuntu.com/security/notices/rss.xml"

# Have to get more specific than ubuntu, my release is Noble
if [[ -z "$CODENAME"  ]]; then
    log  "Cannot determine Ubuntu release codename" >&2
    exit 1
fi

log "Distribution: $DISTRO"
log "Release: $CODENAME"
log "Security Feed: $FEED_URL"

# Lets create a tmp director and a trap to remove it when we are done
# using mktmp and including the XXXXXX so it can create a random stamp
# there avoiding any possible conflicts, escape -- ensures a -X
# in the next part doesn't continue command options
WORK_DIR="$(mktemp -d /tmp/security-update.XXXXXX)"
trap 'rm -rf -- "$WORK_DIR"' EXIT

FEED_FILE="$WORK_DIR/feed.xml"

log "Downloading security feed"

if curl --fail --silent --show-error --location --connect-timeout 15 \
    --max-time 60 "$FEED_URL" --output "$FEED_FILE" 2>> "$LOG_FILE"; then
    log "Successfully retrieved security feed!"
else
    log "Security feed retrieval failed; see $LOG_FILE for details" >&2
    exit 1
fi

# Okay we've successfully pulled xml, lets get our timestamp and update it
if [[ -f "$LASTRUN" ]]; then
    LASTRUN_TIME="$(stat -c %Y "$LASTRUN")"
    log "Previous download timestamp: $LASTRUN_TIME"
else
    LASTRUN_TIME=""
    log "First run will process all entries in the feed"
fi


touch "$LASTRUN"

SOURCE_FILE="$WORK_DIR/source-packages.txt"

python3 "$PROJECT_DIR/process_xml.py" "$FEED_FILE" "$LASTRUN_TIME" "$CODENAME" "$SOURCE_FILE" 2>&1 |
    tee -a "$LOG_FILE"

log "Source packages selected:"
cat "$SOURCE_FILE" | tee -a "$LOG_FILE"

# Lets see what we have installed, this is probably a big list
INSTALLED_FILE="$WORK_DIR/installed-packages.txt"

#  -W show records -f output format, I used AI to help me figure this one
# out we used a tab delimeter here \t
dpkg-query -W \
    -f='${binary:Package}\t${source:Package}\t${db:Status-Status}\n' \
    > "$INSTALLED_FILE"

# Collect installed binaries whose source appears in our list.
# here we initialize an empty array ()
packages_to_update=()

# Okay we read this back in, it's probably huge
while IFS=$'\t' read -r binary source status; do
    # unfortunately dpkg can return  removed packages who have orphans
    # hanging around the system, skip this line if != installed
    if [[ "$status" != "installed" ]]; then
        continue
    fi

    # Oh grep, tell me if my package is in this file, then and only then
    # add it to packages_to_update
    if grep -Fxq -- "$source" "$SOURCE_FILE"; then
        packages_to_update+=("$binary")
        log "Installed possibly compromised binary found: $binary"
    fi
done < "$INSTALLED_FILE"  # This is so cool I love this redirect


if [[ ${#packages_to_update[@]} -eq 0 ]]; then
    log "No matching installed packages"
else
    # this is where we run as a root cron job
    # or a sudo, but I think is enough
    log "Proposed update command:"
    printf 'apt-get install --only-upgrade'
    printf ' %q' "${packages_to_update[@]}"
    printf '\n'
fi
