---
"better-supabase": patch
---

The access kit docs, the `canAssign` JSDoc and the `can_assign()` SQL comment recommend PermDock's assignment rule for the `permdock` model: `canAssign: "permdock.permdock_can_assign({role}, {tenant}::text)"`, with the manifest's `rls.schema`. This is the assignment rule the 0.5.0 note "the `permdock` and `custom` access models need an assignment rule" refers to; see [the access kit](https://bettersupabase.com/docs/kits/access#permdock). Without it only the service role assigns roles, since PermDock projects don't install the `tenant` module, and doctor (BS411) warns.
