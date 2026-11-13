# 0799: Generate permission keys from the block manifests

- Status: accepted
- Date: 2026-11-13

## Context

A freshly installed block's pages answered 403 for the owner until a catalog
migration inserted its permission keys and role grants (EX-807). Five hand-written
migrations did it for commerce, leave, payroll, DAM and advisories (EX-1232,
EX-1603). Keys used `read` and `manage` almost everywhere with ad hoc verbs in
between (EX-1231), and API key and OAuth scopes were edited by hand (EX-1330).
No manifest said which entities use record teams (EX-1322).

## Decision

`entities.<key>.permissions` is a map from a verb to the key it checks. A key is
`<block>.<entity>.<verb>` in snake case. The fixed verbs are `read`, `create`,
`update`, `archive`, `delete`, `export`, `import` and `manage`; a named domain
verb is any other snake_case word. A two-part key that `OPERATIONS` already
holds stays valid, so a manifest can declare today's keys without a rename.
`src/blocks/permission-keys.ts` validates this and
`tests/blocks/permission-keys.test.ts` runs it over every manifest.
`recordAccess: "team"` declares that an entity is filtered by record team.

`gen.permissionCatalog` (default `false`, catalog model only) makes `gen` write a
migration with a row for every key the installed blocks check
(`modulePermissionKeys`, after renames) or declare, and the default grants:
`owner` and `admin` hold every declared key, `member` holds declared `read` keys,
and the existing `DEFAULT_ROLES` patterns still decide every other key. Platform
keys get a row and no default grant. The migration ends in
`_better_supabase_permission_catalog.sql`, and a later run writes a new one that
holds all statements, as the read-sets migration does. The same run writes
`permission-scopes.ts` with `apiKeyScopes` (every tenant key) and `oauthScopes`
(the same without `manage` keys).

The nextjs example turns it on, and its migration
`20261212000000_better_supabase_permission_catalog_eec93676.sql` replaces the
need for another hand-written catalog migration. The earlier migrations are
pushed and stay.

This supersedes the two-part key rule of ADR 0130 for keys that are declared on
an entity; keys a module checks today keep their form.

## Alternatives considered

- Rename every enforced key to three parts now. Rejected: it changes the SQL of
  about 190 modules and every golden file, and breaks apps' role configs in one
  step. Declared keys let the rename move block by block.
- Emit the catalog for every project. Rejected: examples share one fixture
  directory, and two apps with different block sets would overwrite each other's
  file. The flag keeps it per app.
- Generate role grants in the `roles` model. Not done: that model reads
  `DEFAULT_ROLES`, where `<block>.*` already covers declared keys for admins.

## Consequences

The next block needs no catalog migration under the catalog model. The generated
migration does not remove keys of a block that is uninstalled. Declaring
`permissions` on more entities, and moving modules to three-part keys, happens
in the lanes that touch those blocks. The manifest field grows the server chunk,
and the baselines reset accordingly (ADR 0690).
