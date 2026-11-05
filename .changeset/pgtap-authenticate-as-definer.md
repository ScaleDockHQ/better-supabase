---
"better-supabase": minor
---

Breaking for generated pgTAP helpers: `tests.authenticate_as` reads `auth.users` through the `security definer` helpers `tests._user_id_by_email` and `tests._email_of`, so a test that is already signed in can switch to another user by email or id without `tests.clear_authentication()`. Run `better-supabase gen` to refresh `supabase/tests`.
