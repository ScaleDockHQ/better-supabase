---
"better-supabase": minor
---

Doctor warns with BS416 when the `support-sessions` block runs under the provider access model and `authorization.functions.isApprover` never handles `{kind} = 'support-session'`, in the template or in a function it calls. Such a template answers false, so no admin can approve a support request. BS413, which warns when support sessions run under a provider without `actorMayWrite`, now looks for the `support-sessions` block; it checked a block name that doesn't exist and never fired.
