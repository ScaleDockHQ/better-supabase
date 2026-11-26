---
"better-supabase": minor
---

Move the resource routes and the sign-in flows off `createNext` onto their own subpaths, so an app that does not import them does not ship them.

| Before                                                                                                                                             | After                                                                                |
| -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `bsb.resources(map)`                                                                                                                               | `createResources(bsb)(map)` from `better-supabase/next/resources`                    |
| `bsb.signInWithPassword(input)`                                                                                                                    | `createAuthFlows(bsb).signInWithPassword(input)` from `better-supabase/next/sign-in` |
| `bsb.verifyOtp`, `signInWithOtp`, `signUp`, `resend`, `resetPasswordForEmail`, `signInWithOAuth`, `exchangeCodeForSession`, `verifyMfa`, `signOut` | the same names on `createAuthFlows(bsb)`                                             |
