import type { AuthorizationFunctions } from "../config/authorization.ts";
import type { AccessPolicySql } from "../schema/types.ts";

import { sqlString } from "./template.ts";

const SCOPE = /^[a-z][a-z0-9_]*$/;

/** Whether `name` can be a scope: it is put unquoted into templates. */
export const isScopeName = (name: string): boolean => SCOPE.test(name);

/** The placeholders each authorization template may use. */
export const TEMPLATE_PLACEHOLDERS: Readonly<
  Record<keyof AuthorizationFunctions, readonly string[]>
> = {
  idsWith: ["permission", "scope"],
  isPlatform: ["permission"],
  idsWithFor: ["user", "permission", "scope"],
  isPlatformFor: ["user", "permission"],
  memberIds: ["scope"],
  memberIdsFor: ["user", "scope"],
  canAssign: ["role", "tenant", "scope"],
  canAssignFor: ["user", "role", "tenant", "scope"],
  permissionsFor: ["user", "tenant", "scope"],
  canApprove: ["tool", "tenant", "scope"],
};

/** The Postgres types a scope's ids can have. */
export const SCOPE_ID_TYPES: readonly string[] = [
  "uuid",
  "text",
  "bigint",
  "integer",
];

/**
 * What is wrong with a provider's scopes: an unknown tenant scope or
 * parent, a parent cycle, an id type outside `SCOPE_ID_TYPES`, or a tenant
 * scope without one.
 */
export function scopeProblems(provider: {
  readonly scopes: readonly {
    readonly name: string;
    readonly idType?: string | undefined;
    readonly parent?: string | undefined;
  }[];
  readonly tenantScope: string;
}): string[] {
  const problems: string[] = [];
  const byName = new Map(provider.scopes.map((scope) => [scope.name, scope]));
  for (const scope of provider.scopes) {
    if (scope.idType !== undefined && !SCOPE_ID_TYPES.includes(scope.idType)) {
      problems.push(
        `scope "${scope.name}" has idType "${scope.idType}"; use ${SCOPE_ID_TYPES.join(", ")}`,
      );
    }
    if (scope.parent !== undefined && !byName.has(scope.parent)) {
      problems.push(
        `scope "${scope.name}" has parent "${scope.parent}", which is not a scope`,
      );
    }
  }
  const cyclic = new Set<string>();
  for (const scope of provider.scopes) {
    const seen = new Set<string>();
    let current: string | undefined = scope.name;
    while (current !== undefined && !seen.has(current)) {
      seen.add(current);
      current = byName.get(current)?.parent;
    }
    if (current !== undefined && !cyclic.has(current)) {
      for (const name of seen) cyclic.add(name);
      problems.push(`scope "${current}" is its own ancestor (a parent cycle)`);
    }
  }
  const tenant = byName.get(provider.tenantScope);
  if (tenant === undefined) {
    problems.push(`tenantScope "${provider.tenantScope}" is not a scope`);
  } else if (tenant.idType === undefined) {
    problems.push(`tenant scope "${tenant.name}" has no idType`);
  }
  return problems;
}

const CALL_KEYWORDS = new Set([
  "all",
  "and",
  "any",
  "array",
  "as",
  "cast",
  "coalesce",
  "exists",
  "from",
  "greatest",
  "in",
  "is",
  "least",
  "not",
  "nullif",
  "on",
  "or",
  "row",
  "select",
  "some",
  "values",
  "when",
  "where",
]);

/**
 * What makes a template unsafe to put into generated SQL: a `$$`, `;` or
 * `--` (outside string literals), or a function call without a schema.
 */
export function templateProblems(template: string): string[] {
  const code = template
    .replaceAll(/'(?:[^']|'')*'/g, "''")
    .replaceAll(/\{(\w+)\}/g, "$1");
  const problems: string[] = [];
  for (const token of ["$$", ";", "--"]) {
    if (code.includes(token)) problems.push(`contains "${token}"`);
  }
  for (const match of code.matchAll(/(?<![\w$.":])"?([a-z_][\w$]*)"?\s*\(/gi)) {
    const name = match[1]!;
    if (CALL_KEYWORDS.has(name.toLowerCase())) continue;
    problems.push(`calls ${name}() without a schema`);
  }
  return problems;
}

/** The `{name}` placeholders in a template. */
export const templatePlaceholders = (template: string): string[] => [
  ...new Set([...template.matchAll(/\{(\w+)\}/g)].map((match) => match[1]!)),
];

/**
 * Fills a template's `{name}` placeholders. `where` names the setting in
 * the error for a placeholder `values` doesn't have.
 */
export function fillTemplate(
  where: string,
  template: string,
  values: Readonly<Record<string, string>>,
): string {
  return template.replaceAll(/\{(\w+)\}/g, (match, name: string) => {
    const value = values[name];
    if (value === undefined) {
      throw new TypeError(
        `${where}: ${match} is not available here. Use ${Object.keys(values)
          .map((key) => `{${key}}`)
          .join(", ")}`,
      );
    }
    return value;
  });
}

/** The `schema.name` of every schema-qualified function a template calls, with `{scope}` filled. */
export function templateFunctions(template: string, scope?: string): string[] {
  const filled =
    scope === undefined ? template : template.replaceAll("{scope}", scope);
  return [
    ...new Set(
      [
        ...filled.matchAll(
          /(?<![\w$."])"?([a-z_][\w$]*)"?\s*\.\s*"?([a-z_][\w${}]*)"?\s*\(/gi,
        ),
      ].map((match) => `${match[1]!}.${match[2]!}`),
    ),
  ];
}

/** What a bucket or topic access policy decides with. */
export interface AccessTarget {
  /** `tenant` (default), `platform`, or with `sql` any scope its templates take. */
  readonly scope?: string;
  /** `"provider"` is replaced with `authorization.functions` by `gen`. */
  readonly sql?: AccessPolicySql | "provider";
}

/**
 * `target` with `sql: "provider"` replaced by the provider's `idsWith` and
 * `isPlatform`. `where` names the policy in the error when there is no
 * provider.
 */
export function resolveProviderSql<T extends AccessTarget>(
  where: string,
  target: T,
  functions: AuthorizationFunctions | undefined,
): T {
  if (target.sql !== "provider") return target;
  if (functions === undefined) {
    throw new TypeError(
      `${where}: sql "provider" needs \`authorization\` in better-supabase.config.ts`,
    );
  }
  return {
    ...target,
    sql: { idsWith: functions.idsWith, isPlatform: functions.isPlatform },
  };
}

/**
 * The SQL condition for one permission key of an access policy. `id` is the
 * text expression holding the scope id, compared as text so a malformed path
 * never raises a cast error. Without `sql` it calls the access contract
 * (`tenant_ids_with`, `is_platform`); with it, the templates.
 */
export function accessCheck(
  where: string,
  target: AccessTarget,
  key: string,
  id: string | undefined,
): string {
  if (key === "") throw new TypeError(`${where}: a permission key is empty`);
  const scope = target.scope ?? "tenant";
  const permission = sqlString(key);
  if (target.sql === "provider") {
    throw new TypeError(
      `${where}: sql "provider" needs the config's authorization provider; write the policy with \`better-supabase gen\` or pass its templates`,
    );
  }
  if (!target.sql) {
    if (scope === "platform")
      return `(select better_supabase.is_platform(${permission}))`;
    if (scope !== "tenant") {
      throw new TypeError(
        `${where}: scope "${scope}" needs sql templates; without them use "tenant" or "platform"`,
      );
    }
    if (id === undefined)
      throw new TypeError(`${where}: scope "tenant" needs a segment`);
    return `${id} in (select t::text from better_supabase.tenant_ids_with(${permission}) t)`;
  }
  if (scope === "platform") {
    return `(select ${fillTemplate(`${where} sql.isPlatform`, target.sql.isPlatform, { permission })})`;
  }
  if (!isScopeName(scope))
    throw new TypeError(`${where}: invalid scope "${scope}"`);
  if (id === undefined)
    throw new TypeError(`${where}: scope "${scope}" needs a segment`);
  return `${id} in (select t.id::text from ${fillTemplate(`${where} sql.idsWith`, target.sql.idsWith, { permission, scope })} as t(id))`;
}
