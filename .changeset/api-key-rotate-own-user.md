---
"better-supabase": patch
---

`rotate_api_key` refuses a personal key (one with a user) unless the caller is that user or the service role, with `API_KEY_FORBIDDEN`. Before, a holder of `api_keys.manage` could rotate a colleague's key and receive a secret that acts as that colleague. Revoking stays open to key managers. Run `better-supabase upgrade` to regenerate the api-keys module.
