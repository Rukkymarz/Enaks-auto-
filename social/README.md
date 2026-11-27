# Express Cleaning Consult: social media system (SOC-01 to SOC-12)

Modular n8n workflows + a Supabase database (`soc_*` tables, project `cnlvbusjqwepotvlqcgx`).
Regenerate the workflow JSON with `python3 social/build_workflows.py`; schema in `social/schema.sql`.

| # | Workflow | Trigger | Status |
|---|---|---|---|
| 01 | Content strategy and ideas | Mondays 06:30 ET | ready to test |
| 02 | Daily content calendar | Daily 07:00 ET | ready to test |
| 03 | Single post generator | Called by 02 / 06 | ready to test |
| 04 | Carousel generator | Called by 02 / 06 | ready to test |
| 05 | Video script generator | Called by 02 / 06 | ready to test |
| 06 | Approval (email Approve / Revise / Reject) | Form + called | needs SMTP credential |
| 07 | Publishing via Postiz | Every 15 min | blocked: Postiz not hosted yet |
| 08 | Analytics collector (Postiz) | Daily 05:00 ET | blocked: Postiz |
| 09 | Comment monitor (Facebook via Meta Graph) | Hourly | needs Meta Page token |
| 10 | Weekly performance report | Mondays 06:00 ET | ready to test |
| 11 | Repurposing | Form | ready to test |
| 12 | Error monitor | Error workflow for 01-11 | needs SMTP credential |

Credentials to create in n8n (names must match): `Social DB (Supabase)` (Supabase API: project URL + service_role key),
`FreeLLMAPI key` (exists), `Social email (SMTP)` (Gmail app password), `Postiz API key` (Header Auth: Authorization),
`Meta Page token` (Facebook Graph API). Nothing is hard-coded; every workflow imports switched OFF.

Database safety tested 2026-11-27: duplicate topics blocked (incl. reworded), daily cap and non-promotional-first pick,
one post per slot with a minimum gap, a publish lock that claims a post once, 3 retries then failed + error log.
