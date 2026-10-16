---
"better-supabase": minor
---

Add the `better-supabase/blocks/mfa` and `better-supabase/blocks/sessions` entries, with React, Vue, Svelte and Solid
bindings. `useMfa` enrols, verifies and removes TOTP factors, and `useStepUp` raises a session to `aal2` after an
`INSUFFICIENT_AAL` refusal (`needsStepUp`). `useOAuthConsent` serves the consent page of the Auth OAuth server, and
`useOAuthGrants` lists and revokes the clients a user approved.
