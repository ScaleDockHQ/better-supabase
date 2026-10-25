---
"better-supabase": patch
---

The profiles block works over an app profiles table whose `locale` column is an
enum or a domain, such as `public.app_locale`. `update_my_profile` writes the
locale through `better_supabase.as_column_type`, and a sign-up that maps a
metadata key to `locale` writes it through the new
`better_supabase.try_column_type`, which stores null for a value the type
rejects instead of failing the sign-up. `upgrade` and doctor (BS342) no longer
refuse an enum `locale`, and `add --adopt` no longer leaves it unmapped; they
still refuse an enum in a column the block writes as text.
