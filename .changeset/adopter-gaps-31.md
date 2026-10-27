---
"better-supabase": minor
---

Security: block functions no longer let a caller through when a guard compares a null user column with `auth.uid()`. In the employees block anyone in the tenant could read an unlinked employee's contracts and private details and save their private details; the same pattern is fixed in every block that checked an owner, assignee, creator or holder this way.

- Calendar: `permissions.create`, `permissions.update` and `permissions.delete` gate event writes on top of `calendar.write`, and `options.readOnly: { column, values }` locks events (such as synced ones) against changes, deletes, cancels and splits (`CALENDAR_EVENT_READ_ONLY`). Event `kind` and `transparency` and attendee `role` and `response` can be enum columns of the app's tables. `cancelOccurrence` also takes `{ seriesId, originalStart }`.
- Employees: `create_employee` reads only the extra column keys from `attrs`, so a block key such as `status` no longer fails on an adopted enum column, and an omitted `not null default` extra column gets its default. `updateContract({ salary: null })` keeps an app table's currency.
- Tasks: `options.notify: false` leaves assignment notifications to the app, and the `work_item.assigned` notification carries the item's title as its subject label and an action path from `options.actionPath` (`{id}`, `{identifier}`).
- Share links: `blocks["share-links"].on` limits sharing to the listed subject types, including the types other blocks share.
- Data lifecycle: exports leave out `share_links.token_hash`.
- Custom fields: in the keyed layout with an integer rank, a field without a rank goes after the record's last one instead of writing `NULL`.
