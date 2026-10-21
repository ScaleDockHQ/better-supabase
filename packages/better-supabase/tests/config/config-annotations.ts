/**
 * Descriptions and defaults for `schemas/config-v1.json`, keyed by config
 * path: `*` is any key of a record, `[]` an array item, and `$defs.<name>`
 * a shared definition. They stay out of the valibot schema so the CLI
 * bundle doesn't carry them; the renderer throws on a path the schema
 * doesn't have.
 */
export interface Annotation {
  readonly description?: string;
  readonly default?: unknown;
}

export const CONFIG_ANNOTATIONS: Readonly<Record<string, Annotation>> = {
  source: {
    description:
      "Where codegen reads the database from. Without any of these, $DATABASE_URL and then the local stack are used.",
  },
  "source.dbUrl": { description: "Postgres connection string." },
  "source.projectRef": {
    description:
      "Hosted project ref, read through the Management API read-only SQL endpoint.",
  },
  "source.accessToken": {
    description:
      "Management API token for projectRef. Defaults to $SUPABASE_ACCESS_TOKEN.",
  },
  "source.snapshot": {
    description: "Read a saved introspection snapshot instead of connecting.",
  },
  "source.lite": {
    description:
      "Read a Supabase Lite project's schema from [db] driver in supabase/config.toml. On when that key is present; false reads the database like any other project.",
  },
  schemas: {
    description: "Postgres schemas to generate.",
    default: ["public"],
  },
  casing: { default: "snake" },
  "tables.*.serviceRole": {
    description:
      "Only service_role reaches the table. Models are still generated; doctor (BS106) checks that anon and authenticated have no grants.",
  },
  "tables.*.insertOptional": {
    description:
      "Database names of not-null columns an insert may leave out because the database fills them, for example from a before insert trigger.",
  },
  output: {
    description: "Main generated module.",
    default: "src/lib/supabase/generated.ts",
  },
  postgrestVersion: {
    description: "PostgREST major version written to database.types.ts.",
    default: "13",
  },
  codecs: {
    description: "Runtime types for timestamps, int8 and numeric columns.",
  },
  "codecs.timestamptz": { default: "string" },
  "codecs.int8": { default: "number" },
  "codecs.numeric": { default: "number" },
  relations: { description: "How generated relations are typed." },
  "relations.nullableUnderRls": {
    description:
      "Type to-one includes of tables with row level security as nullable, since a policy can hide the related row.",
    default: false,
  },
  json: { description: "Types for jsonb columns, keyed by `table.column`." },
  "json.*.import": { description: "`./path.ts#TypeName`" },
  "json.*.schema": {
    description:
      "JSON Schema enforced by `better-supabase add jsonb-schemas` (pg_jsonschema).",
  },
  "json.*.type": { description: "Inline TypeScript type." },
  generators: {
    description:
      "Generator plugins. Only available in better-supabase.config.ts.",
  },
  claims: {
    description:
      "Claim names shared by the SQL modules, codegen and runtime defaults.",
  },
  "claims.tenant": {
    description:
      "Top-level claim holding the active tenant id. Defaults to `tenant_id`.",
  },
  "claims.scope": {
    description:
      "`scope` of the tenant entries in the `memberships` claim. Defaults to `tenant`.",
  },
  "claims.features": {
    description:
      "Claim holding plan features per tenant. Defaults to `features`.",
  },
  "claims.memberships": {
    description:
      "Claim the memberships hook writes. Defaults to `memberships`.",
  },
  "buckets.*.path": {
    description:
      "Path template, e.g. `{organizationId}/{customerId}/logo.webp`, or several for a bucket that stores objects in more than one layout. A last segment `{...rest}` matches one or more segments.",
  },
  "buckets.*.policy": {
    description:
      "A generated storage policy (tenant, owner, public or none), or a policy through the access contract (tenant_ids_with, is_platform) or `sql` templates such as an authorization provider's.",
  },
  "buckets.*.policy.scope": {
    description:
      "`tenant` (default) or `platform`; with `sql`, any scope name the templates take.",
  },
  "buckets.*.policy.sql": {
    description:
      "SQL templates with `{permission}` and `{scope}` the policy calls instead of the access contract, or `provider` for `authorization.functions`.",
  },
  "buckets.*.versioning": {
    description: "Keep earlier object versions. bucket.apply() sets it.",
  },
  "buckets.*.lifecycle": {
    description: "When noncurrent versions expire. Needs versioning: true.",
  },
  topics: { description: "Realtime topic templates." },
  sensitive: {
    description:
      "Columns guarded by the noSensitiveSelect rule (`table.column` or `schema.table.column`).",
  },
  storagePaths: {
    description:
      "Text columns holding a storage object path (`table.column` or `schema.table.column`), mapped to a `buckets` key or bucket id. Typed as `StoragePath<'bucket-id'>`.",
  },
  functions: {
    description:
      "Function results gen may type as not null, keyed by function name. Results are nullable by default.",
  },
  "functions.*.notNull": {
    description:
      "true for the whole result, or the returns table columns that are never null.",
  },
  expose: {
    description:
      "Data API grants keyed by `table` or `schema.table`: privileges for authenticated, or per role. Written by the `grants` SQL module and checked by doctor (BS106).",
  },
  readSets: {
    description:
      "Modules exporting `defineReadSet` results. `gen` compiles them into the `read-sets` SQL module.",
  },
  entitlements: {
    description:
      "Where the `entitlements` SQL module finds each tenant's entitlements: a Stripe customer, a plan catalog or your own function.",
  },
  "entitlements.customer": {
    description:
      "`table.column` or `schema.table.column` holding the Stripe customer id.",
    default: "organizations.stripe_customer_id",
  },
  "entitlements.key": {
    description: "The tenant id column of that table.",
    default: "id",
  },
  "entitlements.memberships": {
    description:
      'Where has_entitlement and feature_claims read memberships: "provider" (the authorization provider\'s memberIds functions) or "tenant" (better_supabase.memberships). Defaults to "provider" when `authorization` is set.',
  },
  "entitlements.source": {
    description:
      'Where each tenant\'s entitlements come from: "stripe-sync" (the Stripe Sync Engine, the default), "custom" (your own better_supabase.tenant_entitlements), or a plan catalog in your tables.',
  },
  "entitlements.claim": {
    description:
      "The shape of the features claim feature_claims writes: false for {}, or maxTenants (at most that many tenants) and keys (short codes for feature keys).",
  },
  authorization: {
    description:
      "An authorization provider (apiVersion 1) the SQL modules, policies and doctor delegate to.",
  },
  "authorization.scopes[].idType": {
    description: "Required on the tenant scope.",
  },
  "authorization.functions": {
    description:
      "SQL templates with {permission}, {scope}, {user}, {tenant}, {role} and {tool}.",
  },
  "authorization.functions.permissionsFor": {
    description: "The permission keys {user} holds in {tenant}, as a text[].",
  },
  "authorization.functions.teamIdsOf": {
    description:
      "The team ids {user} belongs to, as a set. Under the provider model team_ids_of(), saved-views and collections call it.",
  },
  "authorization.functions.canApprove": {
    description:
      "Whether the caller may decide the tool call {tool} waits on in {tenant}.",
  },
  "authorization.decidingColumns[]": { description: "`schema.table.column`." },
  "authorization.delegation.scopes": {
    description:
      "OAuth scope to the permission keys it grants a delegated token.",
  },
  "authorization.approvals.distinctApprover": {
    description:
      "The user who asked for a tool call can't approve it. Default false.",
  },
  vectorSearch: {
    description:
      "Embedding columns keyed by `table` or `schema.table`. The `vector-search` SQL module writes `search_<table>(query, k)` for each.",
  },
  "vectorSearch.*": {
    description: "The embedding column, or the column and its search options.",
  },
  "vectorSearch.*.distance": { default: "cosine" },
  "vectorSearch.*.type": { default: "vector" },
  "vectorSearch.*.key": {
    description:
      "The primary key column db.$search({ score: true }) merges by.",
    default: "id",
  },
  "vectorSearch.*.hybrid": {
    description:
      "Fuses a full-text ranking over a tsvector column with the vector ranking (reciprocal rank fusion).",
  },
  "vectorSearch.*.hybrid.config": { default: "simple" },
  "vectorSearch.*.hybrid.k": { default: 60 },
  "vectorSearch.*.boost": {
    description: "A SQL expression over the row t the score is multiplied by.",
  },
  "vectorSearch.*.prefilter": {
    description: "Columns db.$search({ filter }) narrows before ranking.",
  },
  "vectorSearch.*.predicate": {
    description:
      "A SQL condition over the row t every candidate must meet, applied before ranking.",
  },
  "vectorSearch.*.boostMode": {
    description: "How boost combines with the score. Defaults to multiply.",
  },
  "vectorSearch.*.order": {
    description: "A SQL order by list over the row t that breaks score ties.",
  },
  subjects: {
    description:
      "The app's subject types, keyed by type name: the entities blocks attach tags, comments, fields and ranks to. Subject-bound SQL modules read this registry, and the `subjects` module writes `subject_title`, `subject_url` and `can_subject` from it.",
  },
  "subjects.*.table": {
    description: "`schema.table`, or a table in `public`.",
  },
  "subjects.*.id": { default: "id" },
  "subjects.*.idType": {
    description: "The id column's type, such as `uuid` or `bigint`.",
  },
  "subjects.*.tenant": {
    description:
      "The tenant column, or `false` for a subject without a tenant. Defaults to `organization_id`, or `<sql.naming.tenant>_id` when the tenant is renamed.",
  },
  "subjects.*.title": { description: "The column `subject_title` returns." },
  "subjects.*.url": {
    description:
      "The path `subject_url` returns, with `{column}` placeholders.",
  },
  "subjects.*.permissions": {
    description:
      "A permission key per action that `can_subject` checks in the subject's tenant.",
  },
  "subjects.*.scope": {
    description:
      "An authorization provider scope whose ids are this subject's ids.",
  },
  "subjects.*.cascade": { default: false },
  "subjects.*.deletedAt": { description: "The soft-delete column." },
  "subjects.*.rank": {
    description:
      "The rank key column and the column it is grouped by, for `move()`.",
  },
  realtime: { description: "Live query change broadcasts." },
  "realtime.tables": {
    description:
      "Tables that broadcast change signals (`table` or `schema.table`). Install with `better-supabase sql add realtime-tables`.",
  },
  "realtime.global": {
    description:
      "Tables in `tables` without a tenant column, which broadcast on one topic for every signed-in user.",
  },
  "realtime.users": {
    description:
      "Tables in `tables` whose rows belong to one user, mapped to the user column. They broadcast on a topic per user that only that user receives.",
  },
  "realtime.policies": {
    description:
      "Writes the realtime.messages policies of the topics `from` exports (defineTopic) to `output` on `sql sync`; `sql sync --check` fails when the file is stale.",
  },
  "realtime.triggers": {
    description:
      "Broadcast triggers `sql sync` writes to `policies.output` through the topic's trigger(), for topics `policies.from` exports. One topic with column values, a keys or row payload and one event name calls better_supabase.broadcast_topic() (the realtime-tables module); any other trigger gets a generated function.",
  },
  "realtime.triggers[].topic": {
    description: "The template of a topic `policies.from` exports.",
  },
  "realtime.triggers[].table": { description: "`table` or `schema.table`." },
  "realtime.triggers[].values": {
    description:
      "The column or lookup per placeholder. Defaults to the placeholder in snake_case. A row whose topic comes out null is not sent to it.",
  },
  "realtime.triggers[].event": {
    description:
      "The broadcast event name, or one per operation ({ insert, update, delete }). Defaults to the operation.",
  },
  "realtime.triggers[].payload": {
    description:
      "keys (default) sends the primary key and the placeholder values; row sends the whole row, which bypasses column grants. An object is the payload itself: each key is a column, a lookup, or { sql }, an expression on the row {row} (tg_op is the operation).",
  },
  "realtime.triggers[].topics": {
    description:
      "More topics the row change goes to, each with its own values.",
  },
  "realtime.triggers[].topics[].topic": {
    description: "The template of a topic `policies.from` exports.",
  },
  "realtime.triggers[].topics[].values": {
    description:
      "The column or lookup per placeholder. Defaults to the placeholder in snake_case.",
  },
  "realtime.triggers[].functionSchema": {
    description:
      "Schema for a generated function. Defaults to better_supabase, which the Data API does not expose.",
  },
  "realtime.triggers[].when": {
    description:
      "Filters updates: with { changed: [columns] } an UPDATE sends only when one of those columns changed. Inserts and deletes always send.",
  },
  "realtime.triggers[].when.changed": {
    description:
      "Columns (database names) whose change lets an UPDATE send. A trigger for updates alone compiles it into its WHEN clause.",
  },
  "$defs.triggerValue": {
    description:
      "A column of the changed row, or a lookup: the `select` column of the `from` row (`table` or `schema.table`) whose `key` (default id) equals `via`, a column or another lookup.",
  },
  blocks: {
    description:
      "The blocks to install and keep in sync: a list of names, or an object keyed by block name whose values set the block's mode, names, permission keys and options. The foundation blocks (tenant, access, updated-at, ensure-rls, ...) are configured here too.",
  },
  appTables: {
    description:
      "Tables the app owns, keyed by name, created in public by `better-supabase sql sync` with an id, the scope column, created_at and updated_at, row level security and policies for the scope. Money is a bigint of minor units next to a text currency column. ADR 0040.",
  },
  "appTables.*.columns": {
    description:
      "The table's own columns, keyed by lower snake name. id, created_at, updated_at, user_id and the tenant column are reserved.",
  },
  "appTables.*.columns.*.nullable": { default: true },
  "appTables.*.columns.*.default": {
    description:
      "now(), gen_random_uuid(), auth.uid(), true, false, a number, a 'quoted' literal, '{}' or '[]'.",
  },
  "appTables.*.columns.*.references": {
    description:
      "Another app table, auth.users, or a logical table of an installed block ({ block, table }).",
  },
  "appTables.*.columns.*.format": {
    description:
      "What the column holds. email, url, rating and percent add a check; phone, long_text, color and currency are hints for the UI and gen. ADR 0042.",
  },
  "appTables.*.columns.*.options": {
    description:
      "The values of a text column (single select) or of each element of a text[] column (multi-select), checked by the database.",
  },
  "appTables.*.columns.*.min": {
    description: "The smallest value of a number column, or the shortest text.",
  },
  "appTables.*.columns.*.max": {
    description: "The largest value of a number column, or the longest text.",
  },
  "appTables.*.columns.*.identity": {
    description:
      "An integer or bigint the database numbers (generated by default as identity).",
  },
  "appTables.*.scope": {
    description:
      "inherit follows sql.scope; user keeps rows per user; none lets signed-in users read and only the service role write.",
    default: "inherit",
  },
  "appTables.*.timestamps": { default: true },
  "appTables.*.id": {
    description:
      "The id's type. A reference to the table needs a column of the same type.",
    default: "uuid",
  },
  "appTables.*.unique": {
    description: "Sets of columns that are unique together.",
  },
  "appTables.*.indexes": { description: "Sets of columns to index, in order." },
  "appTables.*.subject": {
    description:
      "Registers the table as a subject, so comments, attachments, tags, versions, search and other blocks reach its rows (ADR 0043).",
  },
  "appTables.*.subject.rank": {
    description:
      "Adds a rank text column for move(), ordered within group when set.",
  },
  "appTables.*.subject.softDelete": {
    description:
      "Adds a deleted_at column that blocks treat as the soft-delete time.",
  },
  "appTables.*.rollups": {
    description:
      "Columns of public.<table>_view that aggregate a child table through its reference to this table (ADR 0044).",
  },
  "appTables.*.rollups.*.table": { description: "The app table to aggregate." },
  "appTables.*.rollups.*.via": {
    description: "The column of that table that references this one.",
  },
  "appTables.*.rollups.*.column": {
    description: "The column to aggregate; count takes none.",
  },
  "appTables.*.rollups.*.where": {
    description: "Counts only the rows whose select column equals one option.",
  },
  "appTables.*.lookups": {
    description:
      "Columns of public.<table>_view read from the row a reference points at (ADR 0044).",
  },
  "appTables.*.lookups.*.via": {
    description: "The column of this table that references another app table.",
  },
  "appTables.*.lookups.*.column": {
    description: "The column of the referenced row to read.",
  },
  "sql.workflow": {
    description:
      "How the SQL modules reach the database: pg-delta (Declarative Schemas 2.0), migra (declarative schemas 1.0) or migrations (written straight into a migration). Unset, supabase/config.toml decides, and pg-delta is the default.",
  },
  "sql.dir": { default: "supabase/schemas" },
  "sql.prefix": { default: "900_better_supabase" },
  "sql.testsDir": { default: "supabase/tests" },
  "sql.schema": {
    description:
      "The schema of every block's functions and managed tables, unless the block sets its own.",
    default: "better_supabase",
  },
  "sql.api": {
    description:
      "The Data API schema every block writes its security invoker entry points to, unless the block sets its own api or false.",
  },
  "sql.scope": {
    description:
      "Who a block's rows belong to, unless the block sets its own scope: tenant (the default), user (the signed-in user, no tenants) or none (one shared space every signed-in user uses).",
    default: "tenant",
  },
  "sql.naming": { description: "Names for the tenant concept in SQL." },
  "sql.naming.tenant": {
    description:
      "The tenant concept's singular name in table, function and column names, such as workspace or team.",
    default: "organization",
  },
  "seed.entry": { default: "supabase/seed.ts" },
  "seed.output": { default: "supabase/seeds/000_better_supabase.sql" },
  openapi: {
    description:
      "Deprecated: use specs. openapi.entry and openapi.output map onto it.",
  },
  "openapi.entry": { default: "src/lib/openapi.ts" },
  "openapi.output": { default: "openapi.json" },
  specs: {
    description:
      "The documents better-supabase spec emit writes (OpenAPI, AsyncAPI, Arazzo).",
  },
  "specs.entry": {
    description:
      "Module exporting a defineApi() result (or a function returning one) as api or default. Defaults to openapi.entry.",
    default: "src/lib/openapi.ts",
  },
  "specs.outputs[].format": {
    description: "A format id: openapi, asyncapi or arazzo.",
  },
  "specs.outputs[].version": {
    description: "Defaults to the format's default version.",
  },
  "specs.outputs[].output": {
    description:
      "File to write, relative to the root. Defaults to the format's file name.",
  },
  "specs.outputs[].overlays": {
    description: "Overlay files (JSON or YAML), applied in order.",
  },
  "specs.outputs[].serialize": {
    description:
      "Defaults to yaml when output ends in .yaml or .yml, otherwise json.",
  },
  "specs.outputs[].ui": {
    description:
      "Also writes a reference page (openapi.html for openapi.json) next to OpenAPI outputs.",
  },
  "specs.failOn": {
    description:
      "The lowest severity that fails spec emit, check and validate.",
    default: "error",
  },
  "specs.manifest": {
    description:
      "Also write the diagnostics manifest (JSON) to this file, like spec --manifest.",
  },
  "doctor.only": { description: "Run only these checks." },
  "doctor.format": {
    description:
      "Report format. The global --json flag still picks the JSON report.",
    default: "text",
  },
  "doctor.output": { description: "Write the report to this file." },
  gen: { description: "What better-supabase gen runs." },
  "gen.tasks": {
    description:
      "The steps gen runs, in order. Without a list: types, plus sql, spec, seed and scaffold when the project uses them. env runs only when listed.",
  },
  "gen.watchInterval": {
    description:
      "Milliseconds between checks in gen --watch and spec emit --watch.",
  },
  env: { description: "The env file better-supabase env writes." },
  "env.output": { default: ".env.local" },
  "env.prefix": {
    description:
      "Prefix for browser variables, such as NEXT_PUBLIC_; none for no prefix. Detected from the framework by default.",
  },
  "scaffold.api": {
    description:
      "What better-supabase scaffold api writes; the scaffold gen step keeps its generated file current.",
  },
  "scaffold.api.name": { default: "api" },
  "scaffold.api.basePath": { default: "/api" },
  integrations: { description: "The integrations init and add wrote." },
  "skills.agents": {
    description:
      "Agent folders skills install writes to. Defaults to the ones the project has, else agents.",
  },
  "keys.output": {
    description:
      "Signing key file better-supabase keys writes. Defaults to supabase/signing_keys.json.",
  },
  $env: {
    description:
      "Overrides per environment, keyed by name. Picked by --env, $BETTER_SUPABASE_ENV, or ci when $CI is set.",
  },
  "$defs.moduleConfig.mode": { default: "managed" },
  "$defs.moduleConfig.schema": { default: "better_supabase" },
  "$defs.moduleConfig.scope": {
    description:
      "Who the block's rows belong to: tenant, user or none. Defaults to sql.scope, then tenant.",
  },
  "$defs.moduleConfig.functions": {
    description:
      "Function name to the name the block writes it under, such as create_organization to start_company.",
  },
  "$defs.accessBlock.mode": { default: "managed" },
  "$defs.accessBlock.schema": { default: "better_supabase" },
  "$defs.accessBlock.scope": {
    description:
      "Who the block's rows belong to: tenant, user or none. Defaults to sql.scope, then tenant.",
  },
  "$defs.accessBlock.model": { default: "roles" },
  "$defs.accessBlock.platformClaim": { default: "platform_permissions" },
  "$defs.accessBlock.scopes": {
    description:
      "OAuth scope to the permission keys it grants a delegated token; merged over authorization.delegation.scopes.",
  },
  "$defs.environment": {
    description:
      "Keys an environment block overrides. Objects merge into the config; arrays and other values replace.",
  },
  "$defs.privilege": {
    description:
      "select, insert, update or delete, a column privilege such as `update(title, body)`, or every declared column but some, such as `select(*, -token_hash)`.",
  },
};
