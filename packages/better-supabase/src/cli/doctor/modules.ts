import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { tenantClaimPaths, DEFAULT_ACTIVE_TENANT } from "../../config/index.ts";
import {
  adoptedTables,
  contractSignature,
  customContracts,
  type ModuleDeprecation,
  moduleDeprecations,
  moduleEventTriggers,
  moduleFileVersion,
  moduleLayout,
  migrationOptionUses,
  sharedRolesProblems,
  subjectColumns,
} from "../../sql/index.ts";
import { errorText } from "../errors.ts";
import { tomlGet } from "../supabase-toml.ts";
import { accessModule, entitlementsModule } from "./authorization.ts";
import { configuredHooks, hookClaims, isRecord, signatureOf } from "./hooks.ts";
import { literal } from "./live.ts";
import { reservedRoles } from "./reserved-roles.ts";
import {
  catalogOf,
  exposedSchemas,
  lineOf,
  policyObject,
  qualified,
  tableObject,
  permissionCatalogKeys,
} from "./shared.ts";

/** The non-empty string at a dotted path, as the tenant() plugin reads it. */
function claimAt(
  claims: Readonly<Record<string, unknown>>,
  path: string,
): string | undefined {
  let value: unknown = claims;
  for (const segment of path.split(".")) {
    value = isRecord(value) ? value[segment] : undefined;
  }
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

interface ContractCheck {
  readonly module: string;
  readonly schema: string;
  readonly name: string;
  readonly args: string;
  readonly returns: string;
}

function contractChecks(context: DoctorContext): ContractCheck[] {
  return customContracts(
    context.config.blockNames,
    moduleLayout(
      context.config,
      context.config.sql.testsDir,
      [],
      undefined,
      undefined,
      permissionCatalogKeys(context),
    ),
  ).flatMap((contract) =>
    contract.functions.map((fn) => ({
      module: contract.module,
      schema: contract.schema,
      name: fn.name,
      args: contractSignature(fn, contract.idType),
      returns: fn.returns.replaceAll("{id}", contract.idType),
    })),
  );
}

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

const ident = (name: string): string => `"?${escapeRegExp(name)}"?`;

/** Whether a `create function schema.name(` appears in the SQL files. */
function declared(context: DoctorContext, check: ContractCheck): boolean {
  const pattern = new RegExp(
    `create\\s+(?:or\\s+replace\\s+)?function\\s+${ident(check.schema)}\\.${ident(check.name)}\\s*\\(`,
    "i",
  );
  return (context.sqlFiles ?? []).some((file) => pattern.test(file.text));
}

const normalize = (types: string): string =>
  types
    .replaceAll(/\s+/g, " ")
    .replaceAll(/\s*,\s*/g, ", ")
    .trim();

const PRE_REQUEST_HOOK = `select h.hook,
  coalesce(pg_catalog.strpos(pg_catalog.pg_get_functiondef(pg_catalog.to_regproc(h.hook)), 'better_supabase.check_request') > 0, false) as calls
from (
  select (
    select pg_catalog.split_part(setting, '=', 2)
    from pg_catalog.pg_db_role_setting s
    join pg_catalog.pg_roles r on r.oid = s.setrole
    cross join lateral pg_catalog.unnest(s.setconfig) setting
    where r.rolname = 'authenticator' and s.setdatabase = 0
      and setting like 'pgrst.db_pre_request=%'
    limit 1
  ) as hook
) h`;

/** `rate-limit` in `blocks` without PostgREST's pre-request hook reaching `check_request()`. */
async function rateLimitHook(context: DoctorContext): Promise<FindingInput[]> {
  const db = context.database;
  if (
    !context.config.blockNames.includes("rate-limit") ||
    context.config.blocks["rate-limit"]?.options?.["preRequest"] === false ||
    !db ||
    "skipped" in db
  ) {
    return [];
  }
  let rows: { hook: string | null; calls: boolean }[];
  try {
    rows = await db.query(PRE_REQUEST_HOOK);
  } catch {
    return [];
  }
  const [row] = rows;
  if (!row || row.hook === "better_supabase.check_request" || row.calls) {
    return [];
  }
  return [
    {
      message:
        row.hook === null
          ? "pgrst.db_pre_request isn't set for authenticator, so better_supabase.check_request() never runs. Apply the migration `better-supabase sql data` writes, which sets it."
          : `pgrst.db_pre_request is ${row.hook}, which doesn't call better_supabase.check_request(), so rate limits never apply. Call it from ${row.hook}.`,
      target: "authenticator pgrst.db_pre_request",
    },
  ];
}

const DANGLING_AUDIT = `select a.target::oid::text as oid
from better_supabase.audited_tables a
where pg_catalog.to_regclass('better_supabase.audited_tables') is not null
  and not exists (select 1 from pg_catalog.pg_class c where c.oid = a.target::oid)
order by 1`;

/** `better_supabase.audited_tables` rows whose table no longer exists. */
async function danglingAuditRegistrations(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const db = context.database;
  if (!context.config.blockNames.includes("audit") || !db || "skipped" in db) {
    return [];
  }
  let rows: { oid: string }[];
  try {
    rows = await db.query(DANGLING_AUDIT);
  } catch {
    return [];
  }
  return rows.map((row) => ({
    message: `better_supabase.audited_tables registers the table with oid ${row.oid}, which no longer exists. It was dropped before the audit module's sql_drop event trigger was installed. Run \`better-supabase sql sync\` and apply the migration \`better-supabase sql data\` writes, which deletes such rows, or run \`delete from better_supabase.audited_tables where not exists (select 1 from pg_catalog.pg_class c where c.oid = target::oid)\`.`,
    target: `better_supabase.audited_tables ${row.oid}`,
  }));
}

/** Tables and columns adopt-mode modules use that the live database lacks. */
async function missingAdoptedColumns(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const db = context.database;
  if (!db || "skipped" in db) {
    return [];
  }
  const tables = adoptedTables(context.config.blocks);
  if (tables.length === 0) {
    return [];
  }
  const names = tables
    .map((table) => `(${literal(table.schema)}, ${literal(table.table)})`)
    .join(", ");
  let rows: { schema: string; name: string; column: string }[];
  try {
    rows = await db.query(
      `select table_schema as schema, table_name as name, column_name as column
      from information_schema.columns
      where (table_schema, table_name) in (${names})`,
    );
  } catch {
    return [];
  }
  return tables.flatMap((table): FindingInput[] => {
    const target = `${table.schema}.${table.table}`;
    const object = {
      kind: "table" as const,
      schema: table.schema,
      name: table.table,
    };
    const present = new Set(
      rows
        .filter(
          (row) => row.schema === table.schema && row.name === table.table,
        )
        .map((row) => row.column),
    );
    if (present.size === 0) {
      return [
        {
          message: `blocks.${table.module} is in adopt mode and maps its ${table.logical} table to ${target}, which the database does not have. Create it, or point blocks.${table.module}.tables.${table.logical} at the existing table.`,
          target,
          object,
        },
      ];
    }
    return Object.entries(table.columns)
      .filter(([, column]) => !present.has(column))
      .map(([logical, column]) => ({
        message: `blocks.${table.module} is in adopt mode and uses ${target}.${column} (${table.logical}.${logical}), but the table has no such column. Map blocks.${table.module}.columns.${table.logical}.${logical} to the column that holds it, or to null when the module allows that.`,
        target: `${target}.${column}`,
        object,
      }));
  });
}

const EVENT_TRIGGER_FIX =
  "Event triggers belong to no schema, so a schema diff limited to some schemas (`supabase db schema declarative sync -s ...`) leaves them out of the migration. Run `better-supabase sql sync`, then `better-supabase sql data`: the module's data migration creates it.";

/** Event triggers the `blocks` create that the database, or every migration, lacks. */
async function missingEventTriggers(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const expected = moduleEventTriggers(context.config.blockNames);
  if (expected.length === 0) {
    return [];
  }
  const db = context.database;
  if (db && !("skipped" in db)) {
    let rows: { name: string }[];
    try {
      rows = await db.query(
        "select evtname as name from pg_catalog.pg_event_trigger",
      );
    } catch {
      return [];
    }
    const present = new Set(rows.map((row) => row.name));
    return expected
      .filter((trigger) => !present.has(trigger.name))
      .map((trigger) => ({
        message: `The database has no event trigger ${trigger.name}, which the ${trigger.module} module creates. ${EVENT_TRIGGER_FIX}`,
        target: trigger.name,
      }));
  }
  const toml = context.configToml;
  if (toml === undefined) {
    return [];
  }
  const migrations = (context.sqlFiles ?? []).filter((file) =>
    file.path.startsWith(`${toml.dir}/migrations/`),
  );
  if (migrations.length === 0) {
    return [];
  }
  return expected
    .filter((trigger) => {
      const pattern = new RegExp(
        `create\\s+event\\s+trigger\\s+${ident(trigger.name)}\\s`,
        "i",
      );
      return !migrations.some((file) => pattern.test(file.text));
    })
    .map((trigger) => ({
      message: `No migration creates the event trigger ${trigger.name}, which the ${trigger.module} module creates, so a database built from the migrations lacks it. ${EVENT_TRIGGER_FIX}`,
      target: trigger.name,
    }));
}

/** Custom-mode modules whose contract functions the database or SQL files don't have. */
async function missingContracts(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const checks = contractChecks(context);
  if (checks.length === 0) {
    return [];
  }
  const db = context.database;
  const live = db && !("skipped" in db) ? db : undefined;
  if (!live) {
    return checks
      .filter((check) => !declared(context, check))
      .map((check) => ({
        message: `blocks.${check.module} is in custom mode, but no SQL file declares ${check.schema}.${check.name}(${check.args}). Write it, or switch the module to adopt or managed.`,
        target: `${check.schema}.${check.name}`,
        object: { kind: "function", schema: check.schema, name: check.name },
      }));
  }
  const names = checks
    .map((check) => `(${literal(check.schema)}, ${literal(check.name)})`)
    .join(", ");
  let rows: { schema: string; name: string; args: string; returns: string }[];
  try {
    rows = await live.query(
      `select n.nspname as schema, p.proname as name,
        oidvectortypes(p.proargtypes) as args,
        format_type(p.prorettype, null) as returns
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where (n.nspname, p.proname) in (${names})`,
    );
  } catch (cause) {
    return [
      {
        severity: "info",
        message: `Reading the custom module contract functions failed: ${errorText(cause)}`,
        target: "modules",
      },
    ];
  }
  return checks.flatMap((check): FindingInput[] => {
    const found = rows.filter(
      (row) => row.schema === check.schema && row.name === check.name,
    );
    const target = `${check.schema}.${check.name}`;
    const object = {
      kind: "function" as const,
      schema: check.schema,
      name: check.name,
    };
    if (found.length === 0) {
      return [
        {
          message: `blocks.${check.module} is in custom mode, but ${target}(${check.args}) doesn't exist. Write it, or switch the module to adopt or managed.`,
          target,
          object,
        },
      ];
    }
    const match = found.find(
      (row) => normalize(row.args) === normalize(check.args),
    );
    if (!match) {
      return [
        {
          message: `${target} takes (${found.map((row) => row.args).join(" | ")}); the ${check.module} contract calls it with (${check.args}).`,
          target,
          object,
        },
      ];
    }
    if (normalize(match.returns) !== normalize(check.returns)) {
      return [
        {
          message: `${target}(${check.args}) returns ${match.returns}; the ${check.module} contract expects ${check.returns}.`,
          target,
          object,
        },
      ];
    }
    return [];
  });
}

/** With the tenant claim as the active tenant, the hook must put it in the token. */
async function missingTenantClaim(
  context: DoctorContext,
): Promise<FindingInput[]> {
  if (!context.config.blockNames.includes("tenant")) {
    return [];
  }
  if (
    (context.config.blocks.access?.activeTenant ?? DEFAULT_ACTIVE_TENANT) !==
    "claim"
  ) {
    return [];
  }
  const userId = context.hookUser;
  const db = context.database;
  if (!userId || !db || "skipped" in db || !db.session) {
    return [];
  }
  const claim = context.config.claims.tenant;
  const findings: FindingInput[] = [];
  for (const { config, extras } of configuredHooks(context)) {
    if (config.hook !== "custom_access_token" || !extras) {
      continue;
    }
    for (const fn of extras.functions) {
      const target = `${signatureOf(fn)}:${claim}`;
      let claims: Readonly<Record<string, unknown>> | undefined;
      try {
        claims = await hookClaims(db, fn, userId);
      } catch {
        // BS405 reports a hook call that fails.
        continue;
      }
      if (claims === undefined) {
        continue;
      }
      const found = tenantClaimPaths(claim).some(
        (path) => claimAt(claims, path) !== undefined,
      );
      if (found) {
        continue;
      }
      findings.push({
        message: `${signatureOf(fn)} returns no \`${claim}\` claim for ${userId} (top level or app_metadata), and blocks.access.activeTenant is 'claim', so current_tenant_id() is null and the tenant() plugin rejects their requests. Write the claim in the hook, or set blocks.access.activeTenant to 'resolver' (with ServerOptions.tenant) or a profile column.`,
        target,
        object: { kind: "function", schema: fn.schema, name: fn.name },
      });
    }
  }
  return findings;
}

/** Where a deprecated symbol is used: a call, a qualified name or a claim lookup. */
function deprecationPattern(entry: ModuleDeprecation): RegExp {
  const [first = "", second] = entry.symbol.split(".");
  const qualified =
    second === undefined ? ident(first) : `${ident(first)}\\.${ident(second)}`;
  switch (entry.kind) {
    case "function":
      return new RegExp(`${qualified}\\s*\\(`, "i");
    case "table":
    case "column":
      return new RegExp(`(?<![\\w."])${qualified}(?![\\w"])`, "i");
    case "claim": {
      const name = escapeRegExp(entry.symbol);
      return new RegExp(
        `->>?\\s*'${name}'|#>>?\\s*'\\{[^}]*\\b${name}\\b[^}]*\\}'`,
        "i",
      );
    }
    default: {
      const never: never = entry.kind;
      throw new TypeError(`Unknown deprecation kind ${String(never)}`);
    }
  }
}

const bareWord = (name: string): RegExp =>
  new RegExp(`(?<![\\w"])${ident(name)}(?![\\w"])`, "i");

/**
 * The line where `text` uses a deprecated symbol. A column also counts
 * unqualified (`m.org_id`) in a statement that names its table, or in a
 * policy on that table.
 */
function lineOfUse(
  entry: ModuleDeprecation,
  text: string,
  policyTable?: string,
): number | undefined {
  const direct = lineOf(text, deprecationPattern(entry));
  if (direct !== undefined || entry.kind !== "column") {
    return direct;
  }
  const [table = "", column = ""] = entry.symbol.split(".");
  let offset = 0;
  for (const statement of text.split(";")) {
    const named = policyTable === table || bareWord(table).test(statement);
    const at = statement.search(bareWord(column));
    if (named && at !== -1) {
      return text.slice(0, offset + at).split("\n").length;
    }
    offset += statement.length + 1;
  }
  return undefined;
}

/** SQL files and policies that still use a symbol a SQL module deprecated or removed. */
function deprecatedSymbols(context: DoctorContext): FindingInput[] {
  const configured = new Set<string>(Object.values(context.config.claims));
  const entries = moduleDeprecations().filter(
    (entry) =>
      context.config.blockNames.includes(entry.module) &&
      !(entry.kind === "claim" && configured.has(entry.symbol)) &&
      // Adopted and custom tables keep the app's names.
      !(
        (entry.kind === "table" || entry.kind === "column") &&
        (context.config.blocks[entry.module]?.mode ?? "managed") !== "managed"
      ),
  );
  if (entries.length === 0) {
    return [];
  }
  const files = (context.sqlFiles ?? []).filter(
    (file) =>
      !/(^|\/)supabase\/migrations\//.test(file.path) &&
      moduleFileVersion(file.text) === undefined,
  );
  const findings: FindingInput[] = [];
  for (const entry of entries) {
    const status =
      entry.removed === undefined
        ? `deprecated since ${entry.since}`
        : `removed in ${entry.removed}`;
    const advice = `the ${entry.module} module's ${entry.kind} ${entry.symbol}, ${status}. Use ${entry.use}.`;
    for (const file of files) {
      const line = lineOfUse(entry, file.text);
      if (line === undefined) {
        continue;
      }
      findings.push({
        message: `${file.path} uses ${advice}`,
        target: `${file.path}:${entry.symbol}`,
        location: { file: file.path, line },
      });
    }
    for (const table of catalogOf(context).tables) {
      for (const policy of table.policies) {
        const text = `${policy.using ?? ""}\n${policy.check ?? ""}`;
        if (lineOfUse(entry, text, table.name) === undefined) {
          continue;
        }
        findings.push({
          message: `Policy "${policy.name}" on ${qualified(table)} uses ${advice}`,
          target: `${qualified(table)}.${policy.name}:${entry.symbol}`,
          object: policyObject(table, policy),
        });
      }
    }
  }
  return findings;
}

/** Module triggers and the equivalent triggers they replace. */
const EQUIVALENT_TRIGGERS = [
  {
    trigger: "bs_updated_at",
    call: "track_updated_at",
    pattern: /updated_at|moddatetime|touch/i,
  },
  { trigger: "bs_audit", call: "audit", pattern: /audit/i },
] as const;

/** Tables where a module trigger and an older trigger do the same work. */
function duplicateTriggers(context: DoctorContext): FindingInput[] {
  return catalogOf(context).tables.flatMap((table) =>
    EQUIVALENT_TRIGGERS.flatMap(({ trigger, call, pattern }) => {
      if (!table.triggers.some((entry) => entry.name === trigger)) {
        return [];
      }
      return table.triggers
        .filter(
          (entry) =>
            entry.name !== trigger &&
            pattern.test(entry.function.split(".").at(-1) ?? ""),
        )
        .map((entry) => ({
          message: `${qualified(table)} has ${trigger} and ${entry.name} (${entry.function}), so both run on every write. Drop ${entry.name}, or run \`select better_supabase.${call}('${qualified(table)}', replace_trigger => true)\` in a migration.`,
          target: `${qualified(table)}.${entry.name}`,
          object: tableObject(table),
        }));
    }),
  );
}

/** `exempt` globs (`public.*_archive`): `*` matches any run of characters. */
const globs = (value: unknown): RegExp[] =>
  (Array.isArray(value) ? value : [])
    .filter((entry): entry is string => typeof entry === "string")
    .map(
      (glob) =>
        new RegExp(`^${glob.split("*").map(escapeRegExp).join(".*")}$`, "i"),
    );

/** The module schemas and the app tables SQL modules adopted, which the audit trigger skips. */
function moduleOwned(context: DoctorContext): {
  schemas: ReadonlySet<string>;
  tables: ReadonlySet<string>;
} {
  const schemas = new Set<string>(["better_supabase"]);
  const tables = new Set<string>();
  for (const module of Object.values(context.config.blocks)) {
    if (module?.schema !== undefined) {
      schemas.add(module.schema);
    }
    for (const table of Object.values(module?.tables ?? {})) {
      if (table === null) {
        continue;
      }
      tables.add(
        table.includes(".")
          ? table
          : `${module?.schema ?? "better_supabase"}.${table}`,
      );
    }
  }
  return { schemas, tables };
}

/** Tables in `config.schemas` without the `bs_audit` trigger, when `audit` is in `blocks`. */
function unauditedTables(context: DoctorContext): FindingInput[] {
  if (!context.config.blockNames.includes("audit")) {
    return [];
  }
  const exempt = globs(context.config.blocks["audit"]?.options?.["exempt"]);
  const owned = moduleOwned(context);
  return catalogOf(context)
    .tables.filter(
      (table) =>
        table.kind === "table" &&
        context.config.schemas.includes(table.schema) &&
        !owned.schemas.has(table.schema) &&
        !owned.tables.has(qualified(table)) &&
        !exempt.some((pattern) => pattern.test(qualified(table))) &&
        !table.triggers.some(
          (trigger) =>
            trigger.name === "bs_audit" ||
            trigger.function.split(".").at(-1) === "audit_row_change",
        ),
    )
    .map((table) => ({
      message: `${qualified(table)} has no audit trigger, so its inserts, updates and deletes are not in the audit log. Run \`select better_supabase.audit('${qualified(table)}')\` in a schema file, or list it in blocks.audit.options.exempt.`,
      target: qualified(table),
      object: tableObject(table),
    }));
}

/** RLS tables in `config.schemas` without a restrictive `session_active()` policy, when `sessions` is in `blocks`. */
function sessionlessTables(context: DoctorContext): FindingInput[] {
  if (!context.config.blockNames.includes("sessions")) {
    return [];
  }
  const exclude = globs(
    context.config.blocks["sessions"]?.options?.["exclude"],
  );
  const owned = moduleOwned(context);
  return catalogOf(context)
    .tables.filter(
      (table) =>
        table.kind === "table" &&
        table.rls &&
        context.config.schemas.includes(table.schema) &&
        !owned.schemas.has(table.schema) &&
        !owned.tables.has(qualified(table)) &&
        !exclude.some((pattern) => pattern.test(qualified(table))) &&
        !table.policies.some(
          (policy) =>
            !policy.permissive &&
            `${policy.using ?? ""} ${policy.check ?? ""}`.includes(
              "session_active()",
            ),
        ),
    )
    .map((table) => ({
      message: `${qualified(table)} has no restrictive session_active() policy, so a signed-out or revoked session keeps its access until the token expires. Set blocks.sessions.options.policies to true and run \`better-supabase sql sync\`, add the policy by hand, or list the table in blocks.sessions.options.exclude.`,
      target: qualified(table),
      object: tableObject(table),
    }));
}

/** `better_supabase` and every `blocks.*.schema` that `[api] schemas` serves through the Data API. */
function exposedModuleSchemas(context: DoctorContext): FindingInput[] {
  if (context.config.blockNames.length === 0) {
    return [];
  }
  const moduleSchemas = new Set<string>(["better_supabase"]);
  for (const module of Object.values(context.config.blocks)) {
    if (module?.schema !== undefined) {
      moduleSchemas.add(module.schema);
    }
  }
  return exposedSchemas(context)
    .filter((schema) => moduleSchemas.has(schema))
    .map((schema) => ({
      message: `The Data API serves the module schema ${schema}, so its tables and internal helpers are reachable over REST and RPC. Remove it from [api] schemas in supabase/config.toml (and the dashboard's exposed schemas), set blocks.<module>.api to an exposed schema such as "api" so \`sql add\` writes security invoker entry points there, and call them with rpcTransport(supabase, { schema: "api" }).`,
      target: schema,
    }));
}

function migrationOptions(context: DoctorContext): FindingInput[] {
  const module = new Set(context.config.blockNames);
  return migrationOptionUses(context.config.blocks)
    .filter((use) => module.has(use.module))
    .map((use) => ({
      message: `${use.message} It exists to adopt an existing schema; remove it once your data matches the managed default.`,
      target: `blocks.${use.module}.options.${use.option}`,
    }));
}

/** A roles table shared by tenant and platform roles without `where` on both sides. */
function sharedRoleTables(context: DoctorContext): FindingInput[] {
  if (context.config.blockNames.length === 0) {
    return [];
  }
  const access = accessModule(context);
  if (access.kind !== "provider") {
    return [];
  }
  let problems: ReturnType<typeof sharedRolesProblems>;
  try {
    problems = sharedRolesProblems(
      context.config.blockNames,
      moduleLayout(
        context.config,
        context.config.sql.testsDir,
        [],
        entitlementsModule(context),
        access.access,
        permissionCatalogKeys(context),
      ),
    );
  } catch {
    return [];
  }
  return problems.map(({ setting, message }) => ({
    message: `${message} Without it, ${setting.startsWith("blocks.tenant.") ? "an organization invitation, accept or role change can resolve a platform role" : "a platform invitation can resolve a tenant role"}.`,
    target: setting,
  }));
}

export const MODULE_RULES: readonly Rule[] = [
  {
    code: "BS307",
    severity: "error",
    title: "Custom SQL module without its contract",
    description:
      "A module in `blocks` uses `mode: 'custom'`, so the app writes its contract functions. One is missing or has another signature, and the modules and TypeScript APIs that call it fail at run time.",
    check: missingContracts,
  },
  {
    code: "BS308",
    severity: "warning",
    title: "Tenant claim the hook does not write",
    description:
      "With the `tenant` module and `blocks.access.activeTenant: 'claim'`, `current_tenant_id()` and the `tenant()` plugin read the tenant from the `claims.tenant` claim, at the top level or in `app_metadata`. With `--as <user id>` doctor calls the custom access token hook for that user and warns when the claims it returns have neither. The default source, `'resolver'`, takes the tenant from the request instead.",
    check: missingTenantClaim,
  },
  {
    code: "BS309",
    severity: "warning",
    title: "Deprecated SQL module symbol",
    description:
      "A schema file or policy uses a function, table, column or claim that a SQL module deprecated or removed. Deprecated symbols keep a wrapper for at least one minor release; removed ones fail at run time.",
    check: deprecatedSymbols,
  },
  {
    code: "BS310",
    severity: "warning",
    title: "Duplicate module trigger",
    description:
      "A table has a module trigger (`bs_updated_at`, `bs_audit`) and another trigger that does the same work, so both run on every write.",
    check: duplicateTriggers,
  },
  {
    code: "BS313",
    severity: "warning",
    title: "Rate limits not wired to PostgREST",
    description:
      "The `rate-limit` module is in `blocks`, but on the live database `pgrst.db_pre_request` for the `authenticator` role is unset or names a function that doesn't call `better_supabase.check_request()`, so Data API requests are never counted.",
    check: rateLimitHook,
  },
  {
    code: "BS312",
    severity: "error",
    title: "Module schema exposed through the Data API",
    description:
      "`[api] schemas` in `config.toml` lists `better_supabase` or a `blocks.*.schema`. The module schemas hold internal tables and helpers that are granted to `authenticated` for policies, so exposing them makes those callable over REST and RPC.",
    check: exposedModuleSchemas,
  },
  {
    code: "BS314",
    severity: "warning",
    title: "Migration-only module option",
    description:
      "A module in adopt mode sets an option that only exists to match an existing schema: plain invitation tokens, webhook secrets or credentials in a column, non-text webhook ids, a custom outbox source, or audit values mapped to an adopted log's. Remove it once the data matches the managed default.",
    check: migrationOptions,
  },
  {
    code: "BS315",
    severity: "warning",
    title: "Table without an audit trigger",
    description:
      "The `audit` module is in `blocks`, and a table in `schemas` has no `bs_audit` trigger (or another trigger that calls `audit_row_change()`), so its changes are not in the audit log. The module's own schemas and the tables SQL modules adopt are skipped; `blocks.audit.options.exempt` lists more, as `schema.table` globs such as `public.*_archive`.",
    check: unauditedTables,
  },
  {
    code: "BS319",
    severity: "error",
    title: "SQL alters a reserved role",
    description:
      "A schema file, SQL module or migration alters, drops or changes the memberships of a role supautils reserves on Supabase (`supabase_admin`, `supabase_auth_admin`, `supabase_storage_admin`, `pgbouncer` and the other platform roles). The statement fails on a hosted project. `authenticator`, `authenticated`, `anon` and `service_role` accept `alter role ... set` (for example `pgrst.db_pre_request` or `statement_timeout`) and nothing else.",
    check: reservedRoles,
  },
  {
    code: "BS320",
    severity: "warning",
    title: "Table without the session policy",
    description:
      "The `sessions` module is in `blocks`, and a table with RLS in `schemas` has no restrictive policy that calls `better_supabase.session_active()`, so a token whose session was signed out, or whose user was banned or deleted, keeps reaching it until it expires. `blocks.sessions.options.policies` writes the policy on every table; `options.exclude` lists the tables to skip, as `schema.table` globs.",
    check: sessionlessTables,
  },
  {
    code: "BS322",
    severity: "warning",
    title: "Audit registration of a dropped table",
    description:
      "The `audit` module is in `blocks`, and `better_supabase.audited_tables` on the live database has a row whose table no longer exists. A table dropped before the module's `sql_drop` event trigger was installed keeps its row; the module's data migration deletes such rows.",
    check: danglingAuditRegistrations,
  },
  {
    code: "BS323",
    severity: "warning",
    title: "Module event trigger missing",
    description:
      "A module in `blocks` creates an event trigger (`bs_audit_forget_dropped` for `audit`, `bs_ensure_rls` for `ensure-rls`) that the live database lacks, or, without a database, that no migration creates. Event triggers belong to no schema, so a schema diff limited to some schemas leaves them out; the module's data migration creates them.",
    check: missingEventTriggers,
  },
  {
    code: "BS324",
    severity: "error",
    title: "Shared roles table without a role condition",
    description:
      "Under the `provider` model, the tenant module's `roleThrough` and the invitations module's `platformRoles.through` name the same roles table, and one of them has no `where` condition on `{row}`. That side then resolves a role id or key of the other kind: an organization invitation, accept or `update_member_role` can grant a platform role, or a platform invitation a tenant role. `sql sync` refuses the config; set `where` on both, such as `{row}.scope = 'organization'` and `{row}.scope = 'system'`.",
    check: sharedRoleTables,
  },
  {
    code: "BS325",
    severity: "warning",
    title: "Audit log readable only as the service role",
    description:
      "The `audit` module defaults `eventRoles` to `service_role` and `readPolicy` to false, so `audit.list()` under a user session is 403. Set `options.readPolicy: true` and include `authenticated` in `options.eventRoles` when the app lists the log as the signed-in user.",
    check: auditUserSession,
  },
  {
    code: "BS326",
    severity: "warning",
    title: "Admin Auth call without a secret key in env files",
    description:
      "`deleteAccount` and `bs.admin()` need `SUPABASE_SECRET_KEY`. The env files doctor reads do not set it, so those calls fail at run time.",
    check: missingSecretKey,
  },
  {
    code: "BS327",
    severity: "warning",
    title: "aal2 required without MFA enabled",
    description:
      "The app calls `requireAal('aal2')` (or otherwise requires aal2), but `[auth.mfa.totp]` in `config.toml` does not enable enroll and verify, so no user can satisfy the check.",
    check: aal2WithoutMfa,
  },
  {
    code: "BS330",
    severity: "error",
    title: "Adopted table without a mapped column",
    description:
      "A module in adopt mode maps a table or column that the live database lacks, so its functions fail when they run. The check reads every column the module's SQL names (`blocks.<name>.tables` and `columns`, with the defaults for unmapped ones); columns mapped to `null` are skipped.",
    check: missingAdoptedColumns,
  },
  {
    code: "BS331",
    severity: "error",
    title: "Subject registry names a missing table or column",
    description:
      "An entry in `config.subjects` names a table, or a column of it (`id`, `tenant`, `title`, `deletedAt`, the `url` placeholders, `rank` and `search`), that the snapshot lacks. `subject_title`, `subject_url`, `can_subject` and every module that falls back to the registry then fail when they run.",
    check: missingSubjectColumns,
  },
  {
    code: "BS332",
    severity: "warning",
    title: "Subject table without RLS",
    description:
      "A table in `config.subjects` has row level security disabled. `can_subject` treats a row the caller can read as visible, so without RLS every signed-in user passes the visibility half of the check for every row.",
    check: subjectsWithoutRls,
  },
  {
    code: "BS335",
    severity: "warning",
    title: "Audit log not partitioned",
    description:
      "`blocks.audit.options.partitioned` is on, but `better_supabase.audit_events` was created before it: its primary key is `id` alone, so the table isn't partitioned by month and `purge_audit_log` deletes row by row. Postgres can't convert a table in place. Create a partitioned table, copy the entries over and swap the names in a maintenance window, or turn the option off.",
    check: unpartitionedAuditLog,
  },
];

function unpartitionedAuditLog(context: DoctorContext): FindingInput[] {
  if (!context.config.blockNames.includes("audit")) {
    return [];
  }
  if (context.config.blocks["audit"]?.options?.["partitioned"] !== true) {
    return [];
  }
  const table = catalogOf(context).tables.find(
    (candidate) =>
      candidate.schema === "better_supabase" &&
      candidate.name === "audit_events",
  );
  if (table?.primaryKey.length !== 1) {
    return [];
  }
  return [
    {
      message:
        "better_supabase.audit_events isn't partitioned, so options.partitioned has no effect on it. Postgres can't convert it in place: copy the entries into a partitioned table in a maintenance window, or turn the option off.",
      target: "better_supabase.audit_events",
    },
  ];
}

function subjectTables(context: DoctorContext) {
  const catalog = catalogOf(context);
  return Object.entries(context.config.subjects).flatMap(([type, entry]) => {
    const [schema, name] = entry.table.includes(".")
      ? entry.table.split(".", 2)
      : ["public", entry.table];
    if (schema === undefined || name === undefined) {
      return [];
    }
    if (!context.snapshot.schemas.includes(schema)) {
      return [];
    }
    const table = catalog.tables.find(
      (candidate) => candidate.schema === schema && candidate.name === name,
    );
    return [{ type, entry, schema, name, table }];
  });
}

function missingSubjectColumns(context: DoctorContext): FindingInput[] {
  return subjectTables(context).flatMap(
    ({ type, entry, schema, name, table }): FindingInput[] => {
      const target = `${schema}.${name}`;
      if (!table) {
        return [
          {
            message: `subjects.${type} names ${target}, which the database does not have. Create the table, or point subjects.${type}.table at the existing one.`,
            target,
          },
        ];
      }
      const present = new Set(table.columns.map((column) => column.name));
      return subjectColumns(entry)
        .filter(([, column]) => !present.has(column))
        .map(([path, column]) => ({
          message: `subjects.${type}.${path} names ${target}.${column}, but the table has no such column. Map it to the column that holds the value, or add the column.`,
          target: `${target}.${column}`,
          object: tableObject(table),
        }));
    },
  );
}

function subjectsWithoutRls(context: DoctorContext): FindingInput[] {
  return subjectTables(context).flatMap(({ type, table }): FindingInput[] =>
    table?.kind === "table" && !table.rls
      ? [
          {
            message: `subjects.${type} is ${table.schema}.${table.name}, which has row level security disabled, so can_subject treats every row as visible. Enable RLS and add the policies that scope it.`,
            target: `${table.schema}.${table.name}`,
            object: tableObject(table),
          },
        ]
      : [],
  );
}

function auditUserSession(context: DoctorContext): FindingInput[] {
  if (!context.config.blockNames.includes("audit")) {
    return [];
  }
  const options = context.config.blocks["audit"]?.options ?? {};
  const roles = Array.isArray(options["eventRoles"])
    ? options["eventRoles"].filter(
        (role): role is string => typeof role === "string",
      )
    : ["service_role"];
  const readPolicy = options["readPolicy"] === true;
  if (readPolicy && roles.includes("authenticated")) {
    return [];
  }
  const calls = context.sources.some((file) =>
    /\baudit\.(list|listAll)\s*\(/.test(file.text),
  );
  if (!calls) {
    return [];
  }
  return [
    {
      message:
        "blocks.audit leaves the log readable only as the service role (`eventRoles` defaults to service_role, `readPolicy` defaults to false), but the app calls audit.list() or audit.listAll() as a user. Set options.readPolicy to true and include authenticated in options.eventRoles.",
      target: "blocks.audit",
    },
  ];
}

function missingSecretKey(context: DoctorContext): FindingInput[] {
  const usesAdmin = context.sources.some((file) =>
    /\bdeleteAccount\b|\.admin\s*\(|supabaseAdmin\b/.test(file.text),
  );
  if (!usesAdmin) {
    return [];
  }
  const hasKey = context.envFiles.some((file) =>
    /^\s*(?:SUPABASE_SECRET_KEY|SUPABASE_SERVICE_ROLE_KEY)\s*=/m.test(
      file.text,
    ),
  );
  if (hasKey) {
    return [];
  }
  return [
    {
      message:
        "The app calls deleteAccount or bs.admin(), which need SUPABASE_SECRET_KEY, but no env file doctor reads sets it. Add it to .env.local (and the hosted environments), listed without a value in .env.example.",
      target: "SUPABASE_SECRET_KEY",
    },
  ];
}

function aal2WithoutMfa(context: DoctorContext): FindingInput[] {
  const toml = context.configToml;
  if (!toml) {
    return [];
  }
  const requiresAal2 = context.sources.some((file) =>
    /requireAal\s*\(\s*['"]aal2['"]/.test(file.text),
  );
  if (!requiresAal2) {
    return [];
  }
  const enroll = tomlGet(toml.document, [
    "auth",
    "mfa",
    "totp",
    "enroll_enabled",
  ]);
  const verify = tomlGet(toml.document, [
    "auth",
    "mfa",
    "totp",
    "verify_enabled",
  ]);
  if (enroll === true && verify === true) {
    return [];
  }
  return [
    {
      message:
        "The app requires aal2, but [auth.mfa.totp] in config.toml does not set enroll_enabled and verify_enabled to true, so no user can satisfy the check.",
      target: toml.path,
      location: {
        file: toml.path,
        line: lineOf(toml.text, /^\[auth\.mfa\.totp\]/) ?? 1,
      },
    },
  ];
}
