---
"better-supabase": minor
---

Shrink the config and add the provider features a provider already expects. 0.82.0 on npm has none of this work, so 0.83.0 is the first version with `actionKeys`, approval floors (`operations[].approval`), `doctor.command`, the grouped baseline, BS427 and `codemod config --prune`. Breaking changes, with the old and new forms in the [0.82 to 0.83 guide](https://bettersupabase.com/docs/migration/0.82-to-0.83):

- `blocks` is a list of names and `{ block, name?, ... }` entries. Run `better-supabase codemod blocks-list`.
- The numbering tenant column defaults to `database.sql.tenantColumn` instead of `organization_id`. Run `gen sql` and read the diff.
- Record types are declared once, and `blocks.<name>.on` names a registered type. Run `codemod record-types`.
- Audit exemptions, data lifecycle, Data API privileges and same-tenant checks can sit in a `comment on table` as `@bsb` tags. Run `codemod table-tags`.
- An authorization provider can state `actionKeys`, `approverFor`, `managedUsers` and approval floors. The config entry still wins.
- `codemod config --prune` removes entries the render already supplies and bisects by block group.
- Doctor accepts a grouped baseline, reports BS427, BS706, BS707 and BS708, and fixes BS112, BS116, BS217, BS352 and BS365.
- Block fixes: tax codes are unique per tenant (run `validate constraint` once), `cancel_approval` reaches expenses and time entries, notifications can email non-members, and the import runner, template clones, audit statement trigger and fake client filters are corrected.
