import type { LiteRuntime } from "../../lite/runtime.ts";
import type { Issue } from "../issue.ts";
import type { PresetMigrationFile } from "../types.ts";
import type { SkippedBlock } from "./apply.ts";

import { LITE_INSTALL, loadLite } from "../../lite/runtime.ts";
import { applyFiles } from "./apply.ts";
import { SUPABASE_PRELUDE } from "./prelude.ts";

/** What a policy does, as the catalog states it (ADR 0105). */
export interface CatalogPolicy {
  readonly name: string;
  readonly command: "select" | "insert" | "update" | "delete" | "all";
  readonly permissive: boolean;
  /** The roles it applies to; `public` means every role. */
  readonly roles: readonly string[];
  readonly using: string | null;
  readonly check: string | null;
}

export interface CatalogGrant {
  /** The role, or `public` for a grant to `PUBLIC`. */
  readonly grantee: string;
  readonly privilege: string;
}

export interface CatalogTable {
  readonly schema: string;
  readonly name: string;
  readonly rls: boolean;
  readonly force: boolean;
  readonly policies: readonly CatalogPolicy[];
  readonly grants: readonly CatalogGrant[];
}

export interface CatalogFunction {
  readonly schema: string;
  readonly name: string;
  readonly definer: boolean;
  /** Whether the function sets `search_path` in its own configuration. */
  readonly searchPath: boolean;
}

/** The security facts `verifyCatalog` checks. */
export interface SecurityCatalog {
  readonly tables: readonly CatalogTable[];
  readonly functions: readonly CatalogFunction[];
}

export interface VerifyOptions {
  /** `schema.table` names that must have row level security forced. */
  readonly force?: readonly string[];
  /**
   * `schema.table` names that must carry a restrictive tenant scope policy
   * (`bsb_tenant_scope*`).
   */
  readonly tenantScoped?: readonly string[];
}

/** A role the access matrix answers for. */
export type MatrixRole = "anon" | "authenticated";

export type MatrixCommand = "select" | "insert" | "update" | "delete";

export const MATRIX_COMMANDS: readonly MatrixCommand[] = [
  "select",
  "insert",
  "update",
  "delete",
];

/**
 * How far a role reaches with one command on one table: `denied` without the
 * table privilege or without a permissive policy, `open` when a permissive
 * policy admits every row, and `policy` when a policy decides per row.
 */
export type Reach = "denied" | "open" | "policy";

export interface MatrixCell {
  readonly table: string;
  readonly role: MatrixRole;
  readonly command: MatrixCommand;
  readonly reach: Reach;
}

/**
 * One query that returns the security facts as JSON: row level security and
 * grants of each table, its policies, and the functions' `search_path`.
 */
export function verifyQuery(schemas: readonly string[] = ["public"]): string {
  const list = schemas
    .map((name) => `'${name.replaceAll("'", "''")}'`)
    .join(", ");

  return `select json_build_object(
  'tables', (
    select coalesce(json_agg(t order by t.schema, t.name), '[]'::json) from (
      select n.nspname as schema, c.relname as name,
        c.relrowsecurity as rls, c.relforcerowsecurity as force,
        (select coalesce(json_agg(json_build_object(
            'name', p.polname,
            'command', case p.polcmd when 'r' then 'select' when 'a' then 'insert'
              when 'w' then 'update' when 'd' then 'delete' else 'all' end,
            'permissive', p.polpermissive,
            'roles', (select coalesce(json_agg(case when u.oid = 0 then 'public' else r.rolname end), '[]'::json)
              from unnest(p.polroles) as u(oid)
              left join pg_roles r on r.oid = u.oid),
            'using', pg_get_expr(p.polqual, p.polrelid),
            'check', pg_get_expr(p.polwithcheck, p.polrelid)
          )), '[]'::json)
          from pg_policy p where p.polrelid = c.oid) as policies,
        (select coalesce(json_agg(json_build_object(
            'grantee', case when a.grantee = 0 then 'public' else (select rolname from pg_roles where oid = a.grantee) end,
            'privilege', a.privilege_type
          )), '[]'::json)
          from aclexplode(c.relacl) a) as grants
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname in (${list}) and c.relkind in ('r', 'p')
    ) t
  ),
  'functions', (
    select coalesce(json_agg(json_build_object(
      'schema', n.nspname, 'name', p.proname, 'definer', p.prosecdef,
      'searchPath', coalesce(exists (select 1 from unnest(p.proconfig) as c(setting) where c.setting like 'search_path=%'), false)
    ) order by n.nspname, p.proname), '[]'::json)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in (${list}) and p.prokind in ('f', 'p')
  )
) as catalog`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function str(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function records(value: unknown): readonly Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter((item) => isRecord(item)) : [];
}

function commandOf(value: unknown): CatalogPolicy["command"] {
  switch (value) {
    case "select":
    case "insert":
    case "update":
    case "delete": {
      return value;
    }

    default: {
      return "all";
    }
  }
}

function readPolicy(row: Record<string, unknown>): CatalogPolicy {
  return {
    name: str(row["name"]),
    command: commandOf(row["command"]),
    permissive: row["permissive"] !== false,
    roles: Array.isArray(row["roles"])
      ? row["roles"].filter((item): item is string => typeof item === "string")
      : [],
    using: typeof row["using"] === "string" ? row["using"] : null,
    check: typeof row["check"] === "string" ? row["check"] : null,
  };
}

/** Reads the row `verifyQuery` returns; the JSON may arrive as text. */
export function readSecurityCatalog(rows: readonly unknown[]): SecurityCatalog {
  const [row] = rows;
  const cell = isRecord(row) ? row["catalog"] : undefined;
  const parsed: unknown = typeof cell === "string" ? JSON.parse(cell) : cell;
  const catalog = isRecord(parsed) ? parsed : {};

  return {
    tables: records(catalog["tables"]).map((table) => ({
      schema: str(table["schema"]),
      name: str(table["name"]),
      rls: table["rls"] === true,
      force: table["force"] === true,
      policies: records(table["policies"]).map((each) => readPolicy(each)),
      grants: records(table["grants"]).map((grant) => ({
        grantee: str(grant["grantee"]),
        privilege: str(grant["privilege"]),
      })),
    })),
    functions: records(catalog["functions"]).map((fn) => ({
      schema: str(fn["schema"]),
      name: str(fn["name"]),
      definer: fn["definer"] === true,
      searchPath: fn["searchPath"] === true,
    })),
  };
}

const qualified = (table: CatalogTable): string =>
  `${table.schema}.${table.name}`;

/** An expression that admits every row: `true`, in any amount of parentheses. */
function isTrue(expression: string | null): boolean {
  if (expression === null) {
    return false;
  }

  let text = expression.replaceAll(/\s+/gu, "").toLowerCase();

  while (text.startsWith("(") && text.endsWith(")")) {
    text = text.slice(1, -1);
  }

  return text === "true";
}

const WRITES: ReadonlySet<string> = new Set([
  "INSERT",
  "UPDATE",
  "DELETE",
  "TRUNCATE",
]);

function appliesTo(policy: CatalogPolicy, role: MatrixRole): boolean {
  return policy.roles.includes(role) || policy.roles.includes("public");
}

function covers(policy: CatalogPolicy, command: MatrixCommand): boolean {
  return policy.command === "all" || policy.command === command;
}

function hasPrivilege(
  table: CatalogTable,
  role: MatrixRole,
  command: MatrixCommand,
): boolean {
  const wanted = command.toUpperCase();

  return table.grants.some(
    (grant) =>
      grant.privilege === wanted &&
      (grant.grantee === role || grant.grantee === "public"),
  );
}

function expressionOf(
  policy: CatalogPolicy,
  command: MatrixCommand,
): string | null {
  return command === "insert" ? policy.check : policy.using;
}

function reachOf(
  table: CatalogTable,
  role: MatrixRole,
  command: MatrixCommand,
): Reach {
  if (!hasPrivilege(table, role, command)) {
    return "denied";
  }

  if (!table.rls) {
    return "open";
  }

  const applicable = table.policies.filter(
    (policy) => appliesTo(policy, role) && covers(policy, command),
  );

  const permissive = applicable.filter((policy) => policy.permissive);

  if (permissive.length === 0) {
    return "denied";
  }

  const restrictive = applicable.filter((policy) => !policy.permissive);

  const everyRow =
    permissive.some((policy) => isTrue(expressionOf(policy, command))) &&
    restrictive.every((policy) => isTrue(expressionOf(policy, command)));

  return everyRow ? "open" : "policy";
}

/**
 * The role by command by table matrix: how far `anon` and `authenticated` reach
 * with each command on each table (ADR 0105). The service role bypasses row
 * level security, so it has no row.
 */
export function accessMatrix(catalog: SecurityCatalog): readonly MatrixCell[] {
  const roles: readonly MatrixRole[] = ["anon", "authenticated"];

  return catalog.tables.flatMap((table) =>
    roles.flatMap((role) =>
      MATRIX_COMMANDS.map((command) => ({
        table: qualified(table),
        role,
        command,
        reach: reachOf(table, role, command),
      })),
    ),
  );
}

function issue(
  code: Issue["code"],
  severity: Issue["severity"],
  table: string,
  message: string,
): Issue {
  return { code, severity, source: "verifier", path: "", table, message };
}

function tableIssues(table: CatalogTable, options: VerifyOptions): Issue[] {
  const name = qualified(table);
  const issues: Issue[] = [];

  const exposed = table.grants.some(
    (grant) =>
      grant.grantee === "anon" ||
      grant.grantee === "authenticated" ||
      grant.grantee === "public",
  );

  if (!table.rls && exposed) {
    issues.push(
      issue(
        "verify_rls_off",
        "error",
        name,
        `${name} has row level security off and is granted to a client role`,
      ),
    );
  }

  if (options.force?.includes(name) === true && !table.force) {
    issues.push(
      issue(
        "verify_force_off",
        "error",
        name,
        `${name} must force row level security so its owner is bound by the policies`,
      ),
    );
  }

  if (
    options.tenantScoped?.includes(name) === true &&
    !table.policies.some(
      (policy) =>
        !policy.permissive && policy.name.startsWith("bsb_tenant_scope"),
    )
  ) {
    issues.push(
      issue(
        "verify_scope_missing",
        "error",
        name,
        `${name} has no restrictive bsb_tenant_scope policy`,
      ),
    );
  }

  for (const policy of table.policies) {
    const open =
      policy.permissive &&
      (isTrue(policy.using) || isTrue(policy.check)) &&
      policy.command !== "select";

    if (open) {
      issues.push(
        issue(
          "verify_policy_true",
          "error",
          name,
          `${name}: policy ${policy.name} lets ${policy.roles.join(", ")} ${policy.command} every row`,
        ),
      );
    }
  }

  for (const grant of table.grants) {
    if (grant.grantee === "anon" && WRITES.has(grant.privilege)) {
      issues.push(
        issue(
          "verify_anon_write",
          "error",
          name,
          `${name}: anon holds ${grant.privilege}`,
        ),
      );
    }

    if (grant.grantee === "public") {
      issues.push(
        issue(
          "verify_public_grant",
          "warning",
          name,
          `${name}: PUBLIC holds ${grant.privilege}`,
        ),
      );
    }
  }

  return issues;
}

/**
 * Checks the facts a policy file can't show on its own: row level security on
 * every exposed table, no permissive write policy that is only `true`, no write
 * grant to `anon`, nothing granted to `PUBLIC`, `search_path` on every security
 * definer function, and, when asked, forced row level security and a
 * restrictive tenant scope. A permissive `select` policy of `true` for `anon`
 * is an error too. Findings are `Issue`s with `source: "verifier"`.
 */
export function verifyCatalog(
  catalog: SecurityCatalog,
  options: VerifyOptions = {},
): readonly Issue[] {
  const issues = catalog.tables.flatMap((table) => tableIssues(table, options));

  for (const cell of accessMatrix(catalog)) {
    if (cell.role === "anon" && cell.command === "select") {
      const table = catalog.tables.find(
        (each) => qualified(each) === cell.table,
      );

      const open =
        cell.reach === "open" &&
        table?.rls === true &&
        table.policies.some((policy) => policy.permissive);

      if (open) {
        issues.push(
          issue(
            "verify_anon_reads_all",
            "error",
            cell.table,
            `${cell.table}: anon reads every row`,
          ),
        );
      }
    }
  }

  for (const fn of catalog.functions) {
    if (fn.definer && !fn.searchPath) {
      issues.push(
        issue(
          "verify_definer_search_path",
          "error",
          `${fn.schema}.${fn.name}`,
          `${fn.schema}.${fn.name} is security definer without a search_path`,
        ),
      );
    }
  }

  return issues;
}

export interface VerifyDesignOptions extends VerifyOptions {
  /** A loaded `@supabase/lite`; loaded on demand when left out. */
  readonly runtime?: LiteRuntime;
  /** The schemas to read; `public` by default. */
  readonly schemas?: readonly string[];
}

export interface FilesVerification {
  /**
   * The files Postgres rejected (`source: "sql"`), then `verifyCatalog`'s
   * findings.
   */
  readonly issues: readonly Issue[];
  readonly matrix: readonly MatrixCell[];
  /** Modules left out because PGlite lacks an extension they need. */
  readonly skipped: readonly SkippedBlock[];
}

/**
 * Applies the files to an in-memory PGlite database, reads its catalog and
 * returns `verifyCatalog`'s findings with the matrix. A file Postgres rejects
 * is an issue, as in `validateDesign`, because its tables are missing from the
 * catalog. Throws when `@supabase/lite` isn't installed.
 */
export async function verifyFiles(
  files: readonly PresetMigrationFile[],
  options: VerifyDesignOptions = {},
): Promise<FilesVerification> {
  const runtime = options.runtime ?? (await loadLite());

  if (runtime === undefined) {
    throw new Error(LITE_INSTALL);
  }

  const connection = await runtime.createPgliteConnection();

  try {
    const { driver } = connection;

    await driver.exec(SUPABASE_PRELUDE);
    const applied = await applyFiles(driver, files);

    const { rows } = await driver.query(verifyQuery(options.schemas));
    const catalog = readSecurityCatalog(rows);

    return {
      issues: [...applied.issues, ...verifyCatalog(catalog, options)],
      matrix: accessMatrix(catalog),
      skipped: applied.skipped,
    };
  } finally {
    await connection.close();
  }
}
