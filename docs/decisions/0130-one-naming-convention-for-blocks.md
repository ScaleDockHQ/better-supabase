# 0130: Name every block's entities, tables, keys, events and hints by one convention

- Status: accepted
- Date: 2026-10-29

## Context

ADR 0093 renamed the jargon blocks (work-items to `tasks`, parties to
`contacts`, engagements to `activities`) but kept table names, permission
keys, event types, hint codes and queue names at their 0.14 values, so an
installed database only moved its `better_supabase.blocks` rows. That left
two vocabularies side by side. The `compliance` block checks
`controls.*` keys, the `tasks` block records `work_item.*` events, docs
pages still carry the old titles, and permission keys mix `view`, `edit`
and `admin` with `read`, `write` and `manage`. Some keys have three parts
(`custom_fields.sensitive.read`), some events are named `saved` or
`removed`, and generic entity keys (`document`, `entry`, `policy`) collide
across blocks.

New blocks (the quality blocks in ADR 0132, the care and ERP blocks after
them) need one rule to follow, and the existing names need one rule to move
to.

## Decision

Every block follows this convention. It supersedes the sentence in ADR 0093
that froze table names, permission keys, event types and hint codes at their
0.14 values.

1. Block names are kebab-case. Existing block names do not change.
2. An entity key equals its `singular`. Entity keys are unique across all
   blocks. When the noun is generic (`document`, `request`, `entry`,
   `policy`, `task`, `type`, `location`, `key`, `link`, `view`, `field`,
   `node`, `server`, `snapshot`, `definition`, `project`) or another block
   uses it, prefix it with the block noun: `knowledge_document`,
   `leave_request`, `drive_node`. The block that owns the plain noun keeps
   it (`documents` keeps `document`, `tasks` keeps `task` and `project`).
3. A table is the plural of its entity in snake_case (`compliance_policy`
   becomes `compliance_policies`). A table that is not an entity (a link,
   log or history table) starts with its entity's singular:
   `task_assignees`, `case_actions`. Uncountable nouns stay singular:
   `control_evidence`, `webhook_inbox`, `subject_user_state`,
   `chat_state_cache`, `scim_sync_log`, `ai_message_feedback`,
   `ai_model_catalog`, `attachment_cleanup`, `custom_emoji`. Acronym
   prefixes of a standard stay (`ssf_*`, `scim_*`, `oauth_*`).
4. `subject` is the SQL term and `record` is the docs term. The columns
   `subject_type` and `subject_id`, the `subjects` module and the
   `subject.*` events keep their names.
5. A permission key is `<area>.<verb>`. The area is the block name in
   snake_case. Exceptions: `messaging`, `comments` and `channels` share
   `messages.*` because they share one table (`channels` keeps `channels.*`
   for channel settings); `organizations` owns `organization.*`,
   `members.*` and `platform.*`; `platform.*` stays for platform-wide
   actions.
6. Permission verbs: `read` (see), `write` (create and change records),
   `delete` (only when deleting differs from writing), `manage` (configure
   the block, act on everyone's records), plus domain verbs (`approve`,
   `submit`, `review`, `acknowledge`, `collect`, `assign`, `grant`,
   `assess`, `close`, `invite`, `record`). Never `view`, `edit` or `admin`.
   A key never has three parts: `custom_fields.sensitive.read` becomes
   `custom_fields.read_sensitive`.
7. An event type is `<entity singular>.<past tense verb>`, where the entity
   is the one that changed, whichever block wrote it. Lifecycle verbs:
   `created`, `updated`, `deleted`, `archived`, `restored`, `purged`. Never
   `saved` (emit `created` or `updated`), `removed` (emit `deleted`),
   `upserted`, or `<attribute>_set` (emit `<attribute>_changed`). Payload
   keys are camelCase and carry `organizationId` when the event has a
   tenant.
8. A hint code is `<ENTITY>_<REASON>` in upper snake case, from the entity
   singular: `CONTROL_FORBIDDEN`, `TASK_NOT_FOUND`.
9. SQL functions are named through `ctx.fn`, from the entity singular:
   `create_<entity>`, `update_<entity>`, `get_<entity>`, `list_<entities>`,
   `delete_<entity>`, plus domain verbs (`close_case`, `assess_risk`).
   Hooks are `before_<entity>_<action>` and `after_<entity>_<action>`.
10. Exports: `create<Pascal>`, `<camel>Block`, `<camel>Events`. Acronyms are
    written as words: `createOauthServer`.
11. Docs: the page title is the block's plain name in title case, optionally
    with a short qualifier ("Audits and inspections", "Usage and quotas");
    never a pre-0.15 name. The first sentence names the block by its block
    name. The URL is `/docs/blocks/<block-name>`.
12. Manifest `category` decides the docs folder through `BLOCK_GROUPS` in
    `scripts/docs-drift.ts`.

The convention is written down in three places that stay in step: this ADR,
the Naming section of `docs/agents/blocks.md` and the docs page
`concepts/naming.mdx`.

## Alternatives considered

- **Keep the 0.14 names and apply the convention to new blocks only.** Apps
  would learn two vocabularies forever, and every new block that integrates
  with an old one (cases calling the tasks block, acknowledgements on
  compliance policies) would mix them in one function.
- **Rename each block when it is next touched.** Each rename would be its own
  breaking release with its own codemod, and apps would migrate many times
  instead of once.
- **Free-form names checked only in review.** The drift ADR 0093 describes
  came from exactly that.

## Consequences

The existing names that break the convention move in one breaking minor:
rename maps for permission keys, subject types, event types and tables, data
migrations for the names stored in rows, a codemod, doctor findings for code
that still uses an old name, and one minor in which the old names keep
working beside the new ones. The surface renames that change no contract (docs
titles, slugs, comments, categories) ship first and break nothing.

New blocks pick their names from the convention without a design discussion.
Revisit when a block needs a name the rules forbid; add the exception here
rather than in the block.
