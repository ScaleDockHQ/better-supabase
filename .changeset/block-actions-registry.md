---
"better-supabase": minor
---

Build the automation action registry from the installed blocks with `blockActions(blocks, { clients })`
from `better-supabase/blocks/automations`. Manifests gain a `handlers` field, `quotes.from_deal` creates a
quote from a won deal as a default automation that ships off, and doctor reports BS507 when blocks ship
actions and no source builds a registry.
