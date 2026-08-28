#!/usr/bin/env bash

# Claude Code status line — mirrors Starship/Gruvbox Dark prompt style
# Receives JSON on stdin from Claude Code
#
# Keep this cheap: Claude runs it on startup and every UI refresh, including
# inside hab/terrarium guests where the workspace is a virtiofs/Docker mount.
# Never walk the working tree (git status/diff) or scan transcripts — those
# take seconds-to-minutes on monorepos and block the TUI from appearing.

input=$(cat)

# --- One jq pass ---
eval "$(printf '%s' "$input" | jq -r '
  @sh "cwd=\(.workspace.current_dir // .cwd // "")",
  @sh "model=\(.model.display_name // "")",
  @sh "used_pct=\(.context_window.used_percentage // "")",
  @sh "duration_ms=\(.cost.total_duration_ms // "")",
  @sh "cost_usd=\(.cost.total_cost_usd // "")"
')"

git_branch=""
repo_name=""

# --- Repo name + branch (.git metadata only; no working-tree walk) ---
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    toplevel=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
    repo_name=$(basename "${toplevel:-$cwd}")
    # Prefer TERRARIUM_WS_NAME when the project is bind-mounted at /workspace
    # (basename would otherwise be the literal mount name).
    ws="${TERRARIUM_WS:-/workspace}"
    case "$cwd" in
        "$ws"|"$ws"/*)
            if [ -n "${TERRARIUM_WS_NAME:-}" ]; then
                repo_name="$TERRARIUM_WS_NAME"
                if [ "$cwd" != "$ws" ]; then
                    repo_name="$repo_name/${cwd#"$ws"/}"
                fi
            fi
            ;;
    esac
    git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
elif [ -n "$cwd" ]; then
    repo_name=$(basename "$cwd")
fi

# --- Formatting helpers ---
format_duration() {
    local total_s=$(( $1 / 1000 ))
    local h=$(( total_s / 3600 ))
    local m=$(( (total_s % 3600) / 60 ))
    local s=$(( total_s % 60 ))
    if [ "$h" -gt 0 ]; then
        printf '%dh%02dm' "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf '%dm%02ds' "$m" "$s"
    else
        printf '%ds' "$s"
    fi
}

# --- Gruvbox Dark ANSI colors ---
YELLOW='\033[38;2;250;189;47m'      # #fabd2f  bright yellow  — repo name
GREEN='\033[38;2;142;192;124m'      # #8ec07c  bright aqua    — branch
FG1='\033[38;2;235;219;178m'        # #ebdbb2  fg1            — model name
FG2='\033[38;2;213;196;161m'        # #d5c4a1  fg2            — session duration
BLUE='\033[38;2;131;165;152m'       # #83a598  bright blue    — session cost
GRAY='\033[38;2;146;131;116m'       # #928374  gray           — separators
ORANGE='\033[38;2;254;128;25m'      # #fe8019  bright orange  — ctx% emphasis
BOLD='\033[1m'
RESET='\033[0m'

# --- Assemble line ---
# Format: <repo> (<branch>)  [<model>]  ctx:<used>%  <duration>  <cost>
parts=""

if [ -n "$repo_name" ]; then
    parts="${parts}${BOLD}${YELLOW}${repo_name}${RESET}"
fi
if [ -n "$git_branch" ]; then
    parts="${parts} ${GRAY}(${GREEN}${git_branch}${RESET}${GRAY})${RESET}"
fi

if [ -n "$model" ]; then
    parts="${parts} ${GRAY}[${RESET}${FG1}${model}${RESET}${GRAY}]${RESET}"
fi

if [ -n "$used_pct" ]; then
    used_int=$(printf '%.0f' "$used_pct")
    parts="${parts} ${ORANGE}ctx:${used_int}%${RESET}"
fi

if [ -n "$duration_ms" ]; then
    parts="${parts} ${FG2}$(format_duration "$duration_ms")${RESET}"
fi

if [ -n "$cost_usd" ]; then
    parts="${parts} ${BLUE}\$$(printf '%.2f' "$cost_usd")${RESET}"
fi

printf "%b\n" "$parts"
