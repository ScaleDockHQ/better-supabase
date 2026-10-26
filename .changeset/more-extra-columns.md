---
"better-supabase": minor
---

More tables take the app's own columns: `blocks.calendar.options.calendarExtraColumns` (written by `create_calendar`, returned by `list_calendars`), and `blocks.employees.options.privateDetailsExtraColumns` and `contractExtraColumns` (written from `attrs.fields` by `save_employee_private_details` and `add_employee_contract`). `saved-views` writes an extra column that is `not null` without a `default` inside the insert, as tags and teams do. Without the options the modules render as before.
