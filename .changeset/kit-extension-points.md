---
"better-supabase": minor
---

Kits share one set of extension points: typed events, policy callbacks, SQL hooks and fixed attribute names.

- `betterSupabase.on("kit", handler)` receives `support.*`, `org.*`, `invitation.*`, `notification.*` and `webhook.*` events with a copy of their data. `onKitEvent(betterSupabase, "support.*", handler)` from `better-supabase/events` filters by type or prefix and types the data.
- `forwardKitEvents()` and `kitCloudEvent()` send kit events to an `EventSink` as CloudEvents, and `traceKitEvents()` from `better-supabase/otel` records them with the `KIT_ATTRIBUTES` names (`better_supabase.org.id`, `better_supabase.support.session_id`, ...).
- Policy callbacks (`Policy`, `PolicyDecision`) fail closed: only `true` allows, and a throw or rejection denies.
- `kits.<module>.hooks` sets where a module looks for the app's `before_*` and `after_*` SQL functions, and `kits.<module>.events: false` stops it writing its events to the outbox.
