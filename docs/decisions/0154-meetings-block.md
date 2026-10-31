# 0154: Meetings are one block over subjects, reactions, documents and tasks

- Status: accepted
- Date: 2026-10-31

## Context

Boards, management reviews (ISO 9001 clause 9.3), one-on-ones and toolbox
talks all need the same record: an agenda, who attended in which role,
minutes, the decisions taken and the follow-up work. The repo already owns the
pieces: `reactions` counts votes, `documents` holds collaborative text,
`tasks` holds work, and `calendar` holds events. What is missing is the
record that ties them to one meeting. ADR 0150 lists no overlap with it.

## Decision

`meetings` is a block (`better-supabase/blocks/meetings`) with five tables:
`meetings`, `meeting_attendees`, `meeting_agenda_items`, `meeting_decisions`
and `meeting_action_items`. Every table is adoptable (ADR 0098).

- A meeting and a decision are subjects (`meeting`, `meeting_decision`). An
  attendee votes on a decision through the `reactions` `vote` kind, and
  `decide_meeting_decision` without a status settles it from `vote_tally`: more
  up than down passes, more down than up rejects, a tie defers.
- Minutes live in `meeting_agenda_items.minutes` (Markdown, per item). A
  meeting that needs minutes written by several people at once opens a
  `documents` document on its subject; the block stores no second copy.
- An action item is a real task. `add_meeting_action_item` calls
  `tasks.create_task` and `meeting_action_items` records only where the task
  came from (meeting, agenda item, decision). Deleting the task removes the
  link.
- `meeting_attendees` records presence (`invited`, `present`, `absent`,
  `excused`) and a role (`chair`, `secretary`, `attendee`, `guest`), with one
  chair per meeting. It is separate from a calendar RSVP.
- With `options.calendar` a planned meeting mirrors to the named calendar as
  event `meeting-<id>`, and its attendees mirror when the calendar attendees
  table has `email`, `user` and `role` columns. With `notifications` an invited
  attendee gets `meeting.invited`.
- Permissions are `meetings.read`, `meetings.write` and `meetings.manage`
  (ADR 0130). A member with `meetings.write` runs the meetings they created or
  chair or take the minutes of. Members without `meetings.read` read only the
  meetings they are invited to, through the security definer function
  `meeting_role`.
- Events are `meeting.created`, `.updated`, `.started`, `.held`, `.cancelled`,
  `.deleted`, `meeting_decision.recorded`, `.decided` and
  `meeting_action_item.created`. `options.kinds` lists the allowed kinds.
- The `qms` and `ehs` presets include it, and the block ships two recipes
  (`meeting-agenda`, `meeting-minutes`).

## Alternatives considered

- **Extend `calendar`.** A calendar event has no roles of its own, no agenda
  and no decisions. Merging them would put quality-management concepts into a
  scheduling block.
- **Store action items on the meeting.** ADR 0149 removed the same pattern from
  postmortems. Tasks already have assignees, due dates and states.
- **Store votes on the decision.** `reactions` already counts votes per
  subject and caller.
- **A numbering sequence for meetings.** Minutes are found by date and title;
  a number adds a dependency for no query.

## Consequences

- Management review evidence (clause 9.3) is a meeting of kind
  `management_review` with its decisions and tasks.
- The block requires `tasks`, so the presets that include it install tasks.
- Recurring meetings are not modeled; create each occurrence or use a calendar
  event with a recurrence rule next to it. Revisit if apps ask for series.
