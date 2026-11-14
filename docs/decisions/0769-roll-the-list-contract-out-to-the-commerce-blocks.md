# 0769: Roll the list contract out to the commerce blocks

- Status: accepted
- Date: 2026-11-13

## Context

ADR 0749 gave nine blocks `page`, `facets` and `count` over one SQL list
function. Lane G3 of the block consistency audit applies the same contract to
the commerce category. Four commerce blocks already have it (agent-checkout,
rfqs, tills and warehouse). Several others have no entity list to page, or read
through functions with their own signature. Of the rest, five list functions
already take a `filters jsonb` argument (commissions, periods and referrals),
production orders take a `filter jsonb`, and four take one positional argument
per filter (leases, shipments, gifts and pledges).

## Decision

Give these list entities the contract: commission, commission statement and
commission plan, period, referral and referral code, production order, lease,
shipment, gift and pledge.

The four positional list functions (`list_leases`, `list_shipments`,
`list_gifts` and `list_pledges`) change to `(tenant, filters jsonb)`, and
`list_production_orders` renames its `filter` argument to `filters`. The page
helper calls every list function with `{ tenant, filters }`, so one argument
shape is the contract. The old filters keep their meaning under camelCase keys
(`unit_id` is `unitId`, `page_size` is `limit`), and the clients' `list`
methods build the same filters, so a caller of `list` sees no change. A direct
SQL caller moves to the jsonb argument. Apply the generated migration, which
drops the old signatures.

The blocks with extra columns (`fields`) read a page through the same
`fields.rows` step their `list` uses.

Entities left for lane G5 keep their own reads: the accounting, banking,
billable-time, catalog, expenses, funding, inventory, invoices, ledger, reviews
and tax lists (positional arguments with cross-tenant or per-account forms),
because each needs its own signature decision.

## Alternatives considered

Adding a second function (`page_leases`) next to each positional one would keep
the old signatures, but it doubles the surface of each block and leaves two
filter vocabularies. The positional functions had no caller outside the blocks'
own clients and tests, so replacing them costs less.

## Consequences

The manifests of the blocks above declare `sorts`, `facets` and `filters`, so
the server chunk and the `./blocks/*` bundle entries grow as in ADR 0750. Both
baselines are reset from the CI-measured values in the same pull request.
