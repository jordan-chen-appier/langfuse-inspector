---
name: langfuse-session-dump
description: |
  Operational guide for `./langfuse-inspector.sh`.
  Use this skill when user needs to dump Langfuse session traces, control output scope,
  troubleshoot API fetch failures, or prepare structured input for E2E validation.
---

# Langfuse Inspector Guide

## Purpose

Use `langfuse-inspector.sh` to fetch a Langfuse session and print:
1. Ordered trace list (`T1...Tn`)
2. Input summary per trace
3. `state_snapshot_before_agent` / `state_snapshot_after_agent`
4. Observation timeline (`startTime [type] name`)

Script path:

```bash
./langfuse-inspector.sh
```

## Baseline Command

```bash
./langfuse-inspector.sh \
  --session-id "<SESSION_ID>"
```

## Useful Options

- `--session-id <id>`: target session
- `--head N`: First N traces
- `--tail N`: Last N traces
- `--trace-ids`: Trace IDs only (sorted by time)
- `--trace-id <ID>`: Single trace details
- `--observations`: List observation names for trace
- `--observation <NAME>`: Get specific observation (e.g. state_snapshot_before_agent)
- `--session-info`: Session metadata
- `--json`: Raw JSON output

## Recommended Invocation Patterns

### 1) List all traces in session

```bash
./langfuse-inspector.sh \
  --session-id "<SESSION_ID>"
```

### 2) Get trace IDs (sorted by time)

```bash
./langfuse-inspector.sh \
  --session-id "<SESSION_ID>" \
  --trace-ids
```

### 3) Get state snapshot for a trace

```bash
./langfuse-inspector.sh \
  --trace-id "<TRACE_ID>" \
  --observation state_snapshot_before_agent
```

### 4) List all observations in a trace

```bash
./langfuse-inspector.sh \
  --trace-id "<TRACE_ID>" \
  --observations
```

## Output Interpretation Checklist

For each trace, verify:
1. User input summary exists
2. before/after snapshots both present (or explicitly `NOT FOUND`)
3. Workflow/planning/scenario/plan fields are printed
4. Observation timeline is present and time-ordered

## Troubleshooting

### `401 Unauthorized`
- Check API keys are properly configured in environment

### `cannot reach host` / timeout
- Verify network and VPN
- Check Langfuse host is accessible

### Missing observations
- Some traces may fail before snapshot hooks
- Keep trace in report and mark as incomplete, do not drop silently

## Optional Handoff Contract (for any downstream consumer)

When handing output to another workflow/agent, always provide:
1. Session ID
2. Command used
3. Whether output was full or partial
4. Any missing snapshot traces
