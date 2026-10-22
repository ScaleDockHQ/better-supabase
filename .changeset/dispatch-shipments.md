---
"better-supabase": minor
---

Add the `dispatch` block (`better-supabase/blocks/dispatch`). It schedules work orders at a location or asset into time slots for technicians who are members, orders a technician's day as a route of stops, moves each order through `unscheduled`, `scheduled`, `en_route`, `on_site`, `done` and `cancelled` with an event for every step, and links the parts an order uses to assets or inventory items. `board()` returns the schedule and the backlog for a date range, and `dispatchSection` shows a record's work orders. Install it with `better-supabase add dispatch`.

Add the `shipments` block (`better-supabase/blocks/shipments`). It stores packages, addresses and labels, keeps a tracking timeline per shipment, and derives the status and delivery time from the latest tracking event, and `shipmentsSection` shows a record's shipments. Carriers plug in through the versioned `ShipmentCarrier` interface (`apiVersion: 1`); `flatRateCarrier` covers fixed prices, and `ingest()` records a carrier's signed tracking webhook once, however often it is delivered. `better-supabase/testing` adds `testShipmentCarrier`, the conformance case for carrier adapters. Install it with `better-supabase add shipments`.

The Next.js example adds a dispatch board, a technician's day and shipment tracking as UI recipes.
