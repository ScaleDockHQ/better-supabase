---
"better-supabase": minor
---

Security, behaviour change: an API key now holds only the permissions its scopes map to. `cap_allows`, and so `member_can`, `can` and every policy and module that asks them, checks a request with an `api_key` claim against the key's scopes, mapped through `blocks.permissions.scopes`. A key with `*` holds every permission except the interactive-only ones, and a key with no scopes holds none. Before, a personal key held every non-interactive permission of its user whatever its scopes, and only policies that called `has_scope` narrowed it.

To migrate, find the keys whose access shrinks (`select id, name, scopes from better_supabase.api_keys where scopes = '{}'`) and give each the scopes it needs, or rotate it with new scopes, before you deploy. Run `better-supabase upgrade` to regenerate the `permissions` module. The API keys docs page has a section on scopes and permissions.
