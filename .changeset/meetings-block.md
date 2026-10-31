---
"better-supabase": minor
---

New `meetings` block (`better-supabase/blocks/meetings`): meetings with an agenda, attendees and roles, minutes per agenda item, decisions the attendees vote on, and action items that become tasks.

- `create` plans a meeting of one of `options.kinds` with its attendees and agenda. `start`, `hold` and `cancel` move it through `planned`, `in_progress`, `held` and `canceled`; `setAttendee`, `removeAttendee`, `saveAgendaItem` and `deleteAgendaItem` change the team and the agenda.
- `recordDecision` adds a decision, attendees vote on it with the reactions block, and `decide` settles it from the votes or with a status you pass.
- `addActionItem` opens a task through the tasks block and links it to the meeting, an agenda item or a decision.
- A meeting has at most one chair. A member with `meetings.write` runs the meetings they created or chair or take the minutes of, and members without `meetings.read` read only the meetings they are invited to.
- The permission keys are `meetings.read`, `meetings.write` and `meetings.manage`. With `options.calendar` planned meetings mirror to a calendar, and with notifications an invited attendee is notified.
- The `qms` and `ehs` presets include the block, and the recipes `meeting-agenda` and `meeting-minutes` render the list and the minutes.

Add `meetings: {}` to `blocks`, run `better-supabase add meetings` and generate a migration.
