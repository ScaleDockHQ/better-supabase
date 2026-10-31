---
"better-supabase": minor
---

`better-supabase/blocks/dispatch` orders route stops through a new versioned port, `RouteOptimizer` (`apiVersion: 1`).

- `dispatch.optimizeRoute(technicianId, day, { locate, optimizer?, start?, end? })` orders a technician's day and plans it as their route.
- `nearestNeighbourOptimizer` is the fallback, `fetchRouteOptimizer` posts the stops to a routing service, and `optimizeStops` never throws: a failing optimizer or an invalid order falls back and reports `source: "fallback"`.
- `planVisits` orders the bookings of one shift for home care and flags visits that end after the shift.

No migration is needed.
