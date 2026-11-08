---
"better-supabase": minor
---

Doctor BS381 flags `createNativeClient`, `powersyncEngine`, `attachmentQueueRoute` or `queryEngine` when it names a block table that one of your views projects, and BS382 fails a `subjects.<type>` config entry that disagrees with the table's `@bsb subject` comment.

`better-supabase powersync streams` now reads your schema files. A table you project through a view streams the view's columns (under the view's names) and its `where` rows, the authorization provider's version column (`authz_version`, `permissions_version`) is left out of every stream, a bigint `id` syncs as text, and the `membership_roles` stream covers the roles of every member of the user's organizations instead of the user's own.
