---
"better-supabase": minor
---

Modules declare their links to other modules' entities (`names.links`): references, relations and conversions such as a quote created from a deal or an invoice from an order. Every conversion records its `created_from` link through one helper. `resolvePreset` adds `relations` when a selected pair declares a conversion, and the `crm`, `helpdesk`, `erp`, `manufacturing`, `marketplace`, `people`, `psa`, `ats`, `invoicing` and `field-service` presets install it. `better-supabase blocks view` prints a Links line, and doctor reports BS353 when installed modules declare a link and `relations` is missing.
