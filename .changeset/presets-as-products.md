---
"better-supabase": minor
---

The `crm` preset now installs mail-sync, sequences, segments, assignment,
enrichment, forecasts and lead-scoring next to deals, so leads (contacts in
the `lead` lifecycle) are synced, scored, assigned and enrolled in email
sequences. The new `cms` preset installs content with publish approvals,
versions and public media; `erp` installs a catalog, stock, quotes priced
from the catalog, orders that invoice when paid, and employees with time and
leave; `pim` installs a catalog with channels, translations and public
product media, plus custom fields, imports and bulk edits. Write the old
`crm` block list as a preset object to keep the 0.14 selection.
