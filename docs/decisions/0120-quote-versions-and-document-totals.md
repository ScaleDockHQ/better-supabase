# 0120: Publish quote versions and count document totals per tax rate

- Status: accepted
- Date: 2026-10-28

## Context

A revision used to be a new quote row that pointed back through
`supersedes_id` and withdrew the old one. Every revision got its own id, so
links, relations, events and invoices had to follow the chain, and nothing
kept the quote exactly as the customer saw it once a draft changed. Quotes
also lacked what European offers need: prices that include VAT, a discount on
the whole document, a deposit, optional lines the customer picks, and a tax
breakdown per rate that an invoice can carry over. The portal (ADR 0070) let
guests read records, but a guest still needed the link token to answer.

## Decision

A quote is one working copy. `send_quote` publishes its row, lines and tax
lines as a snapshot in `quote_versions`, keyed by quote and revision; a
trigger refuses any update (`QUOTE_VERSION_FROZEN`). `revise_quote` puts the
same row back to draft at the next revision and ends the link. An accepted
quote can't be revised. `supersedes_id` is gone.

Totals are counted per document in `line-items-sql.ts` when the parent table
declares `prices_include_tax`, `discount_bps` or `discount_amount`, the
lines declare `optional`, or the module has a tax lines table. Lines count
when required or selected. The document discount (`discount_bps` of the net
amount, then `discount_amount`, capped at the net amount) is spread over the
(rate, code) groups by cumulative rounding, and tax is computed per group:
counted out of the gross amount with `prices_include_tax`, added otherwise.
The groups are written to `quote_tax_lines`, so they sum exactly to the
totals. `deposit_due` is `deposit_bps` of the total. Money stays bigint minor
units (ADRs 0024, 0037).

Acceptance takes the positions of the optional lines the customer picks,
recounts, and records the name, the user id, the IP address (the last
`x-forwarded-for` entry) and the user agent. `portal_quote` and
`respond_to_portal_quote` serve a signed-in guest without a token, through
`ctx.scope.guest` or a guest of the quote's company or contact.

`invoice_from_quote` copies only the counted lines, adds one negative
`Discount` line per tax rate from the tax lines, and passes
`prices_include_tax`, which invoices now take as an optional column. Both new
tables are adoptable (ADR 0098) and carry `bsb_tenant_scope` (ADR 0099).

## Alternatives considered

Keeping a row per revision lost: the id changes on every revision, and a
snapshot is still needed to show what was sent. Storing the discount on each
line lost: a document discount the customer reads as one amount would round
differently per line, and the tax breakdown would not match the total.
Computing tax lines on read lost: invoices and exports need the same numbers
the customer accepted, without counting again.

## Consequences

Links, relations and invoices keep one quote id across revisions, and every
sent revision can be shown again. Code that read `supersedesId` or the
`revisionId` event field must read `revision` instead. An adopted quotes table
without the new columns keeps the old per-line recount and refuses the
settings it can't store (`QUOTE_PRICING_UNSUPPORTED`,
`QUOTE_DISCOUNT_UNSUPPORTED`, `QUOTE_DEPOSIT_UNSUPPORTED`).
