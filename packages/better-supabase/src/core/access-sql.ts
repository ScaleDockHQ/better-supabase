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
};

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
  readonly sql?: AccessPolicySql;
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

/** The keys a bucket or topic access policy names. */
export function accessKeys(keys: object): string[] {
  return Object.values(keys).filter(
    (key): key is string => typeof key === "string",
  );
}
