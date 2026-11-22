# 1188: Organization attributes are the columns the app adds, less an exclude list

- Status: accepted
- Date: 2026-11-22

## Context

`create_organization`, `update_organization` and `list_my_organizations` copy and
return `options.attributes` plus every column the app's schema files add to the
organizations table. A project that lists a column that the schema already adds
repeats a fact the schema holds, and a project that adds an internal column had
no way to keep it out of the attribute set.

## Decision

The attribute set is the columns the app adds to the table, whether or not
`options.attributes` lists them. `options.attributesExclude` removes columns from
that set. A column named in both options is an error, because the two entries
contradict each other. `better-supabase codemod config --prune` already removes
an `attributes` entry that the schema makes redundant, since it renders both
ways and compares the files.

## Alternatives considered

- Make `attributes` accept `"auto"`: it adds a second spelling for the default.
- Let `attributes` win over the exclude list: a silent choice hides a typo.

## Consequences

No render changes for a project that sets neither option. A project that wants a
column out of the attribute set writes one option instead of listing every other
column.
