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
| **Lead intake + AI scoring (n8n tables)** | OpenAI-compatible key only (FreeLLMAPI); n8n Data Table `ECC Leads` | No |

All are imported **off**. Before switching one on: add its credentials, run it
once with "Test workflow", check the output, then activate. Turning on a
workflow that sends email is your decision; nothing here is switched on automatically.

Sources and licence: see `workflows/SOURCES.md` (templates are CC BY 4.0;
this repo's own code is MIT). n8n itself is under the Sustainable Use License:
free for internal business use, not for reselling n8n as a hosted service.

## Outreach pipeline (Apollo → AI drafts → you approve → Resend from support@)

| Workflow | Does | Sends email? |
|---|---|---|
| `outreach-1-lead-finder-apollo` | Weekdays 8am: Apollo search (free) for property managers, facility/office managers, realtors, contractors, short-term-rental managers **and partner cleaning businesses** (recruiting email, not a quote pitch) → skip already-contacted → Apollo email lookup (credits, max 20/day) → verified only → AI-written draft → `ECC Outreach` table as `pending_approval` | **No** |
| `outreach-2-send-approved` | Only when you submit its form with `SEND`: sends up to 20/day of `pending_approval` drafts via **Resend SMTP as support@expresscleaningconsult.com** with mailing address + opt-out line, marks `sent`/`failed`, then **logs the contact in HubSpot** (Lead, Attempted to contact) | **Yes, only on your confirmation** |

To stop someone ever being emailed, set their row status to `rejected` or `unsubscribed`.

## Adding a workflow

Export it from n8n (Download), drop the JSON in `workflows/`, set `"active": false`,
commit. The **Audit n8n workflows** GitHub Action must pass before you import it.

## HubSpot lead engine

Every lead ends up in HubSpot. Credentials (create once in n8n): `HubSpot private app (ECC)` (HubSpot → Settings → Integrations → Private Apps, scopes `crm.objects.contacts.read/write`, `crm.objects.deals.read/write`), `Gmail IMAP (expressconsulting92)` (Gmail app password), `Resend SMTP (support@)` (host smtp.resend.com, port 465, SSL, user `resend`, password = Resend sending key), `SAM.gov API key` (Query Auth, name `api_key`).

| Workflow | Does | Sends email? |
|---|---|---|
| `hubspot-1-website-quotes` | Each website **New quote request** notification → HubSpot contact (Sales qualified lead) + deal at *Appointment scheduled* | No |
| `hubspot-2-reply-triage` | Each reply to support@ → FreeLLMAPI classifies it → unsubscribe = table `unsubscribed` + HubSpot *Unqualified*; interested = HubSpot *In progress* + deal at *Qualified to buy*; partner yes = HubSpot *In progress* (partner note) | No |
| `hubspot-3-samgov-bids` | Weekdays 7am: new federal janitorial/building-service contracts (NAICS 561720, 561790) nationwide → HubSpot deals named `BID: …` + one digest email to you | Only to you |

Flow: **find** (Apollo, SAM.gov, website) → **approve** (your SEND form) → **send** (Resend, 20/day) → **track** (HubSpot) → **reply triage** (AI) → **you close** (quote, book).
