---
"better-supabase": minor
---

Event types now follow one convention: `<entity>.<past verb>`, where the prefix is the entity the event is about. Each `saved` event is now `created` or `updated`, depending on whether the save inserted the row, and `party.enriched` is `company.enriched` or `person.enriched`, depending on the record. Run `better-supabase codemod 0.47` to rename the types in your code, config and SQL; it lists the split types, such as `agent.saved`, for review.

| Old                                                                         | New                                                                                     |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `work_item.*`                                                               | `task.*`                                                                                |
| `engagement.*`                                                              | `activity.*`                                                                            |
| `rule.*`, `rule.removed`                                                    | `automation.*`, `automation.deleted`                                                    |
| `access.requested`, `access.request_approved`, `access.ended`               | `access_request.requested`, `access_request.approved`, `access_request.ended`           |
| `custom_field.*`                                                            | `field_definition.*`                                                                    |
| `drive.node_*`                                                              | `drive_node.*`                                                                          |
| `forecast.snapshotted`                                                      | `forecast_snapshot.created`                                                             |
| `job.*` (hiring)                                                            | `job_opening.*`                                                                         |
| `leave.adjusted`                                                            | `leave_balance.adjusted`                                                                |
| the other `leave.*` events                                                  | `leave_request.*`                                                                       |
| `obligation.*`                                                              | `contract_obligation.*`                                                                 |
| `organization.domain_added`, `_removed`, `_updated`, `_verified`            | `sso_domain.created`, `.deleted`, `.updated`, `.verified`                               |
| `policy.*` (compliance)                                                     | `compliance_policy.*`                                                                   |
| `postmortem.*`                                                              | `incident_postmortem.*`                                                                 |
| `signature.*`                                                               | `signature_request.*`                                                                   |
| `support.*`                                                                 | `support_session.*`                                                                     |
| `time.invoiced`                                                             | `time_entry.invoiced`                                                                   |
| `variant.*`                                                                 | `product_variant.*`                                                                     |
| `waitlist.*`                                                                | `waitlist_entry.*`                                                                      |
| `webhook.*`                                                                 | `webhook_endpoint.*`                                                                    |
| `workflow.published`                                                        | `workflow_definition.published`                                                         |
| `segment.removed`, `hostname.removed`, `approval_policy.removed`            | `segment.deleted`, `hostname.deleted`, `approval_policy.deleted`                        |
| `marketplace_installation.removed`                                          | `marketplace_installation.deleted`                                                      |
| `credential.set`, `ai_tool_policy.set`                                      | `credential.updated`, `ai_tool_policy.updated`                                          |
| `flag.override_set`, `hostname.primary_set`, `incoming_webhook.enabled_set` | `flag.override_changed`, `hostname.primary_changed`, `incoming_webhook.enabled_changed` |
| `marketplace_invoice.state_changed`                                         | `marketplace_invoice.status_changed`                                                    |
| `<entity>.saved`, `marketplace_installation.upserted`                       | `<entity>.created` or `<entity>.updated`                                                |
| `party.enriched`                                                            | `company.enriched` or `person.enriched`                                                 |

An install that renames an entity names its events after the new name, as before: with `blocks.tasks.entities.task.name` set to `ticket`, `work_item.created` stays `ticket.created`.

The `sla.*` events keep their names: they are about a record's SLA clock, and neither an SLA policy nor a breach table fits them. Relation events such as `collection.entry_removed` keep `removed`, `field_value.set` keeps `set`, and notification types don't change.

The outbox stores the new types. `upgrade` renders a data step that renames the stored types in the outbox events and dead letters, automation triggers and timeline entries, and adds the new types to the type lists of outbox consumers and webhook endpoints while keeping the old ones. The automations rule sink also tests a rule whose trigger is a split type, such as `rule.saved`, against the events it became. The outbox option `legacyEventTypes` (deprecated, off by default) relays a renamed type under its old name for receivers outside the app, with the new name in the `currenttype` CloudEvents extension, which the library's sinks read through the new `eventTypeOf` (`better-supabase/events`). Doctor reports old types in the app's code (BS424), and BS422 no longer reports `activity.*`, which is now an event pattern. `EVENT_TYPE_RENAMES`, `EVENT_TYPE_SPLITS`, `isOldEventType`, `currentEventTypes` and `legacyEventType` (`better-supabase`) export the maps.
