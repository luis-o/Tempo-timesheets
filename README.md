# Tempo Time Logger

Shell script to automatically log time in [Tempo Timesheets](https://www.tempo.io/) (Jira Cloud) by querying Jira for your assigned issues.

## Features

- Finds issues via JQL query (default: your assigned issues, any status, updated within the date range)
- Interactive issue selection — confirm, pick from a numbered list, or quit (`q`)
- Logs 8h/day against the selected issue
- Skips weekends and days that already have time logged
- Supports current week, custom date ranges, and monthly shortcuts

## Setup

### 1. Get API tokens

- **Tempo API token** — Tempo > Settings > API Integration
- **Jira API token** — https://id.atlassian.com/manage-profile/security/api-tokens

### 2. Create `.env` file

```bash
cp .env.example .env
```

Edit `.env` with your credentials:

```bash
export TEMPO_API_TOKEN=your-tempo-token
export JIRA_BASE_URL=https://yourorg.atlassian.net
export JIRA_EMAIL=you@company.com
export JIRA_API_TOKEN=your-jira-token
```

### 3. Make executable

```bash
chmod +x log-time.sh
```

## Usage

```bash
# Load credentials first
source .env

# Log time for the current week (Mon–Fri)
./log-time.sh

# Log time for last month
./log-time.sh --last-month

# Log time for this month (1st through today)
./log-time.sh --this-month

# Log time for a custom date range
./log-time.sh 2026-06-01 2026-06-15

# Log time for a single date
./log-time.sh 2026-06-16
```

### Logging different tasks to different days

Run the script multiple times with different date ranges — each run lets you pick a different issue:

```bash
# Week of June 16: log Mon–Wed against one task, Thu–Fri against another
./log-time.sh 2026-06-16 2026-06-18   # select task A
./log-time.sh 2026-06-19 2026-06-20   # select task B

# Or target a single day
./log-time.sh 2026-06-20              # select task C
```

Days that already have the full hours logged are automatically skipped, so there's no risk of double-logging.

## Configuration

All options are set via environment variables (in `.env` or exported in your shell):

| Variable | Required | Default | Description |
|---|---|---|---|
| `TEMPO_API_TOKEN` | Yes | — | Tempo API token |
| `JIRA_BASE_URL` | Yes | — | Jira Cloud URL (e.g. `https://yourorg.atlassian.net`) |
| `JIRA_EMAIL` | Yes | — | Your Atlassian email |
| `JIRA_API_TOKEN` | Yes | — | Jira API token |
| `JIRA_ACCOUNT_ID` | No | Auto-resolved | Your Atlassian account ID |
| `JQL` | No | `assignee = currentUser()` | JQL query to find issues |
| `HOURS_PER_DAY` | No | `8` | Hours to log per day |

### Custom JQL examples

```bash
# Only a specific project
export JQL="assignee = currentUser() AND project = MYPROJ AND status = 'In Progress'"

# Current sprint
export JQL="assignee = currentUser() AND sprint in openSprints()"

# Specific issue
export JQL="key = PROJ-123"
```

## How it works

1. Queries Jira with your JQL to find issues updated within the date range
2. Prompts you to confirm (single result) or select from a numbered list (multiple results)
3. For each weekday in the date range:
   - Checks existing Tempo worklogs to avoid double-logging
   - Logs the remaining hours (up to `HOURS_PER_DAY`) if needed
4. Reports success/failure for each day

## Requirements

- `bash`, `curl`, `jq`
- macOS or Linux
