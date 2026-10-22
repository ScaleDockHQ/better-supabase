---
"better-supabase": minor
---

Add the `segments` block (`better-supabase/blocks/segments`). A segment saves a rules filter tree over one subject type, such as companies in the `customer` lifecycle, and keeps the records it matches in Postgres. `refresh(segmentId)` or `refreshDue()` on a cron re-evaluates it and writes `segment.entered` and `segment.left` for each record that joined or left, so a workflow can react. `members()`, `of(record)` and `list()` read the result. The block adds the `segments.read` and `segments.edit` permissions and the `maxMembers` option.

Add the `assignment` block (`better-supabase/blocks/assignment`). A queue covers one subject type, a `round_robin` or `weighted` strategy and an optional territory filter. `assign(organizationId, { type, id, fields })` picks an owner from the first matching queue, logs the pick and writes `subject.assigned`; the app writes the owner onto the record. The block adds the `assignment.read`, `assignment.manage` and `assignment.assign` permissions.
