# 0076: One moderation item per subject, shared by reviews and comments

- Status: accepted
- Date: 2026-10-22

## Context

Reviews had their own moderation: a status, `moderated_by`, `moderated_at`
and a queue behind `reviews.manage`. Comments had none, and apps with forums,
posts or listings want the same things for their own records: members report
content, moderators decide from one queue, repeat offenders get banned, and
content with many reports disappears before a moderator gets to it. Copying
the review columns into every content module would give each one its own
queue, log and permissions.

## Decision

A `moderation` block keeps one item per `(organization, subject type, subject
id)` with a generic status (`pending`, `visible`, `hidden`, `removed`), the
open report count, the last decision and a log of decisions. Reports name one
of the configured reasons, one open report per member and subject. Decisions
are approve, hide, remove, restore and ban (remove plus a ban of the author).
At `autoHideThreshold` open reports a visible item is hidden automatically,
logged without an actor, and its reports stay open for a moderator.

Content modules keep their own tables and read the item. Reviews keep their
`status` column as a projection of the item, kept by a trigger on the item,
and `publish_review` and `reject_review` decide on the item. That is the
breaking part: the reviews module goes to version 2, requires moderation,
and its upgrade moves `moderated_by` and `moderated_at` onto items and logs
past decisions. Reviews written before the upgrade get their items from `sql
data`. Comments get a restrictive select policy that hides non-visible
comments from everyone except the author and moderators, through a security
definer function so the policy doesn't depend on the caller's access to
`moderation_items`. Removing a comment soft-deletes it, and a trigger keeps
banned members from commenting.

## Consequences

- One queue, one log and one set of permissions (`moderation.read`,
  `report`, `manage`, `ban`) cover comments, reviews and app records.
- Reporting needs `moderation.report`, which members get, so anonymous
  visitors can't report. Public reporting would need a rate limit first.
- There is no messages or posts module on this branch; comments stand in for
  them, and a later module integrates the same way reviews do.
- The block doesn't notify authors. Reviews keep their own notifications,
  and apps react to `moderation_item.decided` with a rule or sink.
- Inserting the module before reviews shifts the later module file numbers
  by one; the 0.13 to 0.14 guide says to resync.
