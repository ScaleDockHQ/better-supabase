---
"better-supabase": minor
---

Close the gaps task coordination left. A hold can open an approval (`blocks.tasks.options.hold.approval`): approving releases the task, and a rejection cancels it or, with `onReject: "keep"`, leaves it on hold. Messages carry who acted: `send` and comment `create` take `actor: { kind, name }`, and `Message` returns `authorKind` and `authorName`, which `message.sent` also carries as `actorKind` and `actorName`.

Upgrade notes:

- The messaging module is at version 2. Run `better-supabase upgrade`, then `better-supabase db diff` and apply the migration. It adds the nullable `author_kind` and `author_name` text columns to messages. An adopted messages table gets them only when you map them or run `codemod owned-columns`; without them the label is not stored and `authorKind` is `undefined`.
- `hold.approval` is off by default and needs the approvals block and the `held_at` column. When it is on, the tasks module adds the internal function `settle_task_hold`, which no role can call.
- Messages sent before the upgrade have no kind or name.
