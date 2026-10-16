---
"better-supabase": minor
---

Share links expire. `shareLinks.create(..., { expiresAt })` takes a `Temporal.Instant` (`SHARE_EXPIRY_INVALID` when it is not in the future), and `resolve` returns the link's `organizationId` and `expiresAt`. Every module that reads through a link (calendar feeds, booking pages, public forms, drive links, shared AI chats) now checks expiry the same way; shared AI chats used to ignore it. `create_share_link` takes `expires_at` as a sixth argument and drops the five-argument signature.

`revoke_share_link` lets only the link's creator or a member with `share_links.create` revoke a link, and returns `SHARE_NOT_FOUND` to anyone else. `list_share_links` returns the caller's own links and those in organizations where they hold `share_links.read`. `record_view` refuses a caller who is not a member of the organization (`SHARE_FORBIDDEN`), and no longer fails with an ambiguous `subject_type` column.

`authorization.functions.isApprover` takes an optional `{requester}` placeholder: the uuid of the user who asked (the approval's `requested_by`, the support admin, the chat's owner), so a provider that resolves out-of-office covers can refuse the requester's own delegator. Under the `provider` model, `delegate_approval` checks the delegate's membership through the provider's `memberIdsFor`.
