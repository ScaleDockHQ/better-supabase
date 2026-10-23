---
"better-supabase": minor
---

Blocks stop copying tables other blocks own. Leases drops its maintenance
requests (install a `tasks` instance named `maintenance_request` instead; the
upgrade renames the old table to `maintenance_requests_legacy`), admission
pass credits post on the ledger, inventory can keep stock at the assets
locations with `tables: { locations: null }`, and donations requires
`numbering` and contributes a `donation_receipt` sequence (`R-{n}`) that an
app entry replaces. Blocks contribute numbering defaults through
`contributes.numbering`. A renamed instance now reaches notifications and
the queue under their own names, and `gen` names its events type after the
instance (`MaintenanceEvents`) and adds it to `BlockEvents`.
