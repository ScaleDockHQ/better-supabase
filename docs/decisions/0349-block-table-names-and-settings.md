# 0349: Three block tables take their convention names, and settings live in better_supabase

- Status: accepted
- Date: 2026-11-08
- Amends: 0206, 0246, 0247

## Context

ADR 0246 names a block table after its entity and a block setting after the
`better_supabase` schema. Three tables and six `set_config` keys were left:
`stream_kv`, `invoice_e_endpoints` (ADR 0206 kept its prefix when it renamed
`e_invoice_deliveries`), `workflow_step_library`, and the `bsb.recorded`,
`bsb.lane_move`, `bsb.parity`, `bsb.updated`, `bsb.audit` and `bsb.run`
settings.

## Decision

- `stream_kv` becomes `stream_entries`, `invoice_e_endpoints` becomes
  `e_invoice_endpoints` (with the `e_invoice_endpoints(invoice)` function that
  listed them) and `workflow_step_library` becomes `workflow_step_templates`.
  `company_people` already has its name. Each rename is a `table` row of
  `api/naming.json`; `codemod naming` renames the table when the project's SQL
  names it, then the constraints, indexes and policies that start with its old
  name (or `bsb_` and it). The fixture migration
  `20261108010000_bsb_table_names.sql` does the same and renames the function.
  The `stream_kv_*` functions keep their names: they implement Redis key commands.
- The settings a generated trigger or a pgTAP file sets with `set_config` are
  `better_supabase.recorded`, `better_supabase.lane_move`,
  `better_supabase.parity`, `better_supabase.updated`, `better_supabase.audit`
  and `better_supabase.run`. They live for one transaction, so no migration is
  needed. The `bsb.<key>` attributes the Workflow SDK adapter reads from a
  run (`bsb.tenant`, `bsb.actor`) are an adapter contract, not settings, and
  stay.

## Not done

`TABLE_RENAMES`, `spec.formerly` and `functionNouns` stay. They are not only
the 0.47 upgrade: a block whose module key equals an entity's plural (`tasks`)
keeps its permission keys, event types and paths when the install renames the
entity (`task` to `ticket`), because the rename starts from the old noun
(`work_item`). Dropping them renames `tasks.read` to `tickets.read` for every
renamed install and fails 12 tests. The naming engine has to separate the
module key from the entity plural first.

## Consequences

An app that reads one of the three tables over `$client` or `queryRaw` changes
the name; an app that calls `invoice_e_endpoints` over RPC calls
`e_invoice_endpoints`.
