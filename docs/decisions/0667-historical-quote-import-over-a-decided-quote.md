# 0667: A historical quote import can replace a decided quote

- Status: accepted
- Date: 2026-11-10

## Context

`import_quote` (ADR 0141) writes a historical quote with its status, dates, answer, stored tax lines
and totals. An imported quote is kept as imported, and the item reports `IMPORT_DOCUMENT_CHANGED` when
its source changes. With `update: "apply"` in the item's data the import updates the quote instead, but
that path failed for the case a migration meets most: a correction that changes the number of lines of
a quote that was already sent or decided. The line replacement runs the quote's own edit guard, which
refuses any quote that isn't open, and the stored tax lines and totals were not applied again after the
lines changed.

## Decision

When `update` is `apply` and the line count differs, the import reopens the quote to its draft status,
replaces the lines through `set_quote_lines`, then writes the status, dates, answer and the rest of
the item's fields, so the quote ends in the status it had. The stored `taxLines` and `totals` are
applied after the lines in both branches, with the same `IMPORT_TAX_MISMATCH` and
`IMPORT_TOTALS_MISMATCH` warnings as a first import.

The status writes happen in import mode, so a state machine on the quote status skips its transition
check (ADR 0141). A table of the app's own that guards the status with a trigger has to skip it with
`better_supabase.importing()`.

## Consequences

An applied update touches the quote's `updated_at`, as before. No event fires and no version is
published. A second run that sends the same quote without `apply` still keeps it as imported. A pgTAP
file covers the apply path over an accepted quote.
