---
"better-supabase": minor
---

Close the gaps a production Expo, oRPC and MCP app hit on the blocks. See the
0.17 to 0.18 migration guide.

- Security: `team_ids_of(member)` refuses a signed-in caller that names another
  user, and `list_members` checks a key `blocks.organizations.permissions.listMembers`
  can remap. The profiles email mirror is stored lowercase, with a backfill.
- The audit block takes `ipHeader`, `staffClaim` and `subjectColumns`.
- The oRPC, Hono, `handle()` and MCP middleware take `cookies: false` for bearer
  tokens and API keys only. oRPC contexts accept `headers` and `url`.
- `blocks.memberships.options.roles.many` lets a member hold several roles
  (memberships version 3), with `addMemberRole` and `removeMemberRole`, and
  invitations take `defaultRole` and `onAccept`.
- Notifications (version 9) render per delivery and per locale, and take
  `actions` and `resolve({ resolution })`. Push (version 2) retries Expo sends,
  stores tickets and records receipts with `devices.checkReceipts()`.
  Profiles gain a `locale` column; `add --adopt` leaves it unmapped when the
  app's `locale` column is an enum.
- Attachments take `offline`: client ids, an upload trigger, a cleanup queue
  with `createAttachmentSweeper`, and an `{ext}` path placeholder.
- PowerSync: `better-supabase powersync streams` and `gen.powersync` write the
  Sync Streams and the publication migration for notifications and attachments.
  `better-supabase/powersync` adds `powersyncNotificationsTransport`,
  `notificationRecipientsRoute`, `powersyncTopicPort` and
  `attachmentQueueRoute`, and `gen` marks the other block instances as needing
  the network on native.
- Every block types `extraColumns`, and memberships, organizations and teams type
  their nested options. Column types accept quoted defaults and casts.
- `acceptInvitationById` and `declineInvitationById` emit `invitation.accepted`
  and `invitation.declined`. The access-requests approve key is in the typed
  permission registry, and doctor BS409 compares
  `tokenHook.activeOrganizationFrom` with `blocks.permissions.activeTenant`.
