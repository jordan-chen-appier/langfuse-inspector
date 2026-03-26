# langfuse-inspector

Langfuse CLI for fetching traces, observations, and sessions.

## Installation

```bash
cd /Users/jordanchen/Workspace/Appier/langfuse-inspector
chmod +x langfuse-inspector.sh
```

## Configuration

`langfuse-inspector.sh` automatically loads credentials from `.env` in the same directory.

```bash
# /Users/jordanchen/Workspace/Appier/langfuse-inspector/.env
LANGFUSE_HOST="https://langfuse.appier.net"
LANGFUSE_PUBLIC_KEY="pk-lf-..."
LANGFUSE_SECRET_KEY="sk-lf-..."
```

## Usage

```bash
./langfuse-inspector.sh --help
```

### List traces in a session

```bash
./langfuse-inspector.sh --session-id <SESSION_ID>
```

### First/Last N traces

```bash
./langfuse-inspector.sh --session-id <ID> --head 5
./langfuse-inspector.sh --session-id <ID> --tail 3
```

### Trace IDs (sorted by time)

```bash
./langfuse-inspector.sh --session-id <ID> --trace-ids
```

### Single trace details

```bash
./langfuse-inspector.sh --trace-id <TRACE_ID>
```

### Observations

```bash
# List all observation names
./langfuse-inspector.sh --trace-id <ID> --observations

# Get specific observation
./langfuse-inspector.sh --trace-id <ID> --observation state_snapshot_before_agent
```

### Session info

```bash
./langfuse-inspector.sh --session-id <ID> --session-info
```

### Pagination

```bash
./langfuse-inspector.sh --session-id <ID> --page 2 --limit 20
```

### JSON output

```bash
./langfuse-inspector.sh --session-id <ID> --json
```

## Options

| Option | Description |
|--------|-------------|
| `-s, --session-id ID` | Session ID |
| `-t, --trace-id ID` | Single trace ID |
| `-H, --head N` | First N traces |
| `-T, --tail N` | Last N traces |
| `-l, --limit N` | Results per page (default: 50) |
| `-p, --page N` | Page number |
| `-o, --observation NAME` | Filter by observation name |
| `--observations` | List observation names for trace |
| `--session-info` | Get session metadata |
| `--trace-ids` | Output trace IDs only (sorted by time) |
| `-j, --json` | Raw JSON output |
| `-v, --verbose` | Debug output |
| `-h, --help` | Show help |
