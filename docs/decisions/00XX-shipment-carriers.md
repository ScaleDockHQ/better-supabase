# 00XX: Ship through a versioned ShipmentCarrier and ingest tracking by webhook

- Status: accepted
- Date: 2026-10-22

## Context

The `shipments` block stores packages, addresses, labels and a tracking
timeline, and derives a shipment's status from its latest tracking event. Rates,
labels and tracking come from a carrier: a parcel service, an aggregator or the
app's own logistics system. ADR 0036 makes every SDK integration an optional
peer with a tested range, ADR 0024 already keeps payments and tax behind
versioned providers, and invariant 10 says extension interfaces carry an
`apiVersion`. Carriers push tracking updates as webhooks, often more than once
and out of order, and those requests have no Supabase user.

## Decision

The block talks to carriers only through `ShipmentCarrier` (`apiVersion: 1`,
`src/blocks/shipments/carrier.ts`): `rates`, `createLabel`, `track`, `cancel`
and an optional `parseWebhook`. Every method returns a `Result`, money is
`Money` in bigint minor units, and `shipmentCarrierOf` rejects an unknown
version. The library ships no carrier SDK adapter. It ships `flatRateCarrier`
for apps with fixed prices and for tests, and `testShipmentCarrier` in
`better-supabase/testing` as the conformance case any adapter runs.

Tracking reaches the database two ways. `refresh` polls `track` for one
shipment. `ingest(name, request)` hands the raw request to the carrier's
`parseWebhook`, which verifies the signature before it returns any update
(`flatRateCarrier` uses `verifyWebhook`: Standard Webhooks signatures, the
replay window and an optional `seen` store), and refuses a carrier without
one. It then calls `better_supabase.ingest_tracking_events`,
a security definer function granted only to `service_role`. Each event is
stored once per shipment (`unique (shipment_id, external_id)`, `on conflict do
nothing`), so a redelivered or re-polled webhook records nothing twice, and the
status and `delivered_at` follow the event with the latest `occurred_at`, not
the order in which events arrive.

## Alternatives considered

- An adapter per carrier SDK (EasyPost, Shippo, Sendcloud). Each would be an
  optional peer with its own tested range for a handful of calls, and apps
  ship with one carrier at most; the interface lets the carrier's own package
  or the app supply the adapter.
- Status as a column the app sets. It drifts from the timeline when events
  arrive late or out of order; deriving it from the latest event keeps one
  source of truth.
- Ingest through an authenticated route. Carriers can't sign in as a member,
  and a shared service-role call after signature verification is the pattern
  the billing webhooks already use (ADR 0052).

## Consequences

Any carrier plugs in without a release of better-supabase, and the conformance
case keeps adapters honest about errors, idempotency and webhook signatures.
The block can't offer a turnkey integration for a named carrier. A carrier
whose webhook can't be expressed as `CarrierTrackingUpdate[]`, or a breaking
change to the method set, needs `apiVersion: 2`.
