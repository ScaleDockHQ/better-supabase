import type { BlockSqlContext } from "./context.ts";
import type { Policy } from "./policy.ts";

import { sqlString } from "../core/template.ts";
import { withoutComments } from "./audit-registrations.ts";
import {
  policy as buildPolicy,
  readGrants,
  readPolicies,
  renderPolicy,
} from "./policy.ts";

/**
 * The restrictive policy that keeps each organization's rows apart (ADR 0099).
 * Postgres combines permissive policies with `or`, so any permissive policy the
 * app adds would widen a block's; a restrictive one is combined with `and`, so
 * no permissive policy reaches past it.
 */
export const TENANT_SCOPE_POLICY = "bsb_tenant_scope";

export interface TenantScopeTarget {
  /** The table, qualified and quoted as the module writes it. */
  readonly target: string;
  /** The tenant column, quoted. */
  readonly column: string;
  /** The set-returning call of the caller's organizations. */
  readonly members: string;
  /**
   * The `using` expressions of the block's own permissive policies on the
   * table, which may reach rows outside the caller's organizations (guests,
   * platform staff, invitees, a user's own rows).
   */
  readonly using?: readonly string[];
  /** The `with check` expressions of those policies. */
  readonly check?: readonly string[];
}

function clause(base: string, extra: readonly string[]): string {
  const rest = [...new Set(extra.map((entry) => entry.trim()))].filter(
    (entry) => entry !== "" && entry !== base,
  );

  return rest.length === 0
    ? base
    : `\n    ${[base, ...rest.map((entry) => `(${entry})`)].join("\n    or ")}\n  `;
}

/** `drop policy` and `create policy` for the table's tenant scope. */
export function tenantScopePolicy(table: TenantScopeTarget): string {
  const base = `${table.column} in (select ${table.members})`;

  return renderPolicy(
    buildPolicy({
      table: table.target,
      name: TENANT_SCOPE_POLICY,
      permissive: false,
      roles: ["authenticated"],
      using: clause(base, table.using ?? []),
      check: clause(base, table.check ?? []),
    }),
    { drop: true, target: table.target },
  );
}

/** `schema.table` without quotes or spacing, for comparing table names. */
function tableKey(name: string): string {
  return name.replaceAll(/\s+/g, "").replaceAll('"', "").toLowerCase();
}

/** The tables the SQL grants a privilege on to `authenticated` or `public`. */
function grantedTables(sql: string): ReadonlySet<string> {
  return new Set(
    readGrants(sql)
      .filter((grant) =>
        grant.roles.some(
          (role) => role === "authenticated" || role === "public",
        ),
      )
      .map((grant) => grant.table),
  );
}

const reachesAuthenticated = (entry: Policy): boolean =>
  entry.roles.some((role) => role === "authenticated" || role === "public");

/**
 * The expressions a restrictive tenant scope must let through so the block's
 * own permissive policies keep working: `using` of the policies that read,
 * update or delete, and `with check` of those that insert or update (an update
 * without one checks its `using`).
 */
function grantedBy(policies: readonly Policy[]): {
  readonly using: readonly string[];
  readonly check: readonly string[];
} {
  const using: string[] = [];
  const check: string[] = [];

  for (const policy of policies) {
    if (policy.command !== "insert" && policy.using !== null) {
      using.push(policy.using);
    }

    if (
      policy.command === "insert" ||
      policy.command === "update" ||
      policy.command === "all"
    ) {
      const checked = policy.check ?? policy.using;

      if (checked !== null) {
        check.push(checked);
      }
    }
  }

  return { using, check };
}

/**
 * The memberships module's `member_organization_ids` as an empty set when it
 * doesn't exist yet, so a module that installs before memberships can create
 * its tenant scope policies. Memberships replaces it with `create or replace`,
 * which needs the same name, arguments and return type.
 */
function membersStub(ctx: BlockSqlContext): string {
  const fn = ctx.scope.members().replace(/\(\)$/, "");
  const id = ctx.idType;

  return `-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure(${sqlString(`${fn}(text[])`)}) is null then
    create function ${fn}(roles text[] default null)
    returns setof ${id}
    language sql
    stable
    set search_path = ''
    as $members$ select null::${id} where false $members$;
  end if;
end $$;
`;
}

/**
 * `sql` with a restrictive tenant scope policy on each tenant-scoped table the
 * module grants to `authenticated` or writes a permissive policy for it on. A
 * table is tenant-scoped when its spec names a `lifecycle.tenant` column. Each
 * policy lets through the caller's organizations and whatever the block's own
 * permissive policies on the table grant, so it narrows only what other
 * permissive policies, such as the app's, would add. Service-only tables get
 * none: without a grant to `authenticated`, no policy reaches them.
 */
export function applyTenantScope(sql: string, ctx: BlockSqlContext): string {
  if (ctx.scope.kind !== "tenant") {
    return sql;
  }

  const source = withoutComments(sql);
  const policies = readPolicies(source).map((read) => read.policy);
  const granted = grantedTables(source);
  const statements: string[] = [];
  const targets: string[] = [];

  for (const [logical, spec] of Object.entries(ctx.names.tables)) {
    const tenant = spec.lifecycle?.tenant;

    if (
      tenant === undefined ||
      ctx.appViews.includes(logical) ||
      !ctx.hasTable(logical) ||
      !ctx.has(logical, tenant)
    ) {
      continue;
    }

    const name = ctx.tableName(logical);
    const key = tableKey(`${name.schema}.${name.name}`);

    const own = policies.filter(
      (policy) =>
        policy.table === key &&
        policy.permissive &&
        reachesAuthenticated(policy),
    );

    if (source.includes(ctx.table(logical))) {
      targets.push(ctx.table(logical));
    }

    if (own.length === 0 && !granted.has(key)) {
      continue;
    }

    statements.push(
      tenantScopePolicy({
        target: ctx.table(logical),
        column: ctx.col(logical, tenant),
        members: ctx.scope.members(),
        ...grantedBy(own),
      }),
    );
  }

  if (targets.length === 0) {
    return sql;
  }

  const scope =
    statements.length === 0
      ? ""
      : `

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
${ctx.module === "memberships" ? "" : membersStub(ctx)}${statements.join("\n")}`;

  return `-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
${targets
  .map(
    (target) => `  begin
    drop policy if exists ${TENANT_SCOPE_POLICY} on ${target};
  exception when undefined_table or invalid_schema_name then null;
  end;`,
  )
  .join("\n")}
end $$;

${sql.trimEnd()}${scope}
`;
}
