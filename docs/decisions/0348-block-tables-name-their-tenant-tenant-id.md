# 0348: Block tables name their tenant column tenant_id

- Status: accepted
- Date: 2026-11-07
- Amends: 0246, 0247, 0345, 0347

## Context

The catalog test of ADR 0247 counted 63 block tables whose tenant column is
`organization_id`, next to the many that already say `tenant_id`. The word of
ADR 0246 for the unit that owns rows is tenant.

## Decision

- The default `tenant` column of every block table is `tenant_id`: 77 registry
  defaults in 38 modules and the `rate_limit_rules` column. The rename is one
  explicit `column` row of `api/naming.json` per table, applied by
  `codemod naming` to an installed app and by the fixture migration
  `20261107231500_bsb_tenant_id_names.sql`; a generated migration then replaces
  the functions that read them.
- These keep `organization_id`, and the catalog test counts none of them,
  because they are not block tables or not columns:
  - `memberships.organization_id`, which names the app's `organizations` row it
    belongs to, like the table `organizations` itself.
  - The default tenant column of an app table (`blocks.audit.tenantColumn`,
    `config.subjects.<type>.tenant`, `data-lifecycle.auto.tenant`, metrics): the
    app owns its schema.
  - JSON keys and arguments of the SQL API (`organization_id` of the timeline
    batch, the flag definition, the API-key claim, the knowledge hit and the
    usage report), and the `{organization_id}` placeholder of an attachment
    path.
  - Tables an app adopts keep their own names; the config maps `tenant`.
- `blocks.memberships.names.organization` still renames the memberships and
  organizations entities and their functions. It no longer renames the tenant
  column of other block tables, which is `tenant_id` for every app.
- Code that read these columns by name changes: TypeScript readers of block rows,
  the audit export query, the fixture's hand-written functions
  (`bump_override_authz_versions`, `app_organization_invitations`), the seed and
  pgTAP files. The CentraKit validation project maps `tenant: "organization_id"`
  on its notification and webhook tables.

## Consequences

An app that reads one of these columns over `$client` or `queryRaw`, or
selects it in its own SQL, changes the name.
