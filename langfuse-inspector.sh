#!/usr/bin/env bash
#
# langfuse-inspector - Langfuse CLI for fetching traces, observations, and sessions
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

# URL-encode a string (special chars like [], spaces)
url_encode() {
    python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
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
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
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
    
    # Parse and sort traces by timestamp, output only IDs
    echo "$response" | python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
traces = data.get('data', [])

# Sort by timestamp
traces_sorted = sorted(traces, key=lambda t: t.get('timestamp', ''))

for t in traces_sorted:
    print(t.get('id', ''))
" 2>/dev/null || echo "$response"
}

# List traces in session
list_traces() {
    if [[ -z "$SESSION_ID" ]]; then
        echo -e "${RED}Error: --session-id is required${NC}"
        exit 1
    fi
    
    local response
    response=$(api_get "/api/public/traces?sessionId=${SESSION_ID}&limit=${LIMIT}&page=${PAGE}")
    
    # Parse and format traces
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "$response"
        return
    fi
    
    # Get data array
    local traces
    traces=$(echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
traces = data.get('data', [])
print(json.dumps(traces))
" 2>/dev/null) || traces="[]"
    
    # Apply head/tail
    if [[ "$HEAD_COUNT" -gt 0 ]]; then
        traces=$(echo "$traces" | python3 -c "
import sys, json
traces = json.load(sys.stdin)
print(json.dumps(traces[:${HEAD_COUNT}]))
" 2>/dev/null) || traces="[]"
    elif [[ "$TAIL_COUNT" -gt 0 ]]; then
        traces=$(echo "$traces" | python3 -c "
import sys, json
traces = json.load(sys.stdin)
print(json.dumps(traces[-${TAIL_COUNT}:]))
" 2>/dev/null) || traces="[]"
    fi
    
    # Display traces
    echo "$traces" | python3 -c "
import sys, json
from datetime import datetime, timedelta, timezone

traces = json.load(sys.stdin)
print(f'=== Session traces ({len(traces)} traces) ===\n')

# Calculate offset for pagination
offset = (${PAGE} - 1) * ${LIMIT}

for i, t in enumerate(traces):
    tid = t.get('id', '')
    ts = t.get('timestamp', '')
    name = t.get('name', '')
    input_val = t.get('input', '')
    output_val = t.get('output', '')
    
    # Format timestamp (convert UTC to local UTC+8)
    try:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        local_dt = dt.astimezone(timezone(timedelta(hours=8)))
        ts = local_dt.strftime('%Y-%m-%d %H:%M:%S')
    except:
        pass
    
    # Format input/output for display
    if isinstance(input_val, str):
        input_val = input_val.replace('\n', ' ')
    elif input_val:
        input_val = str(input_val).replace('\n', ' ')
    else:
        input_val = ''
    
    if isinstance(output_val, str):
        output_val = output_val.replace('\n', ' ')
    elif output_val:
        output_val = str(output_val).replace('\n', ' ')
    else:
        output_val = ''
    
    print(f'Turn {offset+i+1}: {tid}')
    print(f'  Name: {name}')
    print(f'  Time: {ts}')
    if input_val:
        print(f'  Input: {input_val}')
    if output_val:
        print(f'  Output: {output_val}')
    print()
" 2>/dev/null || echo "$traces"
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
    
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
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
    
    # Extract and display unique observation names with timing
    echo "$response" | python3 -c "
import sys, json
from collections import OrderedDict
from datetime import datetime, timedelta, timezone

data = json.load(sys.stdin)
observations = data.get('data', [])

# Sort by startTime ascending (execution order)
observations.sort(key=lambda o: o.get('startTime', ''))

# Get unique names preserving execution order
names = list(OrderedDict.fromkeys(o.get('name', '') for o in observations if o.get('name')))

print('=== Observations for trace ===\n')
print(f'Total observations: {len(observations)}')
print(f'Unique names: {len(names)}\n')

for name in names:
    matched = [o for o in observations if o.get('name') == name]
    count = len(matched)
    obs_type = matched[0].get('type', '')
    
    # Calculate total latency across all instances (API returns ms)
    total_ms = sum(o.get('latency', 0) or 0 for o in matched)
    
    # Format latency (ms → human readable)
    if total_ms >= 60000:
        latency_str = f'{total_ms/60000:.1f}m'
    elif total_ms >= 1000:
        latency_str = f'{total_ms/1000:.1f}s'
    else:
        latency_str = f'{total_ms:.0f}ms'
    
    # Time range (convert UTC to local UTC+8)
    try:
        utc_dt = datetime.fromisoformat(matched[0].get('startTime', '').replace('Z', '+00:00'))
        local_dt = utc_dt.astimezone(timezone(timedelta(hours=8)))
        first_start = local_dt.strftime('%Y-%m-%d %H:%M:%S')
    except:
        first_start = matched[0].get('startTime', '')[:19].replace('T', ' ')
    
    if count == 1:
        print(f'  {name}')
        print(f'    Type: {obs_type} | Latency: {latency_str} | Start: {first_start}')
    else:
        print(f'  {name}')
        print(f'    Type: {obs_type} | Count: {count} | Total: {latency_str} | First: {first_start}')
" 2>/dev/null || echo "$response"
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
    
    echo "$response" | python3 -c "
import sys, json

data = json.load(sys.stdin)
obs_list = data.get('data', [])

if not obs_list:
    print(f'Observation \"${OBSERVATION}\" not found')
    sys.exit(1)

for idx, obs in enumerate(obs_list):
    if idx > 0:
        print('\n' + '='*60 + '\n')
    label = f'{obs.get(\"name\", \"Observation\")}' if len(obs_list) == 1 else f'{obs.get(\"name\", \"Observation\")} [{idx+1}/{len(obs_list)}]'
    print(f'=== {label} ===')
    print(f'ID: {obs.get(\"id\", \"\")}')
    print(f'Type: {obs.get(\"type\", \"\")}')
    print(f'Start: {obs.get(\"startTime\", \"\")}')
    print(f'End: {obs.get(\"endTime\", \"\")}')

    # Input
    inp = obs.get('input')
    if inp is not None:
        print('\n--- Input ---')
        if isinstance(inp, (dict, list)):
            print(json.dumps(inp, indent=2, ensure_ascii=False))
        else:
            print(str(inp))

    # Output
    out = obs.get('output')
    if out is not None:
        print('\n--- Output ---')
        if isinstance(out, (dict, list)):
            print(json.dumps(out, indent=2, ensure_ascii=False))
        else:
            print(str(out))

    # Metadata
    meta = obs.get('metadata')
    if meta:
        print('\n--- Metadata ---')
        if isinstance(meta, str):
            try:
                meta = json.loads(meta)
            except:
                pass
        if isinstance(meta, (dict, list)):
            print(json.dumps(meta, indent=2, ensure_ascii=False))
        else:
            print(meta)
" 2>/dev/null || echo "$response"
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
