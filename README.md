# Enaks-auto

Version-controlled n8n workflows for Express Cleaning Consult. GitHub is the
source of truth: workflows are reviewed here, audited automatically, then
imported into a local n8n that only this PC can reach.

## Setup (Windows, one command)

Needs Node 24+ and git.

```powershell
git clone https://github.com/Rukkymarz/Enaks-auto- $HOME\Documents\Enaks-auto
powershell -ExecutionPolicy Bypass -File $HOME\Documents\Enaks-auto\setup\setup-n8n.ps1
powershell -ExecutionPolicy Bypass -File $HOME\Documents\Enaks-auto\setup\start-n8n.ps1
```

Open http://localhost:5678, create the owner account, then add credentials.

| Script | Does |
|---|---|
| `setup/setup-n8n.ps1` | Installs n8n **2.48.6** (pinned), pulls this repo, runs the audit, imports workflows **switched off** |
| `setup/start-n8n.ps1` | Starts n8n with the hardened settings in `setup/n8n-env.ps1` |
| `tools/n8n_audit.py` | Blocks shell/SSH/local-file nodes, hard-coded secrets, `active: true`, embedded credential IDs |

Re-run `setup-n8n.ps1` any time to pull and re-import; fixed workflow IDs mean
updates replace the old copy instead of duplicating it.

## Hardening (`setup/n8n-env.ps1`)

- Listens on `127.0.0.1` only (not your network); telemetry and version pings off
- Shell, SSH and local-file nodes disabled; workflows can't read environment variables

## Workflows

| Workflow | Needs | Sends messages? |
|---|---|---|
| Lead qualification (Google Sheets + AI) | Google Sheets, OpenAI-compatible key | No |
| Appointment request qualifier (n8n Form) | Gmail, Google Calendar, OpenAI | **Yes, automatically**: receipt + rejection emails to customers; approval email to you |
| Email replies with your approval (IMAP/SMTP) | IMAP + SMTP (works with Zoho Mail), OpenAI | Only after you approve each reply |
| Feedback summary (Google Sheets) | Google Sheets, Gmail, OpenAI | One summary email, manual trigger |
| Expense tracker (chat + Google Sheets) | Google Sheets, OpenAI | No |

All are imported **off**. Before switching one on: add its credentials, run it
once with "Test workflow", check the output, then activate. Turning on a
workflow that sends email is your decision; nothing here is switched on automatically.

Sources and licence: see `workflows/SOURCES.md` (templates are CC BY 4.0;
this repo's own code is MIT). n8n itself is under the Sustainable Use License:
free for internal business use, not for reselling n8n as a hosted service.

## Adding a workflow

Export it from n8n (Download), drop the JSON in `workflows/`, set `"active": false`,
commit. The **Audit n8n workflows** GitHub Action must pass before you import it.
