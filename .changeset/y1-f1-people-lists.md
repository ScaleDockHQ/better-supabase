---
"better-supabase": minor
---

Pages the people blocks by the block list contract (ADR 1077). `leave` gains
`requestPage`, `requestFacets`, `requestCount` and `getRequest`, with sorts on
`startsOn`, `endsOn` and `createdAt`, filters on status, type, member, employee
and dates, and `q` over the note and type. `employees` gains `page`, `facets`,
`count` and `get`. `document-templates` gains `templatePage`, `templateFacets`
and `templateCount`, and `deadlines` and `enrollments` accept `q` on their
pages. The SQL adds `page_leave_requests`, `get_leave_request`,
`page_employees`, `get_employee` and `page_document_templates`, and the
generated schema files need `better-supabase upgrade`. The array methods
`leave.list`, `deadlines.list`, `enrollments.list` and
`documentTemplates.listTemplates` keep working and are deprecated.

| Old                               | New                              |
| --------------------------------- | -------------------------------- |
| `leave.list`                      | `leave.requestPage`              |
| `deadlines.list`                  | `deadlines.page`                 |
| `enrollments.list`                | `enrollments.enrollmentPage`     |
| `documentTemplates.listTemplates` | `documentTemplates.templatePage` |
