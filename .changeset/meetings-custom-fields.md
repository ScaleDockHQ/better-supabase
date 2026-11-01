---
"better-supabase": minor
---

`meetings` takes custom fields: `blocks.meetings.options.extraColumns` adds columns to the `meetings` table, `create` and `update` take their values under `fields`, and reads return them under `fields`. Pass a Standard Schema as `fields` to `createMeetings` to type and validate them.

`Meeting` gains a `fields` property (empty without extra columns). Run `better-supabase upgrade` and generate a migration after adding columns.
