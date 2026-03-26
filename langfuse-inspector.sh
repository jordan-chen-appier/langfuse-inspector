#!/usr/bin/env bash
#
# langfuse-inspector - Langfuse CLI for fetching traces, observations, and sessions
#
# Dependencies: curl, jq
#
# Usage:
#   source this file or call with parameters
#
# Environment Variables (can be exported or passed as args):
#   LANGFUSE_HOST        - Langfuse host URL (default: https://langfuse.appier.net)
#   LANGFUSE_PROJECT_ID  - Project ID
#   LANGFUSE_PUBLIC_KEY  - Public key (pk-lf-...)
#   LANGFUSE_SECRET_KEY  - Secret key (sk-lf-...)
#
# Examples:
#   ./langfuse-inspector.sh --session-id <id>              # List all traces in session
#   ./langfuse-inspector.sh --session-id <id> --head 5    # First 5 traces
#   ./langfuse-inspector.sh --session-id <id> --tail 3     # Last 3 traces
#   ./langfuse-inspector.sh --trace-id <id>                # Single trace details
#   ./langfuse-inspector.sh --trace-id <id> --observation state_snapshot_before_agent
#   ./langfuse-inspector.sh --session-id <id> --observations  # List observation names
#   ./langfuse-inspector.sh --session-id <id> --session-info             # Session metadata
#   ./langfuse-inspector.sh --session-id <id> --trace-ids         # List all trace IDs (sorted by time)

set -euo pipefail

# Auto-load .env from script directory if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    source "${SCRIPT_DIR}/.env"
fi

# Check dependencies
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' is required but not installed." >&2
        exit 1
    fi
done

# Default values
LANGFUSE_HOST="${LANGFUSE_HOST:-https://langfuse.appier.net}"
LANGFUSE_PROJECT_ID="${LANGFUSE_PROJECT_ID:-}"
LANGFUSE_PUBLIC_KEY="${LANGFUSE_PUBLIC_KEY:-}"
LANGFUSE_SECRET_KEY="${LANGFUSE_SECRET_KEY:-}"

# CLI options
SESSION_ID=""
TRACE_ID=""
HEAD_COUNT=0
TAIL_COUNT=0
LIMIT=50
PAGE=1
OBSERVATION=""
LIST_OBSERVATIONS=false
SESSION_INFO=false
OUTPUT_JSON=false
OUTPUT_TRACE_IDS=false

VERBOSE=false

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    cat <<'EOF'
langfuse-inspector.sh - Langfuse CLI

Usage:
  ./langfuse-inspector.sh --session-id <ID>
  ./langfuse-inspector.sh --trace-id <ID>

Examples:
  ./langfuse-inspector.sh --session-id <id>
  ./langfuse-inspector.sh --session-id <id> --head 5
  ./langfuse-inspector.sh --session-id <id> --tail 3
  ./langfuse-inspector.sh --session-id <id> --trace-ids
  ./langfuse-inspector.sh --trace-id <id> --observations
  ./langfuse-inspector.sh --trace-id <id> --observation state_snapshot_before_agent
EOF
    echo ""
    echo "Options:"
    echo "  -s, --session-id ID       Session ID (required for session-based queries)"
    echo "  -t, --trace-id ID        Single trace ID"
    echo "  -H, --head N             Show first N traces"
    echo "  -T, --tail N             Show last N traces"
    echo "  -l, --limit N            Limit results (default: 50)"
    echo "  -p, --page N             Page number (default: 1)"
    echo "  -o, --observation NAME   Filter by observation name"
    echo "      --observations       List all observation names for a trace"
    echo "      --session-info       Get session metadata"
    echo "      --trace-ids         Output only trace IDs (sorted by time)"
    echo "  -j, --json               Output raw JSON"
    echo "  -v, --verbose            Verbose output"
    echo "  -h, --help               Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  LANGFUSE_HOST           Host URL (default: https://langfuse.appier.net)"
    echo "  LANGFUSE_PROJECT_ID     Project ID"
    echo "  LANGFUSE_PUBLIC_KEY     Public key (pk-lf-...)"
    echo "  LANGFUSE_SECRET_KEY     Secret key (sk-lf-...)"
    echo ""
    echo "Or pass credentials via arguments:"
    echo "  --host URL               Override host"
    echo "  --project-id ID          Override project ID"
    echo "  --public-key KEY         Override public key"
    echo "  --secret-key KEY         Override secret key"
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--session-id)
                SESSION_ID="$2"
                shift 2
                ;;
            -t|--trace-id)
                TRACE_ID="$2"
                shift 2
                ;;
            -H|--head)
                HEAD_COUNT="$2"
                shift 2
                ;;
            -T|--tail)
                TAIL_COUNT="$2"
                shift 2
                ;;
            -l|--limit)
                LIMIT="$2"
                shift 2
                ;;
            -p|--page)
                PAGE="$2"
                shift 2
                ;;
            -o|--observation)
                OBSERVATION="$2"
                shift 2
                ;;
            --observations)
                LIST_OBSERVATIONS=true
                shift
                ;;
            --session-info)
                SESSION_INFO=true
                shift
                ;;
            --trace-ids)
                OUTPUT_TRACE_IDS=true
                shift
                ;;
            -j|--json)
                OUTPUT_JSON=true
                shift
                ;;

            -v|--verbose)
                VERBOSE=true
                shift
                ;;

            -h|--help)
                usage
                ;;
            --host)
                LANGFUSE_HOST="$2"
                shift 2
                ;;
            --project-id)
                LANGFUSE_PROJECT_ID="$2"
                shift 2
                ;;
            --public-key)
                LANGFUSE_PUBLIC_KEY="$2"
                shift 2
                ;;
            --secret-key)
                LANGFUSE_SECRET_KEY="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                ;;
        esac
    done
}

# Validate required credentials
validate_credentials() {
    if [[ -z "$LANGFUSE_PUBLIC_KEY" ]]; then
        echo -e "${RED}Error: LANGFUSE_PUBLIC_KEY is required${NC}"
        echo "Set it via environment variable or --public-key argument"
        exit 1
    fi
    if [[ -z "$LANGFUSE_SECRET_KEY" ]]; then
        echo -e "${RED}Error: LANGFUSE_SECRET_KEY is required${NC}"
        echo "Set it via environment variable or --secret-key argument"
        exit 1
    fi
}

# URL-encode a string (RFC 3986, pure shell, no python dependency)
url_encode() {
    local LC_ALL=C
    local string="$1" i byte
    local hex_string
    hex_string=$(printf '%s' "$string" | od -An -tx1 | tr -d ' \n')
    for (( i = 0; i < ${#hex_string}; i += 2 )); do
        byte="${hex_string:i:2}"
        case "$byte" in
            4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]) printf "\\x${byte}" ;;  # A-Z a-z
            3[0-9]) printf "\\x${byte}" ;;                                  # 0-9
            2d|2e|5f|7e) printf "\\x${byte}" ;;                             # - . _ ~
            *) printf '%%%s' "${byte^^}" ;;
        esac
    done
}

# Convert ISO 8601 UTC timestamp to UTC+8 display string
# Input: "2024-01-15T10:30:00.000Z" or "2024-01-15T10:30:00+00:00"
# Output: "2024-01-15 18:30:00"
utc_to_local() {
    local ts="$1"
    # Strip fractional seconds and normalize Z to +00:00
    ts="${ts%%.*}"
    ts="${ts%Z}"
    ts="${ts%+00:00}"
    if date --version &>/dev/null 2>&1; then
        # GNU date (Linux)
        date -d "${ts}Z +8 hours" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$1"
    else
        # BSD date (macOS)
        local epoch
        epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "$ts" '+%s' 2>/dev/null) || { echo "$1"; return; }
        epoch=$(( epoch + 28800 ))
        date -j -f '%s' "$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$1"
    fi
}

# Format milliseconds to human-readable latency
format_latency() {
    local ms="$1"
    if [[ "$ms" -ge 60000 ]]; then
        echo "$(echo "scale=1; $ms / 60000" | bc)m"
    elif [[ "$ms" -ge 1000 ]]; then
        echo "$(echo "scale=1; $ms / 1000" | bc)s"
    else
        echo "${ms}ms"
    fi
}

# Make API request
api_get() {
    local path="$1"
    local url="${LANGFUSE_HOST}${path}"

    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG] GET $url${NC}" >&2
    fi

    curl -s -u "${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}" "$url"
}

# Get session info
get_session_info() {
    if [[ -z "$SESSION_ID" ]]; then
        echo -e "${RED}Error: --session-id is required for --session-info${NC}"
        exit 1
    fi

    local response
    response=$(api_get "/api/public/sessions/${SESSION_ID}")

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "$response"
    else
        echo "$response" | jq . 2>/dev/null || echo "$response"
    fi
}

# Output trace IDs sorted by timestamp
list_trace_ids() {
    if [[ -z "$SESSION_ID" ]]; then
        echo -e "${RED}Error: --session-id is required${NC}"
        exit 1
    fi

    local response
    response=$(api_get "/api/public/traces?sessionId=${SESSION_ID}&limit=${LIMIT}&page=${PAGE}")

    echo "$response" | jq -r '.data | sort_by(.timestamp) | .[].id' 2>/dev/null || echo "$response"
}

# List traces in session
list_traces() {
    if [[ -z "$SESSION_ID" ]]; then
        echo -e "${RED}Error: --session-id is required${NC}"
        exit 1
    fi

    local response
    response=$(api_get "/api/public/traces?sessionId=${SESSION_ID}&limit=${LIMIT}&page=${PAGE}")

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "$response"
        return
    fi

    # Extract traces, apply head/tail
    local traces
    traces=$(echo "$response" | jq '.data // []') || traces="[]"

    if [[ "$HEAD_COUNT" -gt 0 ]]; then
        traces=$(echo "$traces" | jq ".[0:${HEAD_COUNT}]")
    elif [[ "$TAIL_COUNT" -gt 0 ]]; then
        traces=$(echo "$traces" | jq ".[-${TAIL_COUNT}:]")
    fi

    local count
    count=$(echo "$traces" | jq 'length')
    echo "=== Session traces (${count} traces) ==="
    echo ""

    local offset=$(( (PAGE - 1) * LIMIT ))
    local i=0

    while IFS= read -r trace; do
        local tid name ts input_val output_val
        tid=$(echo "$trace" | jq -r '.id // ""')
        name=$(echo "$trace" | jq -r '.name // ""')
        ts=$(echo "$trace" | jq -r '.timestamp // ""')
        input_val=$(echo "$trace" | jq -r 'if .input == null then "" elif (.input | type) == "string" then .input | gsub("\n"; " ") else (.input | tostring) | gsub("\n"; " ") end')
        output_val=$(echo "$trace" | jq -r 'if .output == null then "" elif (.output | type) == "string" then .output | gsub("\n"; " ") else (.output | tostring) | gsub("\n"; " ") end')

        if [[ -n "$ts" ]]; then
            ts=$(utc_to_local "$ts")
        fi

        echo "Turn $(( offset + i + 1 )): ${tid}"
        echo "  Name: ${name}"
        echo "  Time: ${ts}"
        [[ -n "$input_val" ]] && echo "  Input: ${input_val}"
        [[ -n "$output_val" ]] && echo "  Output: ${output_val}"
        echo ""

        i=$(( i + 1 ))
    done < <(echo "$traces" | jq -c '.[]')
}

# Get single trace details
get_trace() {
    if [[ -z "$TRACE_ID" ]]; then
        echo -e "${RED}Error: --trace-id is required${NC}"
        exit 1
    fi

    local response
    response=$(api_get "/api/public/traces/${TRACE_ID}")

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "$response"
        return
    fi

    echo "$response" | jq . 2>/dev/null || echo "$response"
}

# List observations for a trace
list_observations() {
    if [[ -z "$TRACE_ID" ]]; then
        echo -e "${RED}Error: --trace-id is required${NC}"
        exit 1
    fi

    local response
    response=$(api_get "/api/public/observations?traceId=${TRACE_ID}&limit=100")

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "$response"
        return
    fi

    # Use jq to sort, group, and format observations
    echo "$response" | jq -r '
        .data // [] | sort_by(.startTime) as $sorted |
        ($sorted | length) as $total |
        ($sorted | [.[].name // empty] | unique | length) as $unique_count |

        "=== Observations for trace ===\n",
        "Total observations: \($total)",
        "Unique names: \($unique_count)\n",

        # Group by name preserving execution order
        (reduce $sorted[] as $o (
            {seen: {}, names: []};
            if .seen[$o.name] then . else .seen[$o.name] = true | .names += [$o.name] end
        ) | .names[]) as $name |

        ($sorted | [.[] | select(.name == $name)]) as $matched |
        ($matched | length) as $count |
        ($matched[0].type // "") as $obs_type |
        ($matched | map(.latency // 0) | add) as $total_ms |
        ($matched[0].startTime // "") as $start_time |

        # Format latency
        (if $total_ms >= 60000 then "\($total_ms / 60000 * 10 | round / 10)m"
         elif $total_ms >= 1000 then "\($total_ms / 1000 * 10 | round / 10)s"
         else "\($total_ms)ms"
         end) as $latency_str |

        # Format start time (strip fractional seconds for display)
        ($start_time | split(".")[0] | gsub("T"; " ") | gsub("Z"; "")) as $time_display |

        "  \($name)",
        if $count == 1 then
            "    Type: \($obs_type) | Latency: \($latency_str) | Start: \($time_display)"
        else
            "    Type: \($obs_type) | Count: \($count) | Total: \($latency_str) | First: \($time_display)"
        end
    ' 2>/dev/null || echo "$response"
}

# Get specific observation
get_observation() {
    if [[ -z "$TRACE_ID" ]]; then
        echo -e "${RED}Error: --trace-id is required${NC}"
        exit 1
    fi
    if [[ -z "$OBSERVATION" ]]; then
        echo -e "${RED}Error: --observation NAME is required${NC}"
        exit 1
    fi

    local response
    local encoded_name=$(url_encode "$OBSERVATION")
    response=$(api_get "/api/public/observations?traceId=${TRACE_ID}&name=${encoded_name}&limit=100")

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "$response"
        return
    fi

    local obs_count
    obs_count=$(echo "$response" | jq '.data | length' 2>/dev/null) || obs_count=0

    if [[ "$obs_count" -eq 0 ]]; then
        echo "Observation \"${OBSERVATION}\" not found"
        return 1
    fi

    local i=0
    while IFS= read -r obs; do
        if [[ "$i" -gt 0 ]]; then
            echo ""
            printf '=%.0s' {1..60}
            echo ""
            echo ""
        fi

        local name obs_id obs_type start_time end_time
        name=$(echo "$obs" | jq -r '.name // "Observation"')
        obs_id=$(echo "$obs" | jq -r '.id // ""')
        obs_type=$(echo "$obs" | jq -r '.type // ""')
        start_time=$(echo "$obs" | jq -r '.startTime // ""')
        end_time=$(echo "$obs" | jq -r '.endTime // ""')

        if [[ "$obs_count" -eq 1 ]]; then
            echo "=== ${name} ==="
        else
            echo "=== ${name} [$(( i + 1 ))/${obs_count}] ==="
        fi
        echo "ID: ${obs_id}"
        echo "Type: ${obs_type}"
        echo "Start: ${start_time}"
        echo "End: ${end_time}"

        # Input
        local has_input
        has_input=$(echo "$obs" | jq '.input != null')
        if [[ "$has_input" == "true" ]]; then
            echo ""
            echo "--- Input ---"
            echo "$obs" | jq -r 'if (.input | type) == "string" then .input else (.input | tojson) end' | jq . 2>/dev/null || echo "$obs" | jq -r '.input | tostring'
        fi

        # Output
        local has_output
        has_output=$(echo "$obs" | jq '.output != null')
        if [[ "$has_output" == "true" ]]; then
            echo ""
            echo "--- Output ---"
            echo "$obs" | jq -r 'if (.output | type) == "string" then .output else (.output | tojson) end' | jq . 2>/dev/null || echo "$obs" | jq -r '.output | tostring'
        fi

        # Metadata
        local has_meta
        has_meta=$(echo "$obs" | jq '.metadata != null and .metadata != {} and .metadata != ""')
        if [[ "$has_meta" == "true" ]]; then
            echo ""
            echo "--- Metadata ---"
            echo "$obs" | jq '.metadata' 2>/dev/null
        fi

        i=$(( i + 1 ))
    done < <(echo "$response" | jq -c '.data[]')
}

# Main execution
main() {
    parse_args "$@"
    validate_credentials

    # Route to appropriate function
    if [[ "$SESSION_INFO" == "true" ]]; then
        get_session_info
    elif [[ -n "$TRACE_ID" ]]; then
        if [[ "$LIST_OBSERVATIONS" == "true" ]]; then
            list_observations
        elif [[ -n "$OBSERVATION" ]]; then
            get_observation
        else
            get_trace
        fi
    elif [[ -n "$SESSION_ID" ]]; then
        if [[ "$OUTPUT_TRACE_IDS" == "true" ]]; then
            list_trace_ids
        else
            list_traces
        fi

    else
        echo -e "${RED}Error: Must specify --session-id or --trace-id${NC}"
        usage
    fi
}

# Run main
main "$@"
