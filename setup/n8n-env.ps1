# n8n-env.ps1 — hardened settings, dot-sourced by setup-n8n.ps1 and start-n8n.ps1
$env:N8N_LISTEN_ADDRESS = "127.0.0.1"             # this PC only; not reachable from your network
$env:N8N_HOST = "localhost"
$env:N8N_PORT = "5678"
$env:N8N_PROTOCOL = "http"
$env:N8N_DIAGNOSTICS_ENABLED = "false"            # no telemetry to n8n
$env:N8N_VERSION_NOTIFICATIONS_ENABLED = "false"
$env:N8N_PERSONALIZATION_ENABLED = "false"
$env:N8N_BLOCK_ENV_ACCESS_IN_NODE = "true"        # workflows can't read your env vars
# Disable nodes that touch your PC or run commands (same list the audit blocks)
$env:NODES_EXCLUDE = '["n8n-nodes-base.executeCommand","n8n-nodes-base.ssh","n8n-nodes-base.readWriteFile","n8n-nodes-base.localFileTrigger"]'
$env:GENERIC_TIMEZONE = "America/New_York"
$env:TZ = "America/New_York"
