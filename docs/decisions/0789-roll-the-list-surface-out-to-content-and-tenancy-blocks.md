# 0789: Roll the list surface out to the content and tenancy blocks

- Status: accepted
- Date: 2026-11-13

## Context

ADR 0749 gave the nine blocks that already paged one SQL list function behind
`page`, `facets` and `count`. Lane G5 owns the blocks outside work and
collaboration (G2), commerce (G3) and crm, people and scheduling (G4): admin,
ai, automation, content, database, developer, growth, identity, messaging and
tenancy. About 70 SQL list functions live there, and none of them pages. They
differ in more than names: some take positional arguments (`status`,
`include_archived`, `page_size`, `before`), some take no tenant because the
caller is the user (`list_my_sessions`, `list_my_organizations`), some are
child lists of one parent (`list_ai_run_steps_for`, `list_form_submissions`),
and some post-process rows through the app's `fields` schema.

## Decision

Move the entity lists that fit the recipe without changing what a caller
reads: a tenant-scoped list of one entity, read through the block's own
`tenant` option, with filters that are plain columns. In this lane that is:

- `legal_entity` (`legal-entities`): `list_legal_entities(tenant, filters)`
  replaces `(tenant, include_archived)`. `includeArchived` becomes a flag
  filter, the default entity stays first.
- `course` (`courses`): `list_courses(tenant, filters)` replaces `(tenant,
  status)`. A reader still sees only published courses. An unknown `status`
  value now matches no row instead of raising `COURSE_INVALID`, because a
  filter takes a list of values.
- `content_entry` (`content`): `list_content_entries(tenant, filters)` replaces
  `(tenant, filter)`. `query` becomes `q` (stored as `search`), and `type`,
  `locale`, `status` and `translationGroupId` take lists.

Each entity gets `page`, `facets` and `count` over one function and declares
its surface in `lists.ts`. `list` stays the capped convenience: it sends the
same filters, and the SQL now caps it (`legal_entity` and `course` at 200 by
default and 500 at most, `content_entry` at 50 and 200 as before).

`sso` stays on SCIM paging. Its SCIM resources page by `startIndex` and
`count` as RFC 7644 requires. Its two entity lists (`sso_provider`,
`organization_domain`) are bounded by the organization, take the organization
id per call and have no sort worth choosing, so they keep `domains()` and
`providers()` and gain no `page`.

Left for a later pass, with the reason each does not fit yet:

- Lists that take no tenant or take the organization id per call instead of
  `options.tenant` (`domains`, `forms`, `teams`, `imports`, `access-requests`,
  `api-keys`): `entityList` reads the tenant from the block options, so these
  need the contract to accept a per-call tenant first.
- Lists scoped to the caller (`sessions`, `organizations.list_my_*`,
  `notifications`, `inbox`): the user is the filter, not a column, and the
  list is not an entity list of the organization.
- Child lists of one parent (AI run steps, eval items, form submissions,
  course learners, consent receipts): they page under their parent, not as a
  top-level entity.
- Lists with no row identity to key on or with an app-side `fields` row mapper
  that needs a paged variant (`signatures`, `announcements`, `flags`,
  `waitlist`, `agents`).

## Alternatives considered

Moving all 70 lists in one change would mix three kinds of work (argument
shape, parent scoping, caller scoping) and break callers that pass an
organization id positionally. The recipe stays honest when each entity that
moves keeps its existing method names and options.

## Consequences

Each moved list grows by the same three methods as the nine in ADR 0749. The
follow-up that lets a block take the tenant per call unlocks the largest share
of what is left. `tests/blocks/list-surface.test.ts` lists the blocks that
moved, so a block that joins later adds itself there.
