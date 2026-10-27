---
"better-supabase": minor
---

The `permissions` claim carries only the keys the authorization provider marks `sqlComplete: true`: `better_supabase.member_permissions` and `permission_claims` drop the others, because a key in the token is a grant in the whole tenant. A provider whose `tokenHook.ownedClaims` lists `permissions` gets no permissions lines in the generated hook template, and `tokenHook.truncatedClaim` names the hook's truncated marker for `permissionsOf` and `permissionsAuthorizer`. Run `better-supabase gen` to regenerate the functions.
