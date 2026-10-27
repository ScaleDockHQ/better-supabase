/**
 * Descriptions and defaults for `schemas/config-v1.json`, keyed by config path:
 * `*` is any key of a record, `[]` an array item, and `$defs.<name>` a shared
 * definition. They stay out of the valibot schema so the CLI bundle doesn't
 * carry them; the renderer throws on a path the schema doesn't have.
 */
export interface Annotation {
  readonly description?: string;
  readonly default?: unknown;
}

export const CONFIG_ANNOTATIONS: Readonly<Record<string, Annotation>> = {
  "database.source": {
    description:
      "Where codegen reads the database from. Without any of these, $DATABASE_URL and then the local stack are used.",
  },
  "database.source.dbUrl": { description: "Postgres connection string." },
  "database.source.projectRef": {
    description:
      "Hosted project ref, read through the Management API read-only SQL endpoint.",
  },
  "database.source.accessToken": {
    description:
      "Management API token for projectRef. Defaults to $SUPABASE_ACCESS_TOKEN.",
  },
  "database.source.snapshot": {
    description: "Read a saved introspection snapshot instead of connecting.",
  },
  "database.source.lite": {
    description:
      "Read a Supabase Lite project's schema from [db] driver in supabase/config.toml. On when that key is present; false reads the database like any other project.",
  },
  "database.schemas": {
    description: "Postgres schemas to generate.",
    default: ["public"],
  },
  "gen.casing": { default: "snake" },
  "gen.tables.*.serviceRole": {
    description:
      "Only service_role reaches the table. Models are still generated; doctor (BS106) checks that anon and authenticated have no grants.",
  },
  "gen.tables.*.insertOptional": {
    description:
      "Database names of not-null columns an insert may leave out because the database fills them, for example from a before insert trigger.",
  },
  "gen.output": {
    description: "Main generated module.",
    default: "src/lib/supabase/generated.ts",
  },
  "gen.postgrestVersion": {
    description: "PostgREST major version written to database.types.ts.",
    default: "13",
  },
  "gen.codecs": {
    description: "Runtime types for timestamps, int8 and numeric columns.",
  },
  "gen.codecs.timestamptz": { default: "string" },
  "gen.codecs.int8": { default: "number" },
  "gen.codecs.numeric": { default: "number" },
  "gen.relations": { description: "How generated relations are typed." },
  "gen.relations.nullableUnderRls": {
    description:
      "Type to-one includes of tables with row level security as nullable, since a policy can hide the related row.",
    default: false,
  },
  "gen.json": {
    description: "Types for jsonb columns, keyed by `table.column`.",
  },
  "gen.json.*.import": { description: "`./path.ts#TypeName`" },
  "gen.json.*.schema": {
    description:
      "JSON Schema enforced by `better-supabase add jsonb-schemas` (pg_jsonschema).",
  },
  "gen.json.*.type": { description: "Inline TypeScript type." },
  "gen.generators": {
    description:
      "Generator plugins. Only available in better-supabase.config.ts.",
  },
  "auth.claims": {
    description:
      "Claim names shared by the SQL modules, codegen and runtime defaults.",
  },
  "auth.tenant": {
    description:
      "How the active tenant is found: the claim that holds its id and the column the memberships extension filters by.",
  },
  "auth.tenant.claim": {
    description:
      "Top-level claim holding the active tenant id. Defaults to `tenant_id`.",
  },
  "auth.tenant.column": {
    description:
      "Column the tenant plugin filters and fills on tenant-scoped tables. Defaults to `tenant_id`.",
  },
  "auth.claims.scope": {
    description:
      "`scope` of the tenant entries in the `memberships` claim. Defaults to `tenant`.",
  },
  "auth.claims.features": {
    description:
      "Claim holding plan features per tenant. Defaults to `features`.",
  },
  "auth.claims.memberships": {
    description:
      "Claim the memberships hook writes. Defaults to `memberships`.",
  },
  "auth.claims.permissions": {
    description:
      "Claim holding the caller's permission keys per tenant, written by permission_claims(). The hook sets `<permissions>_truncated` when it left keys out. Defaults to `permissions`.",
  },
  "database.buckets.*.path": {
    description:
      "Path template, e.g. `{organizationId}/{customerId}/logo.webp`, or several for a bucket that stores objects in more than one layout. A last segment `{...rest}` matches one or more segments.",
  },
  "database.buckets.*.policy": {
    description:
      "A generated storage policy (tenant, owner, public or none), or a policy through the access contract (tenant_ids_with, is_platform) or `sql` templates such as an authorization provider's.",
  },
  "database.buckets.*.policy.scope": {
    description:
      "`tenant` (default) or `platform`; with `sql`, any scope name the templates take.",
  },
  "database.buckets.*.policy.sql": {
    description:
      "SQL templates with `{permission}` and `{scope}` the policy calls instead of the access contract, or `provider` for `authorization.functions`.",
  },
  "database.buckets.*.versioning": {
    description: "Keep earlier object versions. bucket.apply() sets it.",
  },
  "database.buckets.*.lifecycle": {
    description: "When noncurrent versions expire. Needs versioning: true.",
  },
  "database.topics": { description: "Realtime topic templates." },
  "gen.sensitive": {
    description:
      "Columns guarded by the noSensitiveSelect rule (`table.column` or `schema.table.column`).",
  },
  "gen.storagePaths": {
    description:
      "Text columns holding a storage object path (`table.column` or `schema.table.column`), mapped to a `buckets` key or bucket id. Typed as `StoragePath<'bucket-id'>`.",
  },
  "gen.functions": {
    description:
      "Function results gen may type as not null, keyed by function name. Results are nullable by default.",
  },
  "gen.functions.*.notNull": {
    description:
      "true for the whole result, or the returns table columns that are never null.",
  },
  "database.expose": {
    description:
      "Data API grants keyed by `table` or `schema.table`: privileges for authenticated, or per role. Written by the `grants` SQL module and checked by doctor (BS106).",
  },
  "gen.readSets": {
    description:
      "Modules exporting `defineReadSet` results. `gen` compiles them into the `read-sets` SQL module.",
  },
  "auth.entitlements": {
    description:
      "Where the `entitlements` SQL module finds each tenant's entitlements: a Stripe customer, a plan catalog or your own function.",
  },
  "auth.entitlements.customer": {
    description:
      "`table.column` or `schema.table.column` holding the Stripe customer id.",
    default: "organizations.stripe_customer_id",
  },
  "auth.entitlements.key": {
    description: "The tenant id column of that table.",
    default: "id",
  },
  "auth.entitlements.memberships": {
    description:
      'Where has_entitlement and feature_claims read memberships: "provider" (the authorization provider\'s memberIds functions) or "tenant" (better_supabase.memberships). Defaults to "provider" when `authorization` is set.',
  },
  "auth.entitlements.source": {
    description:
      'Where each tenant\'s entitlements come from: "stripe-sync" (the Stripe Sync Engine, the default), "custom" (your own better_supabase.tenant_entitlements), or a plan catalog in your tables.',
  },
  "auth.entitlements.claim": {
    description:
      "The shape of the features claim feature_claims writes: false for {}, or maxTenants (at most that many tenants) and keys (short codes for feature keys).",
  },
  "auth.authorization": {
    description:
      "An authorization provider (apiVersion 1) the SQL modules, policies and doctor delegate to.",
  },
  "auth.authorization.scopes[].idType": {
    description: "Required on the tenant scope.",
  },
  "auth.authorization.functions": {
    description:
      "SQL templates with {permission}, {scope}, {user}, {tenant}, {role} and {tool}.",
  },
  "auth.authorization.functions.permissionsFor": {
    description: "The permission keys {user} holds in {tenant}, as a text[].",
  },
  "auth.authorization.functions.teamIdsOf": {
    description:
      "The team ids {user} belongs to, as a set. Under the provider model team_ids_of(), saved-views and collections call it.",
  },
  "auth.authorization.functions.canApprove": {
    description:
      "Whether the caller may decide the tool call {tool} waits on in {tenant}.",
  },
  "auth.authorization.decidingColumns[]": {
    description: "`schema.table.column`.",
  },
  "auth.authorization.delegation.scopes": {
    description:
      "OAuth scope to the permission keys it grants a delegated token.",
  },
  "auth.authorization.approvals.distinctApprover": {
    description:
      "The user who asked for a tool call can't approve it. Default false.",
  },
  "database.vectorSearch": {
    description:
      "Embedding columns keyed by `table` or `schema.table`. The `vector-search` SQL module writes `search_<table>(query, k)` for each.",
  },
  "database.vectorSearch.*": {
    description: "The embedding column, or the column and its search options.",
  },
  "database.vectorSearch.*.distance": { default: "cosine" },
  "database.vectorSearch.*.type": { default: "vector" },
  "database.vectorSearch.*.key": {
    description:
      "The primary key column db.$search({ score: true }) merges by.",
    default: "id",
  },
  "database.vectorSearch.*.hybrid": {
    description:
      "Fuses a full-text ranking over a tsvector column with the vector ranking (reciprocal rank fusion).",
  },
  "database.vectorSearch.*.hybrid.config": { default: "simple" },
  "database.vectorSearch.*.hybrid.k": { default: 60 },
  "database.vectorSearch.*.boost": {
    description: "A SQL expression over the row t the score is multiplied by.",
  },
  "database.vectorSearch.*.prefilter": {
    description: "Columns db.$search({ filter }) narrows before ranking.",
  },
  "database.vectorSearch.*.predicate": {
    description:
      "A SQL condition over the row t every candidate must meet, applied before ranking.",
  },
  "database.vectorSearch.*.boostMode": {
    description: "How boost combines with the score. Defaults to multiply.",
  },
  "database.vectorSearch.*.order": {
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
      "The tenant column, or `false` for a subject without a tenant. Defaults to `organization_id`, or `<blocks.memberships.entities.organization>_id` when the tenant is renamed.",
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
  "database.realtime": { description: "Live query change broadcasts." },
  "database.realtime.tables": {
    description:
      "Tables that broadcast change signals (`table` or `schema.table`). Install with `better-supabase add realtime-tables`.",
  },
  "database.realtime.global": {
    description:
      "Tables in `tables` without a tenant column, which broadcast on one topic for every signed-in user.",
  },
  "database.realtime.users": {
    description:
      "Tables in `tables` whose rows belong to one user, mapped to the user column. They broadcast on a topic per user that only that user receives.",
  },
  "database.realtime.policies": {
    description:
      "Writes the realtime.messages policies of the topics `from` exports (defineTopic) to `output` on `upgrade`; `upgrade --check` fails when the file is stale.",
  },
  "database.realtime.triggers": {
    description:
      "Broadcast triggers `upgrade` writes to `policies.output` through the topic's trigger(), for topics `policies.from` exports. One topic with column values, a keys or row payload and one event name calls better_supabase.broadcast_topic() (the realtime-tables module); any other trigger gets a generated function.",
  },
  "database.realtime.triggers[].topic": {
    description: "The template of a topic `policies.from` exports.",
  },
  "database.realtime.triggers[].table": {
    description: "`table` or `schema.table`.",
  },
  "database.realtime.triggers[].values": {
    description:
      "The column or lookup per placeholder. Defaults to the placeholder in snake_case. A row whose topic comes out null is not sent to it.",
  },
  "database.realtime.triggers[].event": {
    description:
      "The broadcast event name, or one per operation ({ insert, update, delete }). Defaults to the operation.",
  },
  "database.realtime.triggers[].payload": {
    description:
      "keys (default) sends the primary key and the placeholder values; row sends the whole row, which bypasses column grants. An object is the payload itself: each key is a column, a lookup, or { sql }, an expression on the row {row} (tg_op is the operation).",
  },
  "database.realtime.triggers[].topics": {
    description:
      "More topics the row change goes to, each with its own values.",
  },
  "database.realtime.triggers[].topics[].topic": {
    description: "The template of a topic `policies.from` exports.",
  },
  "database.realtime.triggers[].topics[].values": {
    description:
      "The column or lookup per placeholder. Defaults to the placeholder in snake_case.",
  },
  "database.realtime.triggers[].functionSchema": {
    description:
      "Schema for a generated function. Defaults to better_supabase, which the Data API does not expose.",
  },
  "database.realtime.triggers[].when": {
    description:
      "Filters updates: with { changed: [columns] } an UPDATE sends only when one of those columns changed. Inserts and deletes always send.",
  },
  "database.realtime.triggers[].when.changed": {
    description:
      "Columns (database names) whose change lets an UPDATE send. A trigger for updates alone compiles it into its WHEN clause.",
  },
  "$defs.triggerValue": {
    description:
      "A column of the changed row, or a lookup: the `select` column of the `from` row (`table` or `schema.table`) whose `key` (default id) equals `via`, a column or another lookup.",
  },
  blocks: {
    description:
      "The blocks to install and keep in sync: a list of names, or an object keyed by block name whose values set the block's mode, names, permission keys and options. The foundation blocks (tenant, access, updated-at, rls-guard, ...) are configured here too.",
  },
  "database.sql.workflow": {
    description:
      "How the SQL modules reach the database: pg-delta (Declarative Schemas 2.0), migra (declarative schemas 1.0) or migrations (written straight into a migration). Unset, supabase/config.toml decides, and pg-delta is the default.",
  },
  "database.sql.dir": { default: "supabase/schemas" },
  "database.sql.prefix": { default: "900_better_supabase" },
  "database.sql.testsDir": { default: "supabase/tests" },
  "database.sql.schema": {
    description:
      "The schema of every block's functions and managed tables, unless the block sets its own.",
    default: "better_supabase",
  },
  "database.sql.api": {
    description:
      "The Data API schema every block writes its security invoker entry points to, unless the block sets its own api or false.",
  },
  "database.sql.owner": {
    description:
      "Who a block's rows belong to, unless the block sets its own scope: tenant (the default), user (the signed-in user, no tenants) or none (one shared space every signed-in user uses).",
    default: "tenant",
  },
  "database.sql.ownTablePolicies": {
    description:
      "Whose policies govern the app's tables a block runs over, unless the block sets its own ownTablePolicies: block (the default) lets a block add its bsb_ policies where none of the app's covers them, and app keeps every bsb_ policy, permissive or restrictive, off them.",
    default: "block",
  },
  "database.seed.entry": { default: "supabase/seed.ts" },
  "database.seed.output": { default: "supabase/seeds/000_better_supabase.sql" },
  "database.seed.perTenant": { default: "supabase/seed.tenant.ts" },
  "api.openapi": {
    description:
      "Deprecated: use specs. openapi.entry and openapi.output map onto it.",
  },
  "api.openapi.entry": { default: "src/lib/openapi.ts" },
  "api.openapi.output": { default: "openapi.json" },
  "api.specs": {
    description:
      "The documents better-supabase spec emit writes (OpenAPI, AsyncAPI, Arazzo).",
  },
  "api.specs.entry": {
    description:
      "Module exporting a defineApi() result (or a function returning one) as api or default. Defaults to openapi.entry.",
    default: "src/lib/openapi.ts",
  },
  "api.specs.outputs[].format": {
    description: "A format id: openapi, asyncapi or arazzo.",
  },
  "api.specs.outputs[].version": {
    description: "Defaults to the format's default version.",
  },
  "api.specs.outputs[].output": {
    description:
      "File to write, relative to the root. Defaults to the format's file name.",
  },
  "api.specs.outputs[].overlays": {
    description: "Overlay files (JSON or YAML), applied in order.",
  },
  "api.specs.outputs[].serialize": {
    description:
      "Defaults to yaml when output ends in .yaml or .yml, otherwise json.",
  },
  "api.specs.outputs[].ui": {
    description:
      "Also writes a reference page (openapi.html for openapi.json) next to OpenAPI outputs.",
  },
  "api.specs.failOn": {
    description:
      "The lowest severity that fails spec emit, check and validate.",
    default: "error",
  },
  "api.specs.manifest": {
    description:
      "Also write the diagnostics manifest (JSON) to this file, like spec --manifest.",
  },
  "tooling.doctor.only": { description: "Run only these checks." },
  "tooling.doctor.format": {
    description:
      "Report format. The global --json flag still picks the JSON report.",
    default: "text",
  },
  "tooling.doctor.output": { description: "Write the report to this file." },
  gen: { description: "What better-supabase gen runs." },
  "gen.tasks": {
    description:
      "The steps gen runs, in order. Without a list: types, plus sql, spec and seed when the project uses them. env runs only when listed.",
  },
  "gen.watchInterval": {
    description:
      "Milliseconds between checks in gen --watch and spec emit --watch.",
  },
  "gen.contentMapper": {
    description:
      "Serve the schema types through the TypeScript 7.1 content mapper: gen writes a slim generated.ts and schema.bsb instead of the type files.",
    default: false,
  },
  "tooling.env": {
    description: "The env file better-supabase dev env writes.",
  },
  "tooling.env.output": { default: ".env.local" },
  "tooling.env.prefix": {
    description:
      "Prefix for browser variables, such as NEXT_PUBLIC_; none for no prefix. Detected from the framework by default.",
  },
  adapters: { description: "The integrations init and add wrote." },
  "tooling.skills.agents": {
    description:
      "Agent folders skills install writes to. Defaults to the ones the project has, else agents.",
  },
  "tooling.keys.output": {
    description:
      "Signing key file better-supabase dev keys writes. Defaults to supabase/signing_keys.json.",
  },
  $env: {
    description:
      "Overrides per environment, keyed by name. Picked by --env, $BETTER_SUPABASE_ENV, or ci when $CI is set.",
  },
  "$defs.moduleConfig.block": {
    description:
      "The block this entry installs. Defaults to the key; any other key is a second instance of the block it names.",
  },
  "$defs.moduleConfig.on": {
    description:
      "The record types an attachable block attaches to, as names or keyed by name with settings. Defaults to every record type.",
  },
  "$defs.moduleConfig.uses": {
    description:
      "Dependency block to the instance it uses, needed when that dependency is installed more than once.",
  },
  "$defs.moduleConfig.ownership": { default: "managed" },
  "$defs.moduleConfig.schema": { default: "better_supabase" },
  "$defs.moduleConfig.owner": {
    description:
      "Who the block's rows belong to: tenant, user or none. Defaults to database.sql.owner, then tenant.",
  },
  "$defs.moduleConfig.ownTablePolicies": {
    description:
      "Whose policies govern the app's tables this block runs over: block lets it add its bsb_ policies where none of the app's covers them, app keeps every bsb_ policy, permissive or restrictive, off them. Applies to every app table of the block. Defaults to database.sql.ownTablePolicies, then block.",
  },
  "$defs.moduleConfig.functions": {
    description:
      "Function name to the name the block writes it under, such as create_organization to start_company.",
  },
  "$defs.permissionsBlock.ownership": { default: "managed" },
  "$defs.permissionsBlock.schema": { default: "better_supabase" },
  "$defs.permissionsBlock.owner": {
    description:
      "Who the block's rows belong to: tenant, user or none. Defaults to database.sql.owner, then tenant.",
  },
  "$defs.permissionsBlock.ownTablePolicies": {
    description:
      "Whose policies govern the app's tables this block runs over: block lets it add its bsb_ policies where none of the app's covers them, app keeps every bsb_ policy, permissive or restrictive, off them. Applies to every app table of the block. Defaults to database.sql.ownTablePolicies, then block.",
  },
  "$defs.permissionsBlock.model": { default: "roles" },
  "$defs.permissionsBlock.platformClaim": { default: "platform_permissions" },
  "$defs.permissionsBlock.scopes": {
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
