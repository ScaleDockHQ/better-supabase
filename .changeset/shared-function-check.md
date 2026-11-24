---
"better-supabase": minor
---

Doctor BS430 reports every reason a shared function can't run in a
`share: "tenant"` fill, numbered in one finding, and checks the functions it
calls the same way. It matches `sharedFunctions` on `schema.name`, so listing
`public.x` no longer admits a call to `private.x`. A call to a
`better_supabase` helper that passes the check on its own needs no listing;
the doctor page lists those helpers.

`better-supabase config functions --shareable 'public.*_payload'` runs the
check on functions you haven't listed yet and prints each verdict with its
reasons and the functions it calls.

Authorization providers can declare `permissionFilters`: helpers that return
the tenants where the caller holds a permission, with the argument that holds
the key. A shared function may call one with a literal key that the entry's
`permissions` list, so it can filter the way a tenant table's select policy
does.

With an authorization provider set, the snapshot also keeps the bodies of the
`language sql`, security invoker, non-volatile functions in the read schemas,
so BS430 and `--shareable` can read them. On the repo's own schema that adds
0.4 MB to `supabase/snapshot.json`.
