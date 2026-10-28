# 0129: One naming convention for blocks

- Status: accepted
- Date: 2026-10-28

## Context

ADR 0093 gave every block a plain name and fixed the jargon names
(`work-items` became `tasks`, `parties` became `contacts`). It also froze
table names, permission keys, event types and hint codes at their 0.14
values so an installed database would move only its
`better_supabase.blocks` rows. That freeze held while the renames landed,
and it now leaves the surface split in two vocabularies.

The block is `tasks`, the table is `work_items`, the permission area is
`work_items`, the event is `work_item.created` and the hint is
`WORK_ITEM_NOT_FOUND`. The same split exists for `compliance`
(`policies`, `controls.*`), `activities` (`engagements`), `goals`
(`targets`), `automations` (`rules.*`), `timeline` (`activity_entries`),
`numbering` (`number_sequences.*`) and a dozen others. Generic nouns
(`document`, `request`, `policy`, `task`, `node`, `key`, `view`) repeat
across blocks, so an entity key or a hint code does not say which block it
belongs to.

## Decision

One convention, applied to every block. It is written out in the Naming
section of `docs/agents/blocks.md` and on the docs Naming page, and it
supersedes the sentence in ADR 0093 that froze table names, permission
keys, event types and hint codes at their 0.14 values.

1. Block names are kebab-case, and existing block names do not change.
2. An entity key equals its `singular`, and entity keys are unique across
   all blocks. A generic noun takes the block noun as a prefix
   (`knowledge_document`, `leave_request`, `drive_node`); the block that
   owns the plain noun keeps it (`documents` keeps `document`, `tasks`
   keeps `task` and `project`).
3. A table is the plural of its entity in snake_case (`compliance_policy`
   becomes `compliance_policies`). A table that is not an entity (a link,
   log or history table) starts with its entity's singular
   (`task_assignees`, `case_actions`). Uncountable nouns stay singular
   (`control_evidence`, `webhook_inbox`, `scim_sync_log`, `custom_emoji`).
   Acronym prefixes of a standard stay (`ssf_*`, `scim_*`, `oauth_*`).
4. `subject` is the SQL term and `record` is the docs term. The columns
   `subject_type` and `subject_id`, the `subjects` module and the
   `subject.*` events keep their names.
5. A permission key is `<area>.<verb>`, and the area is the block name in
   snake_case. `messaging`, `comments` and `channels` share `messages.*`
   because they share one table; `channels` keeps `channels.*` for channel
   settings. `organizations` owns `organization.*`, `members.*` and
   `platform.*`.
6. Permission verbs are `read`, `write`, `delete` (only when deleting
   differs from writing) and `manage`, plus domain verbs (`approve`,
   `submit`, `review`, `acknowledge`, `collect`, `assign`, `grant`,
   `assess`, `close`, `invite`, `record`). Never `view`, `edit` or
   `admin`, and a key never has three parts.
7. An event type is `<entity singular>.<past tense verb>`, where the entity
   is the one that changed, whichever block wrote it. Lifecycle verbs are
   `created`, `updated`, `deleted`, `archived`, `restored` and `purged`.
   Never `saved`, `removed`, `upserted` or `<attribute>_set`.
8. A hint code is `<ENTITY>_<REASON>` in upper snake case, from the entity
   singular (`CONTROL_FORBIDDEN`, `TASK_NOT_FOUND`).
9. SQL functions are named from the entity singular through `ctx.fn`:
   `create_<entity>`, `update_<entity>`, `get_<entity>`,
   `list_<entities>`, `delete_<entity>`, plus domain verbs
   (`close_case`, `assess_risk`). Hooks are `before_<entity>_<action>` and
   `after_<entity>_<action>`.
10. Exports are `create<Pascal>`, `<camel>Block` and `<camel>Events`.
    Acronyms are written as words: `createOauthServer`.
11. A docs page title is the block's plain name in title case, optionally
    with a short qualifier. The first sentence names the block by its block
    name, and the URL is `/docs/blocks/<block-name>`.
12. The manifest `category` decides the docs folder through `BLOCK_GROUPS`
    in `scripts/docs-drift.ts`.

The implementation lands as one breaking minor: rename maps in
`src/core/renames.ts`, data migrations for stored names, a codemod, doctor
checks, and one minor of compatibility for event delivery and client
methods.

## Alternatives considered

- **Keep the 0.14 freeze.** It keeps every migration small, but the docs,
  the config, the events and the errors keep naming blocks by their old
  nouns, and the generic-noun clashes cannot be fixed without it.
- **Rename blocks too.** A second block rename would move subpaths, exports
  and presets again for no gain; the block names are already plain.
- **Prefix every entity with its block.** Uniform, but `documents` would
  hold `documents_document`, and the common case gets worse.

## Consequences

Apps move their stored permission keys, subject types, event filters and
hint comparisons once, through a generated migration and a codemod. New
blocks have one obvious name for every object, and the audit scripts can
check the convention. Revisit if a future block genuinely needs a shared
permission area across three tables.
