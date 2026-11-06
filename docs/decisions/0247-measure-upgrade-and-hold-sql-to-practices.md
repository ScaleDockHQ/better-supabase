# 0247: Measure upgrade before splitting it, and hold SQL to the naming and Supabase practices

- Status: accepted
- Date: 2026-11-06
- Amends: 0246

## Context

ADR 0246 left the SQL renames, the hint codes and the pipeline work open. The
declarative base layer plan splits `upgrade` into pure stages with a render
cache, and it asks the generated and app SQL to follow the Supabase and
Postgres practices. A change like that needs a number to beat, and a rule that
only a review enforces comes back.

## Decision

- `tests/types/perf/bench.ts` times `upgrade` on a copy of the CentraKit
  fixture in three cases (cold with no module files, a warm no-op, one app-file
  edit) and records seconds, modules rendered and files written in
  `baseline.json`. The seconds are scaled to the calibration of the baseline
  machine. The counts may only go down, so a render cache shows up as fewer
  rendered modules. Lienlink is not in the repository, so only CentraKit is
  measured.
- The first baseline: cold renders and writes 74 files, a warm run renders 75
  and writes 1, an edit renders 75 and writes 0. The one write on a warm run is
  the audit tables pgTAP file, which the cold run cannot write because it reads
  the audited tables from schema files the same run creates. The declared-object
  index of the pipeline split removes that second pass.
- `naming.json` gains the `hint`, `event` and `sqlFunction` kinds. `codemod
  naming` rewrites quoted hint codes and event names, and writes
  `alter function ... set schema` for the `bsb.*` helper functions only when the
  project's SQL names them. Done: `CHAIN_SIGNER`, `APPEND_ONLY` and
  `FISCAL_YEAR_CLOSED` are `AUDIT_CHAIN_SIGNER`, `TABLE_APPEND_ONLY` and
  `PERIOD_CLOSED`, the policy helpers moved from `bsb` to `better_supabase`, and
  the 15 allowlisted type names are renamed.
- The 0.47 table move upgrade steps (`tableMoves`) are removed, since upgrades
  start at 0.53. `TABLE_RENAMES` stays: `tableBase` still decides the table
  names of an install that renames an entity.
- `tests/sql/practices.test.ts` counts, per module golden, definer functions
  without `search_path`, `user_metadata` in a policy, views without
  `security_invoker`, `timestamp` and `serial` columns, update policies without a
  select policy, security definer functions and row triggers. Each count may
  only fall (`practices-baseline.json`). Doctor BS365 to BS368 apply the first
  four to the app's own schema files. `supabase/tests/database/naming_catalog.test.sql`
  reads the naming rules from the catalog: the `bsb` schema must be empty, and
  the counts of policies, triggers, checks, indexes, timestamps, tenant columns,
  user references and public definer functions may only fall.

## Alternatives considered

Renaming every SQL object in one step needs a hand migration and a golden
update per block and moves every installed table. A lint rule without a
baseline fails on the existing 478 policies and cannot be merged. Measuring
after the pipeline split would leave nothing to compare against.

## Consequences

Each later rename lowers a number in the pgTAP test or the practices baseline.
Still open, with their owners: the policy, trigger and function prefixes
(`bsb_*`), `tenant_id` in the 63 block tables that use `organization_id`, the
`_at` timestamps, `archived_at`, the `<role>_id` user columns, the table
renames (`e_invoice_endpoints`, `company_people`, `stream_entries`), the event
verbs, the `task` and `activity` nouns in the SQL and the clients (which
unblocks removing `TABLE_RENAMES`, `spec.formerly` and `clientNoun`), the
`bsb.*` GUCs and workflow attributes, and the format domain schema `bsb` that
the app owns after `migrate schema-first`. The pipeline split, the schema
model, the prelude, static DDL, the adopted-tables rules and the render cache
are not started.
