---
"better-supabase": minor
---

Add the `incidents` block (`better-supabase/blocks/incidents`). Incidents carry a severity, a status timeline of updates, the components they affect and a postmortem. A component's status follows its open incidents and keeps an uptime history. Each organization can publish a status page, and `publicStatusPage(slug)` returns it to anyone, signed in or not: the public components with their daily uptime and the public incidents with their public updates, and nothing else. Install it with `better-supabase add incidents`.
