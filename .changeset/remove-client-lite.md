---
"better-supabase": minor
---

Breaking: `better-supabase/client/lite` is removed, along with the optional
peers `@supabase/auth-js` and `@supabase/realtime-js`. Browser clients come
only from `@supabase/ssr`'s `createBrowserClient`, so sessions follow its
cookies everywhere (ADR 0846).

| Before                                                                  | After                                                   |
| ----------------------------------------------------------------------- | ------------------------------------------------------- |
| `import { createLiteBrowserClient } from "better-supabase/client/lite"` | `import { createClient } from "better-supabase/client"` |

A route that used the lite client loads about 12 KB more. You can uninstall
`@supabase/auth-js` and `@supabase/realtime-js` if nothing else in the app
imports them.
