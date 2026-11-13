---
"better-supabase": minor
---

`sessionStatus`, `asSignedInUser` and the flags-sdk Data API transport now
call Supabase through supabase-js (`auth.getUser`, `auth.signInWithPassword`
and `rpc`) instead of building the requests.

Breaking: the notifications block's `avatars` option takes only a function of
the object path. Pass `getPublicUrl` from a supabase-js client for a public
bucket:

| Before                              | After                                                        |
| ----------------------------------- | ------------------------------------------------------------ |
| `avatars: { url, bucket: "users" }` | `avatars: (path) => users.getPublicUrl(path).data.publicUrl` |

`sessionStatus` reads a 403 whose body is not Auth's JSON as `unknown`
instead of `ended`, so a proxy or firewall response no longer ends a session.
