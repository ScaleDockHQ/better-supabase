import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { tenantClaimPaths } from "../../config/index.ts";
import { DEFAULT_ACTIVE_TENANT } from "../../config/index.ts";
import {
  contractSignature,
  customContracts,
  type BlockDeprecation,
  blockDeprecations,
  blockFileVersion,
  blockLayout,
  migrationOptionUses,
} from "../../sql/index.ts";
import { configuredHooks, hookClaims, isRecord, signatureOf } from "./hooks.ts";
import { errorText, literal } from "./live.ts";
import {
  catalogOf,
  exposedSchemas,
  lineOf,
  policyObject,
  qualified,
  tableObject,
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
    context.config.sql.modules,
    blockLayout(context.config),
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

/** `rate-limit` in `sql.modules` without PostgREST's pre-request hook reaching `check_request()`. */
async function rateLimitHook(context: DoctorContext): Promise<FindingInput[]> {
  const db = context.database;
  if (
    !context.config.sql.modules.includes("rate-limit") ||
    !db ||
    "skipped" in db
  )
    return [];
  let rows: { hook: string | null; calls: boolean }[];
  try {
    rows = await db.query(PRE_REQUEST_HOOK);
  } catch {
    return [];
  }
  const [row] = rows;
  if (!row || row.hook === "better_supabase.check_request" || row.calls)
    return [];
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

/** Custom-mode modules whose contract functions the database or SQL files don't have. */
async function missingContracts(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const checks = contractChecks(context);
  if (checks.length === 0) return [];
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
        message: `Reading the custom block contract functions failed: ${errorText(cause)}`,
        target: "blocks",
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
  if (!context.config.sql.modules.includes("tenant")) return [];
  if (
    (context.config.blocks.access?.activeTenant ?? DEFAULT_ACTIVE_TENANT) !==
    "claim"
  ) {
    return [];
  }
  const userId = context.hookUser;
  const db = context.database;
  if (!userId || !db || "skipped" in db || !db.session) return [];
  const claim = context.config.claims.tenant;
  const findings: FindingInput[] = [];
  for (const { config, extras } of configuredHooks(context)) {
    if (config.hook !== "custom_access_token" || !extras) continue;
    for (const fn of extras.functions) {
      const target = `${signatureOf(fn)}:${claim}`;
      let claims: Readonly<Record<string, unknown>> | undefined;
      try {
        claims = await hookClaims(db, fn, userId);
      } catch {
        // BS405 reports a hook call that fails.
        continue;
      }
      if (claims === undefined) continue;
      const found = tenantClaimPaths(claim).some(
        (path) => claimAt(claims, path) !== undefined,
      );
      if (found) continue;
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
function deprecationPattern(entry: BlockDeprecation): RegExp {
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
  entry: BlockDeprecation,
  text: string,
  policyTable?: string,
): number | undefined {
  const direct = lineOf(text, deprecationPattern(entry));
  if (direct !== undefined || entry.kind !== "column") return direct;
  const [table = "", column = ""] = entry.symbol.split(".");
  let offset = 0;
  for (const statement of text.split(";")) {
    const named = policyTable === table || bareWord(table).test(statement);
    const at = statement.search(bareWord(column));
    if (named && at !== -1)
      return text.slice(0, offset + at).split("\n").length;
    offset += statement.length + 1;
  }
  return undefined;
}

/** SQL files and policies that still use a symbol a SQL module deprecated or removed. */
function deprecatedSymbols(context: DoctorContext): FindingInput[] {
  const configured = new Set<string>(Object.values(context.config.claims));
  const entries = blockDeprecations().filter(
    (entry) =>
      context.config.sql.modules.includes(entry.module) &&
      !(entry.kind === "claim" && configured.has(entry.symbol)) &&
      // Adopted and custom tables keep the app's names.
      !(
        (entry.kind === "table" || entry.kind === "column") &&
        (context.config.blocks[entry.module]?.mode ?? "managed") !== "managed"
      ),
  );
  if (entries.length === 0) return [];
  const files = (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.startsWith("supabase/migrations/") &&
      blockFileVersion(file.text) === undefined,
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
      if (line === undefined) continue;
      findings.push({
        message: `${file.path} uses ${advice}`,
        target: `${file.path}:${entry.symbol}`,
        location: { file: file.path, line },
      });
    }
    for (const table of catalogOf(context).tables) {
      for (const policy of table.policies) {
        const text = `${policy.using ?? ""}\n${policy.check ?? ""}`;
        if (lineOfUse(entry, text, table.name) === undefined) continue;
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

/** Block triggers and the equivalent triggers they replace. */
const EQUIVALENT_TRIGGERS = [
  {
    trigger: "bs_updated_at",
    call: "track_updated_at",
    pattern: /updated_at|moddatetime|touch/i,
  },
  { trigger: "bs_audit", call: "audit", pattern: /audit/i },
] as const;

/** Tables where a block trigger and an older trigger do the same work. */
function duplicateTriggers(context: DoctorContext): FindingInput[] {
  return catalogOf(context).tables.flatMap((table) =>
    EQUIVALENT_TRIGGERS.flatMap(({ trigger, call, pattern }) => {
      if (!table.triggers.some((entry) => entry.name === trigger)) return [];
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

/** The block schemas and the app tables SQL modules adopted, which the audit trigger skips. */
function blockOwned(context: DoctorContext): {
  schemas: ReadonlySet<string>;
  tables: ReadonlySet<string>;
} {
  const schemas = new Set<string>(["better_supabase"]);
  const tables = new Set<string>();
  for (const module of Object.values(context.config.blocks)) {
    if (module?.schema !== undefined) schemas.add(module.schema);
    for (const table of Object.values(module?.tables ?? {})) {
      if (table === null) continue;
      tables.add(
        table.includes(".")
          ? table
          : `${module?.schema ?? "better_supabase"}.${table}`,
      );
    }
  }
  return { schemas, tables };
}

/** Tables in `config.schemas` without the `bs_audit` trigger, when `audit` is in `sql.modules`. */
function unauditedTables(context: DoctorContext): FindingInput[] {
  if (!context.config.sql.modules.includes("audit")) return [];
  const exempt = globs(context.config.blocks["audit"]?.options?.["exempt"]);
  const owned = blockOwned(context);
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

/** `better_supabase` and every `blocks.*.schema` that `[api] schemas` serves through the Data API. */
function exposedBlockSchemas(context: DoctorContext): FindingInput[] {
  if (context.config.sql.modules.length === 0) return [];
  const blockSchemas = new Set<string>(["better_supabase"]);
  for (const module of Object.values(context.config.blocks)) {
    if (module?.schema !== undefined) blockSchemas.add(module.schema);
  }
  return exposedSchemas(context)
    .filter((schema) => blockSchemas.has(schema))
    .map((schema) => ({
      message: `The Data API serves the block schema ${schema}, so its tables and internal helpers are reachable over REST and RPC. Remove it from [api] schemas in supabase/config.toml (and the dashboard's exposed schemas), and call the block functions through a wrapper in an exposed schema.`,
      target: schema,
    }));
}

function migrationOptions(context: DoctorContext): FindingInput[] {
  const block = new Set(context.config.sql.modules);
  return migrationOptionUses(context.config.blocks)
    .filter((use) => block.has(use.module))
    .map((use) => ({
      message: `${use.message} It exists to adopt an existing schema; remove it once your data matches the managed default.`,
      target: `blocks.${use.module}.options.${use.option}`,
    }));
}

export const BLOCK_RULES: readonly Rule[] = [
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
    title: "Duplicate block trigger",
    description:
      "A table has a block trigger (`bs_updated_at`, `bs_audit`) and another trigger that does the same work, so both run on every write.",
    check: duplicateTriggers,
  },
  {
    code: "BS313",
    severity: "warning",
    title: "Rate limits not wired to PostgREST",
    description:
      "The `rate-limit` module is in `sql.modules`, but on the live database `pgrst.db_pre_request` for the `authenticator` role is unset or names a function that doesn't call `better_supabase.check_request()`, so Data API requests are never counted.",
    check: rateLimitHook,
  },
  {
    code: "BS312",
    severity: "error",
    title: "Block schema exposed through the Data API",
    description:
      "`[api] schemas` in `config.toml` lists `better_supabase` or a `blocks.*.schema`. The block schemas hold internal tables and helpers that are granted to `authenticated` for policies, so exposing them makes those callable over REST and RPC.",
    check: exposedBlockSchemas,
  },
  {
    code: "BS314",
    severity: "warning",
    title: "Migration-only block option",
    description:
      "A module in adopt mode sets an option that only exists to match an existing schema: plain invitation tokens, webhook secrets in a column, non-text webhook ids, or a custom outbox source. Remove it once the data matches the managed default.",
    check: migrationOptions,
  },
  {
    code: "BS315",
    severity: "warning",
    title: "Table without an audit trigger",
    description:
      "The `audit` module is in `sql.modules`, and a table in `schemas` has no `bs_audit` trigger (or another trigger that calls `audit_row_change()`), so its changes are not in the audit log. The module's own schemas and the tables SQL modules adopt are skipped; `blocks.audit.options.exempt` lists more, as `schema.table` globs such as `public.*_archive`.",
    check: unauditedTables,
  },
];
