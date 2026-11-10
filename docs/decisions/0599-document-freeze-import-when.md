# 0599: Check import mode in the document freeze trigger's when clause

- Status: accepted
- Date: 2026-11-10
- Amends: 0422

## Context

`bsb_document_freeze` is a deferred constraint trigger. Its function returned early when
`importing()` was true, but the function runs at commit and `import_upsert_batch` restores the
import flag before that. CentraKit measured 47,668 freezes, about 219 s, in one import.

## Decision

The trigger's `when` clause adds `not (better_supabase.import_run() is not null)`. Postgres
evaluates it when the row changes, inside the import, so the event is never queued. The check
stays in the function for triggers installed before this change. The other five deferrable
constraint triggers in the modules have no import guard, so nothing else moves.

## Alternatives considered

- Hold the import flag until commit: it would change what every other function sees after the
  batch returns.
- Make the trigger immediate for import targets: it loses the commit-time totals the freeze needs.

## Consequences

A pgTAP file (`document_freeze_import`) checks the clause. A normal issue still freezes at commit.
