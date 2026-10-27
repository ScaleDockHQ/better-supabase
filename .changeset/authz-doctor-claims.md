---
"better-supabase": minor
---

Doctor BS407 reports a custom hook that calls `better_supabase.permission_claims` when the authorization provider owns the `permissions` claim. The new BS419 warns when app code calls `permissionsAuthorizer` while some provider keys lack `sqlComplete`, since the token leaves those keys out.
