# 0969: Run Stripe in the example from env keys

- Status: accepted
- Date: 2026-11-14

## Context

The example installed the `billing` block but had no way to receive Stripe
events, hand them to the block or start Checkout (EX-1608). Its plan picker read
the plan from the seeded `subscriptions` row only, and `/settings/marketplace`
asked for a Vercel configuration id although PR #902 added the member-readable
`marketplace_installation_for` and `marketplace_resources_for` (EX-516).

## Decision

`src/features/billing/billing-stripe.ts` builds the webhook inbox and the
billing block lazily from `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` and
`DATABASE_URL`. `POST /api/stripe` stores a verified event once and
`GET /api/stripe/process` (bearer `CRON_SECRET`) hands the stored events to
`billing.handleStripeEvent`. Both answer 503 or 401 without their keys, so the
example runs and builds without Stripe.

The plan picker reads the plan from `billing.overview` when Stripe holds a
subscription, matched to a plan through `STRIPE_PRICE_PRO` and
`STRIPE_PRICE_ENTERPRISE`, and from the seeded row before that. Checkout maps a
plan to its price the same way, so no migration adds a price column and no
test price ids are committed. The marketplace page and a resource page read the
installation through the tenant-scoped functions, and the seed links one
installation to the first organization.

## Alternatives considered

A `plan_prices` table read through `blocks.billing.options.plans`: it needs a
migration and price ids in the seed, which are Stripe account data. The env keys
carry the same mapping and stay out of the repository.

## Consequences

A maintainer sets the Stripe test keys and the two price ids in the three Vercel
environments and points a Stripe webhook endpoint and a cron at the two routes.
Until then Checkout answers `unsupported` and the example shows the seeded plan.
