---
"better-supabase": minor
---

Three more blocks declare tenant default seeds, applied by `seed_tenant_defaults`. `inbox` creates a "Help" inbox on the in-app channel. `attachments` creates the document types `contract`, `invoice`, `receipt`, `identity`, `report` and `other` (the drive uses the same types). `calendar` creates a "Public holidays" calendar for the locales `nl`, `de`, `fr`, `en-gb` and `en-us`, with an all-day event per holiday for the years 2026 to 2030, each with a stable `uid` so running the defaults again keeps existing events. Apply the new functions to an existing app with `better-supabase db diff`, then call `seed_tenant_defaults` for the organizations that should get them.
