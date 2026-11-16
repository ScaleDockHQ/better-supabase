---
"better-supabase": minor
---

Pages the content, scheduling, work and platform blocks by the block list
contract (ADR 1077). `announcements`, `reminders`, `tags`, `saved-views`,
`custom-fields`, `incidents`, `advisories`, `time-entries`, `care-plans`,
`observations`, `calendar`, `bookings`, `tasks` (with projects) and `trash` gain
`page`, `facets`, `count` and a `get` that returns a `not_found` error, with
sorts, list filters and `q`. `prompts` gains `page`, `count` and `getPrompt`
(labels are a map, so it has no facet). `bookings` uses `pageBookings`,
`bookingFacets`, `countBookings` and `getBooking` because `page` reads slots.
`incidents` gains `getIncident`, and `tasks` gains `getTask`, because their `get`
returns `undefined`. Advisories also page vulnerabilities, observations page
definitions and calendar pages calendars. The SQL adds `page_*` and `get_*`
functions for each, so the generated schema files need `better-supabase
upgrade`. The array methods keep working and are deprecated.

| Old                            | New                              |
| ------------------------------ | -------------------------------- |
| `announcements.list`           | `announcements.page`             |
| `prompts.list`                 | `prompts.page`                   |
| `reminders.list`               | `reminders.page`                 |
| `tags.list`                    | `tags.page`                      |
| `savedViews.list`              | `savedViews.page`                |
| `tasks.list`                   | `tasks.page`                     |
| `customFields.listDefinitions` | `customFields.page`              |
| `incidents.list`               | `incidents.page`                 |
| `advisories.advisories`        | `advisories.page`                |
| `advisories.vulnerabilities`   | `advisories.pageVulnerabilities` |
| `timeEntries.list`             | `timeEntries.page`               |
| `carePlans.list`               | `carePlans.page`                 |
| `observations.list`            | `observations.page`              |
| `observations.definitions`     | `observations.pageDefinitions`   |
| `calendar.listCalendars`       | `calendar.pageCalendars`         |
| `bookings.list`                | `bookings.pageBookings`          |
| `trash.list`                   | `trash.page`                     |
| `imports.runs.list`            | `imports.runs.page`              |
