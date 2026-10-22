---
"better-supabase": minor
---

Add the `passes` block (`better-supabase/blocks/passes`): admission passes on QR codes and NFC tags. Issue a ticket for a booking or a pass for a resource, sign its token with the signing-keys block (`token`, `typ: vnd.pass+jwt`), and check holders in with `checkIn`, which verifies the signature against your JWKS before the database decides. Every scan is logged with why it was turned away, and passes without a booking count against the resource's capacity with its confirmed bookings and live holds. A passes section lists a record's passes, and a merged record keeps its passes. Install it with `better-supabase add passes`.
