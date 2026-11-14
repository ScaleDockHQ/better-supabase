---
"better-supabase": minor
---

Declare the offline rules in the manifest. `EntitySurface.offline` now accepts
`{ scope, where, systemRows }` next to `true`, and `better-supabase powersync
streams` reads them for the teams, profiles, observations, medications and
activities streams. The generated sync streams are unchanged. The notification,
membership and attachment streams keep their joins in the generator.
