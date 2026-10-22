# 0092: Posts keep only boards and posts; votes, replies and moderation stay in their blocks

- Status: accepted
- Date: 2026-10-22

## Context

Community forums and product feedback boards need posts with votes,
threaded replies, reports, hiding and bans, and a roadmap status. Each of
those already has a block: `reactions` keeps up and down votes with a score
per subject, `comments` threads replies on the messaging core (ADR 0062),
and `moderation` (ADR 0076) keeps one moderation item per subject with
reports, decisions and bans. The plan's Phase 9 asks for the vertical as a
thin block on those primitives rather than another copy of them.

## Decision

A `posts` block owns two tables, `post_boards` (kind `forum` or `feedback`)
and `posts` (title, body, status, pin, lock, merged-into and a reply count),
and registers `post` as a subject. Everything else goes through the other
blocks' SQL functions:

- Votes are reactions votes on the subject `post`; `list_posts` sorts `top`
  by the reactions score table, and `merge_posts` moves the duplicate's
  votes to the kept post unless the voter already voted there.
- Replies are comments on the subject `post`. A trigger on the comment
  thread's messages keeps `reply_count` and `last_activity_at`, and a guard
  refuses replies on a locked, merged or hidden post unless a moderator
  writes them.
- Every post gets a moderation item. A trigger projects the item's status
  onto the post's `moderation` column, so hiding or removing it in the
  moderation queue hides the post; `pre` moderation creates the item as
  pending. `moderation_banned` refuses posts from banned members.

## Alternatives considered

- A `post_votes` table: duplicates the reactions score and its realtime
  counts, and a score model couldn't read post votes the way it reads other
  subjects' votes.
- Replies as child posts: loses mentions, attachments, edit history and the
  comments recipes, and needs its own unread state.
- A `hidden` flag set by the posts block: two places would decide
  visibility, and the moderation queue wouldn't list posts.

## Consequences

- `posts` requires `subjects`, `messaging`, `comments`, `reactions` and
  `moderation`, so it is a heavier install than its two tables suggest.
- A post's reply count and moderation state are copies kept by triggers;
  a change made around them (a direct update of a moderation item's status
  by the service role) still fires the trigger, but a bulk import that
  disables triggers has to recount.
- The community and feedback presets build on this block; they land after
  the vertical presets PR, so the preset lists don't conflict.
