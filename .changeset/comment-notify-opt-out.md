---
"better-supabase": minor
---

Comments and messaging notifications can be turned off again, and they no longer write a notification nobody receives.

- `blocks.comments.options.notify` (default `true`) restores the opt-out the 0.14 comments move removed: `false` sends no `comment.posted`. `blocks.messaging.options.notify` (default `true`) does the same for `message.mentioned`, `message.direct` and `message.replied`; following records and threads still works.
- `comment.posted` and `message.replied` are sent only when the record or thread has a follower besides the author and the mentioned members, or a `notification_audience` hook can add recipients.
- Every comment and message notification carries a `subject_label`: the record's `subject_title` from `config.subjects`, or the conversation's title. An adopted notifications table that requires a label no longer makes `create_comment` fail, and one that restricts types can turn the comment and message types off with `notify: false`.
