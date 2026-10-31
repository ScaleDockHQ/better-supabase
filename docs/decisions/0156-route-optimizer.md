# 0156: Route stops are ordered behind a versioned RouteOptimizer

- Status: accepted
- Date: 2026-10-31

## Context

`dispatch` stores a route as an ordered list of work orders, and home care
plans a caregiver's visits from `bookings` inside a `shifts` window. Both are
set by hand. Good orderings come from routing services, which an organization
picks and pays for, and the library must not depend on one of them. Work orders
hold a location id or a free-text address, not coordinates.

## Decision

The route stays in SQL (`plan_dispatch_route`); the ordering runs in TypeScript
in `better-supabase/blocks/dispatch`.

- `RouteOptimizer` is a versioned port (`apiVersion: 1`) typed structurally:
  `optimize({ start?, end?, stops })` returns the stop ids in order.
- `nearestNeighbourOptimizer` is the bundled fallback. `fetchRouteOptimizer`
  posts the request as JSON to a routing service over `fetch`, so a service
  needs no package.
- `optimizeStops` never throws. A failing optimizer, or an order that drops,
  repeats or invents a stop, gives the nearest-neighbour order with
  `source: "fallback"` and `fallbackReason`.
- `dispatch.optimizeRoute` reads the technician's day, asks the app to locate
  each work order, orders them and calls `planRoute`. Work orders without a
  place go last in their current order.
- `planVisits` orders the visits of one shift and walks the shift clock along
  the order, flagging visits that end after the shift.
- No new table, function or permission: planning keeps `dispatch.manage`.

## Alternatives considered

- Store coordinates on work orders. Geocoding is the app's concern, and
  `assets` already models coordinates (ADR 0066); `locate` lets an app read
  them from wherever they live.
- Order in SQL. A routing service is a network call and cannot run in a
  transaction.
- Bundle a vendor client. It would add a runtime dependency (invariant 1).

## Consequences

- A routing service is one function or one URL.
- Travel time in `planVisits` is a straight-line estimate; a service that
  returns durations can be used through `optimizeStops` and the app's own
  scheduling.
- Time windows per stop are not part of version 1 of the port.
