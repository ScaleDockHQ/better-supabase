---
"better-supabase": patch
---

The memberships module lets `anon` execute `member_organization_ids` and `has_organization_role`. The restrictive tenant scope applies to every role, so an anonymous reader of a public table (a published storefront) hit "permission denied for function" before it reached the block's public policy. For `anon` both functions return no organizations and false.
