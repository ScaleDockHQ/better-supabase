# 1078: Archive, restore and purge for posts (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 puts posts in its first group. A post is deleted by its author or a
moderator and nothing else hides it from a board. The moderation status
(`visible`, `pending`, `hidden`, `removed`) is a moderator's decision about
content, not the author's way to tidy a board, and a `closed` status means a
feedback idea was decided, not that it left the list.

## Decision

`posts` gets an optional `archived_at` column. `archive_post` and
`restore_post` set and clear it, are idempotent, record `post.archived` and
`post.restored` once, and are open to the post's author and to a moderator,
the same people who could delete it. `purge_post` replaces `delete_post` and
records `post.purged`. It needs `permissions.purge` when the app sets that
key, and otherwise the author or a moderator, as the delete did.

Read paths: `list_posts` hides archived posts unless `archived` is set (`true`
lists only archived ones). `get_post` still returns an archived post, so a
link keeps working. An archived post takes no votes (`vote_on_post`), no new
replies (the reply guard, like a locked or merged post), no edits by its
author or a moderator (`update_post`) and cannot be the target of a merge.
`set_post_state` and moderation still work, so a moderator can act on a
reported archived post. Exports keep archived posts, and search does not
filter them: the subject search reads `title` and `body`, and an archived
post stays findable by the people who may read it.

## Consequences

Breaking: `posts.delete`, `delete_post` and `post.deleted`. The 0.66 to 0.67
guide has the old-to-new table, and the migration adds `archived_at`.
