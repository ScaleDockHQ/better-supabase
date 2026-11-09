# 0432: Re-issue a taken number when the item asks

- Status: accepted
- Date: 2026-11-09
- Amends: 0141

## Context

A quote or invoice imported with a number that another document already holds
failed with a unique violation, and the whole item was an error. A migration from
a source with overlapping number ranges had to rewrite the numbers before it
could import.

## Decision

`item.data.onTaken` is `fail` (the default) or `next_free`. With `next_free`,
`import_quote` and `import_invoice_document` check the tenant's identifiers; a
taken number is dropped, the numbering module issues the next free one, and the
item carries an `IMPORT_NUMBER_REASSIGNED` warning with the old number. Any other
value is `IMPORT_ITEM_INVALID`. Orders and the other numbered entities keep
failing; they take the option when a source needs it.

Two edges the brief asked to verify hold without a change and now have tests
(`import_run_edges`): a cancelled dry run leaves no customer and no record map
entry, and a run started right after another of the same source gets its own id
and counts (two runs of one source at once are refused by design).

## Consequences

`better-supabase upgrade` rewrites the quotes and invoices modules and the next
schema migration replaces two functions. No data migration. pgTAP
`import_number_taken` covers a clash with and without the option, an unknown
value, and an invoice.
