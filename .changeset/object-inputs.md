---
"better-supabase": minor
---

Breaking: every block client method with two or more positional arguments takes one object. A required argument becomes a property of the same name, a trailing options object is merged into the object when all its fields are optional and moves under `options` otherwise, and hook arguments become `[input]`. For example `catalog.setPrice(variantId, price)` is now `catalog.setPrice({ variantId, input: price })`, `drive.shareDrive(id, principal, "editor")` is now `drive.shareDrive({ id, principal, role: "editor" })`, and `onboarding.complete(checklist, step, organizationId)` is now `onboarding.complete({ checklist, step, organizationId })`. Ports other libraries implement, queue backends and record-binding `load` and `run` stay positional. Run `better-supabase codemod 0.47` to rewrite your calls; `better-supabase doctor` reports the calls it can still rewrite as BS509, and a new test fails on any block client method with two or more parameters.
