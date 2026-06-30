#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────
# Set these as environment variables or in a .env file

# Tempo API token (Tempo > Settings > API Integration)
TEMPO_API_TOKEN="${TEMPO_API_TOKEN:?Set TEMPO_API_TOKEN}"

# Jira Cloud credentials
JIRA_BASE_URL="${JIRA_BASE_URL:?Set JIRA_BASE_URL (e.g. https://yourorg.atlassian.net)}"
JIRA_EMAIL="${JIRA_EMAIL:?Set JIRA_EMAIL}"
JIRA_API_TOKEN="${JIRA_API_TOKEN:?Set JIRA_API_TOKEN}"

# Your Jira/Atlassian account ID (find via: GET /rest/api/3/myself)
JIRA_ACCOUNT_ID="${JIRA_ACCOUNT_ID:-}"

# JQL to find issues to log time against
JQL="${JQL:-assignee = currentUser()}"

# Hours per day (in seconds for Tempo API)
HOURS_PER_DAY="${HOURS_PER_DAY:-8}"
SECONDS_PER_DAY=$((HOURS_PER_DAY * 3600))

# ── Date range ─────────────────────────────────────────────────
# Default: current week (Monday to Friday)
get_week_dates() {
    local today
    today=$(date +%u)  # 1=Monday, 7=Sunday
    local monday_offset=$(( today - 1 ))

    local dates=()
    for i in 0 1 2 3 4; do
        local day_offset=$(( i - monday_offset ))
        if [[ "$(uname)" == "Darwin" ]]; then
            if [[ $day_offset -ge 0 ]]; then
                dates+=("$(date -v+"${day_offset}d" +%Y-%m-%d)")
            else
                dates+=("$(date -v"${day_offset}d" +%Y-%m-%d)")
            fi
        else
            dates+=("$(date -d "${day_offset} days" +%Y-%m-%d)")
        fi
    done
    echo "${dates[@]}"
}

# Build weekday list from a date range
dates_in_range() {
    local start_date="$1" end_date="$2"
    local result=()
    local current="$start_date"
    while [[ "$current" < "$end_date" || "$current" == "$end_date" ]]; do
        day_of_week=$(date -j -f "%Y-%m-%d" "$current" +%u 2>/dev/null || date -d "$current" +%u)
        if [[ "$day_of_week" -le 5 ]]; then
            result+=("$current")
        fi
        if [[ "$(uname)" == "Darwin" ]]; then
            current=$(date -j -v+1d -f "%Y-%m-%d" "$current" +%Y-%m-%d)
        else
            current=$(date -d "$current + 1 day" +%Y-%m-%d)
        fi
    done
    echo "${result[@]}"
}

# Get first and last day of last month
get_last_month_range() {
    if [[ "$(uname)" == "Darwin" ]]; then
        local first_of_this_month
        first_of_this_month=$(date -v1d +%Y-%m-%d)
        local last_of_last_month
        last_of_last_month=$(date -j -v-1d -f "%Y-%m-%d" "$first_of_this_month" +%Y-%m-%d)
        local first_of_last_month
        first_of_last_month=$(date -j -v1d -f "%Y-%m-%d" "$last_of_last_month" +%Y-%m-%d)
        echo "$first_of_last_month $last_of_last_month"
    else
        echo "$(date -d "$(date +%Y-%m-01) - 1 month" +%Y-%m-%d) $(date -d "$(date +%Y-%m-01) - 1 day" +%Y-%m-%d)"
    fi
}

# Get first day of this month through today
get_this_month_range() {
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "$(date -v1d +%Y-%m-%d) $(date +%Y-%m-%d)"
    else
        echo "$(date +%Y-%m-01) $(date +%Y-%m-%d)"
    fi
}

# Parse arguments
if [[ $# -eq 1 ]]; then
    case "$1" in
        --last-month)
            read -r start_date end_date <<< "$(get_last_month_range)"
            read -ra dates <<< "$(dates_in_range "$start_date" "$end_date")"
            ;;
        --this-month)
            read -r start_date end_date <<< "$(get_this_month_range)"
            read -ra dates <<< "$(dates_in_range "$start_date" "$end_date")"
            ;;
        *)
            echo "Usage: $0 [--last-month | --this-month | start_date end_date]"
            exit 1
            ;;
    esac
elif [[ $# -eq 2 ]]; then
    read -ra dates <<< "$(dates_in_range "$1" "$2")"
elif [[ $# -eq 0 ]]; then
    read -ra dates <<< "$(get_week_dates)"
else
    echo "Usage: $0 [--last-month | --this-month | start_date end_date]"
    exit 1
fi

echo "=== Tempo Time Logger ==="
echo "Dates: ${dates[*]}"
echo ""

# ── Resolve account ID if not set ──────────────────────────────
if [[ -z "$JIRA_ACCOUNT_ID" ]]; then
    echo "Resolving your Jira account ID..."
    JIRA_ACCOUNT_ID=$(curl -s \
        -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
        "${JIRA_BASE_URL}/rest/api/3/myself" | jq -r '.accountId')
    echo "Account ID: $JIRA_ACCOUNT_ID"
fi

# ── Query Jira for issues ─────────────────────────────────────
full_jql="${JQL} AND updated >= \"${dates[0]}\" ORDER BY updated DESC"
echo "Querying Jira: ${full_jql}"
issues_response=$(curl -s \
    -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    -G "${JIRA_BASE_URL}/rest/api/3/search/jql" \
    --data-urlencode "jql=${full_jql}" \
    --data-urlencode "fields=key,summary" \
    --data-urlencode "maxResults=50")

issue_count=$(echo "$issues_response" | jq '.issues | length')
if [[ "$issue_count" -eq 0 ]]; then
    echo "No issues found matching JQL query."
    exit 0
fi

echo "Found $issue_count issue(s):"
echo "$issues_response" | jq -r '.issues[] | "  [\(input_line_number)] \(.key) — \(.fields.summary)"' | awk '{gsub(/\[.*\]/, "["NR"]"); print}'
echo ""

# Let the user pick an issue
if [[ "$issue_count" -eq 1 ]]; then
    read -rp "Log time against $(echo "$issues_response" | jq -r '.issues[0].key')? [Y/n] " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo "Aborted."
        exit 0
    fi
    issue_key=$(echo "$issues_response" | jq -r '.issues[0].key')
else
    read -rp "Select issue [1-${issue_count}, q to quit]: " selection
    if [[ "$selection" == "q" ]]; then
        echo "Aborted."
        exit 0
    fi
    if [[ -z "$selection" ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt "$issue_count" ]]; then
        echo "Invalid selection."
        exit 1
    fi
    issue_key=$(echo "$issues_response" | jq -r ".issues[$((selection - 1))].key")
fi

echo ""
echo "Logging ${HOURS_PER_DAY}h/day against: $issue_key"
echo ""

# ── Check existing worklogs ────────────────────────────────────
echo "Checking existing worklogs..."
existing_worklogs=$(curl -s \
    -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.tempo.io/4/worklogs/user/${JIRA_ACCOUNT_ID}?from=${dates[0]}&to=${dates[${#dates[@]}-1]}")

# ── Log time for each date ─────────────────────────────────────
for date in "${dates[@]}"; do
    already_logged=$(echo "$existing_worklogs" | jq --arg d "$date" \
        '[.results[]? | select(.startDate == $d) | .timeSpentSeconds] | add // 0')

    if [[ "$already_logged" -ge "$SECONDS_PER_DAY" ]]; then
        echo "  $date — already logged ${HOURS_PER_DAY}h+, skipping"
        continue
    fi

    remaining=$((SECONDS_PER_DAY - already_logged))

    echo -n "  $date — logging $((remaining / 3600))h..."

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: Bearer ${TEMPO_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://api.tempo.io/4/worklogs" \
        -d "{
            \"issueKey\": \"${issue_key}\",
            \"timeSpentSeconds\": ${remaining},
            \"startDate\": \"${date}\",
            \"startTime\": \"09:00:00\",
            \"authorAccountId\": \"${JIRA_ACCOUNT_ID}\",
            \"description\": \"\"
        }")

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
        echo " done"
    else
        echo " FAILED (HTTP $http_code)"
        echo "    $(echo "$body" | jq -r '.errors // .message // .' 2>/dev/null || echo "$body")"
    fi
done

echo ""
echo "Done!"
