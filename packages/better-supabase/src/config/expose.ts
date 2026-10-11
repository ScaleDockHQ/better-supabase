/** A privilege the Data API roles can be granted on a table or view. */
export type Privilege = "select" | "insert" | "update" | "delete";

export type ColumnPrivilege = `${"select" | "insert" | "update"}(${string})`;

export type ExposePrivilege = Privilege | ColumnPrivilege;

/** A role the `grants` module writes privileges for. */
export type ExposeRole = "anon" | "authenticated" | "service_role";

/**
 * Data API grants for one table: privileges for `authenticated`, or per
 * role. `serviceRole` defaults to every privilege. For a function, keyed by
 * its signature (`search_notes(text, integer)`), `execute` lists the roles
 * that may call it; `service_role` is added unless `serviceRole` is false.
 */
export type ExposeConfig =
  | readonly ExposePrivilege[]
  | {
      readonly anon?: readonly ExposePrivilege[];
      readonly authenticated?: readonly ExposePrivilege[];
      readonly serviceRole?: readonly ExposePrivilege[];
    }
  | {
      readonly execute: readonly ("anon" | "authenticated")[];
      readonly serviceRole?: boolean;
    };

/** Resolved grants for one table. */
export interface ResolvedExpose {
  readonly anon: readonly ExposePrivilege[];
  readonly authenticated: readonly ExposePrivilege[];
  readonly serviceRole: readonly ExposePrivilege[];
}

const ALL_PRIVILEGES: readonly Privilege[] = [
  "select",
  "insert",
  "update",
  "delete",
];

export const isFunctionKey = (key: string): boolean => key.endsWith(")");

const EXPOSE_PRIVILEGE =
  /^(?:select|insert|update|delete|(?:select|insert|update)\s*\(\s*[a-z_][a-z0-9_$]*(?:\s*,\s*[a-z_][a-z0-9_$]*)*\s*\))$/;

function checkedPrivileges(
  key: string,
  privileges: readonly ExposePrivilege[],
): readonly ExposePrivilege[] {
  for (const privilege of privileges) {
    const value: unknown = privilege;
    if (typeof value !== "string" || !EXPOSE_PRIVILEGE.test(value)) {
      throw new TypeError(
        `expose.${key}: "${String(value)}" is not a privilege. Use select, insert, update or delete, or name columns such as "update(title, body)"`,
      );
    }
  }
  return privileges;
}

export function resolveExpose(
  key: string,
  entry: ExposeConfig,
): ResolvedExpose {
  if (Array.isArray(entry))
    return {
      anon: [],
      authenticated: checkedPrivileges(key, entry),
      serviceRole: ALL_PRIVILEGES,
    };
  if ("execute" in entry) {
    throw new TypeError(
      `expose.${key}: \`execute\` is for functions; key it by its signature, such as ${key}(text)`,
    );
  }
  // SAFETY: the checks above removed the privilege-list and function forms.
  const roles = entry as Exclude<
    ExposeConfig,
    readonly ExposePrivilege[] | { readonly execute: unknown }
  >;
  return {
    anon: checkedPrivileges(key, roles.anon ?? []),
    authenticated: checkedPrivileges(key, roles.authenticated ?? []),
    serviceRole: checkedPrivileges(key, roles.serviceRole ?? ALL_PRIVILEGES),
  };
}

export function resolveExposeFunction(
  key: string,
  entry: ExposeConfig,
): readonly ExposeRole[] {
  if (Array.isArray(entry) || !("execute" in entry)) {
    throw new TypeError(
      `expose.${key}: a function takes { execute: ["authenticated"] }, not table privileges`,
    );
  }
  return [
    ...entry.execute,
    ...(entry.serviceRole === false ? [] : (["service_role"] as const)),
  ];
}
