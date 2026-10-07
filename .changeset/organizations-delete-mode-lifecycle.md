---
"better-supabase": minor
---

`sql.modules.organizations.options.deleteMode` takes `"lifecycle"` and `"none"`. With `"lifecycle"`, `delete_organization` checks the `delete` permission and calls the data-lifecycle module's `request_organization_deletion`, so a deletion goes through its grace period, disabled tenant and purge job instead of an immediate hard delete. With `"none"`, the module writes no `delete_organization` (and drops an existing one), so no API entry point deletes an organization, and `createOrganizations().delete` fails.
