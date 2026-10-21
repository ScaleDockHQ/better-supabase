---
"better-supabase": minor
---

Add `withClaims(postgres, claims, fn)` to `better-supabase/testing`. It runs
raw SQL as the user the claims describe (`role` and `request.jwt.claims` are
set, so `auth.uid()`, `auth.jwt()` and RLS apply) inside one transaction that
always rolls back.
