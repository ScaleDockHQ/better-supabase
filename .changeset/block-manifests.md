---
"better-supabase": minor
---

Every block exports a manifest built with `defineBlock` (`commentsBlock` from `better-supabase/blocks/comments`): its SQL modules, option keys, its own events, the ports it provides and consumes, its creator, category and UI recipes. `createBlocks(options, blocks)` takes manifests and wires them on their ports (`notifier`, `files`, `attachments`, `workflows`, `sink`) instead of on names. `block.with(options)` sets a block's own options, and `block.using(create)` builds it with your own call to its creator. `defineBlocks(blocks, ...appEvents)` types the events of every block and the app's.

Breaking:

- `createBlocks` no longer takes factories or the `aiTaskNotification`, `reminderNotification`, `metricEvents` and `metricTime` options. Use `aiTasksBlock.with({ notification })`, `remindersBlock.with({ notification })` and `metricsBlock.with({ sink: { on, time } })`.
- The closed `BlockEventMap` is gone. Each block exports its own event map (`CommentsEvents` and `commentsEvents`), `onBlockEvent(betterSupabase, events, pattern, handler)` takes the events to type by, `blockEmitter`, `emitBlockEvent`, `BlockEvent`, `BlockEventSchemas` and `SubjectEventType` take an event map, and `defineEvents` declares app events.
- `createDrive` takes the attachments block as `attachments` instead of building one (`attachmentsSchema`, `requireScan` and `downloadTtl` move to that block), and the workflow builder takes the workflows block as `workflows` for schedule triggers.
- `createBuilder` is renamed `createWorkflowBuilder` and `createPushDevices` is renamed `createPush`.
