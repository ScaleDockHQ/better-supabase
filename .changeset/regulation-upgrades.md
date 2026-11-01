---
"better-supabase": minor
---

Five blocks gain regulatory workflows (ADR 0182). `moderation` records DSA statements of reasons,
notices from trusted flaggers and appeals, and exports a transparency report as CSV. `incidents`
keeps a regulatory profile per incident and one filing per NIS2, DORA or CRA deadline, with a
`reminders` rule for each when that block is installed. `consents` records Sec-GPC as an opt-out,
stores parsed IAB TCF v2.2 and GPP strings as evidence, and issues consent receipts.
`data-lifecycle` tracks GDPR data subject requests with identity verification, a 30 day due date
and one extension. `compliance` imports OSCAL catalogs and profiles and exports assessment
results. Each module gets an upgrade step, so run `better-supabase db diff` to pick up the new
tables and functions.
