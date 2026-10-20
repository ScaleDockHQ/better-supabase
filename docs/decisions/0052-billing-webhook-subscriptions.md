# 0052: Billing can store subscriptions from webhooks

- Status: accepted
- Date: 2026-10-20

## Context

The billing module reads subscriptions from the Stripe Sync Engine tables.
An app that cannot run the Sync Engine had no plan, status or checkout guard,
and a second checkout for a subscribed tenant created a second subscription.
Tenants billed by another provider (a marketplace) had no way to be refused.

## Decision

`blocks.billing.options.subscriptions` is `sync-engine` (default) or
`webhook`. In webhook mode the `billing` module adds `billing_subscriptions`,
`upsert_billing_subscription` (an older `event_at` never overwrites a newer
one), `billing_plan_of_price` and `billing_checkout_block`. `createBilling`
checks `billing_checkout_block` and the app's `external` hook before
`checkout` and returns a `conflict` error with the hint
`BILLING_ALREADY_SUBSCRIBED` or `BILLING_EXTERNAL`. The module version stays
2 because the default mode is unchanged.

## Alternatives considered

Requiring the Sync Engine kept one source but excluded apps without it.
Reading subscriptions from Stripe on every call added latency and a Stripe
dependency to reads.

## Consequences

Both modes return the same status shape. Webhook mode has no item id, so
`syncSeats` needs the Sync Engine. Revisit if a third source appears.
