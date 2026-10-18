import type { BlockScope } from "../config/blocks.ts";
import type { ModuleIdType } from "./context.ts";

/**
 * How a module checks who may reach a row, for the block's scope. Modules
 * call these instead of naming the access contract (`can`,
 * `tenant_ids_with`, `is_platform`) or the tenant module's helpers, so the
 * same module runs per tenant, per user or in one shared space. In `tenant`
 * scope each one renders the access contract call it replaces.
 */
export interface ModuleScope {
  readonly kind: BlockScope;
  /** The type of a scope id: the tenant id type, or `uuid` (a user id) in `user` scope. */
  readonly idType: ModuleIdType;
  /**
   * The type of a managed table's scope column: `<idType> not null` per
   * tenant, nullable outside it (`uuid default auth.uid()` per user).
   */
  column(): string;
  /** True when the caller holds `permission` (a SQL expression) in scope `id`. */
  can(id: string, permission: string): string;
  /** True when `user` (a uuid expression) holds `permission` in scope `id`. */
  canUser(user: string, id: string, permission: string): string;
  /**
   * PL/pgSQL that sets the scope id parameter `param` for the scope: the
   * caller's id per user (the service role keeps what it passes), null in
   * the shared space. Empty per tenant.
   */
  bind(param: string): string;
  /**
   * A scope id argument as an expression: as passed per tenant, the
   * caller's id when it is null per user, null in the shared space.
   */
  value(param: string): string;
  /**
   * A set-returning call of the scope ids the caller holds `permission` in,
   * usable as `select ...`, `x in (select ...)` and `from ... x`.
   */
  ids(permission: string): string;
  /** A row policy check: `column` is a scope the caller holds `permission` in. */
  check(column: string, permission: string): string;
  /** `a = b` for scope ids, null-safe in `none` scope where they are null. */
  eq(a: string, b: string): string;
  /**
   * `is_platform(permission)`: whether the caller is platform staff holding
   * `permission`. `false` outside `tenant` scope without the access module.
   */
  platform(permission: string): string;
  /** A set-returning call of the tenants the caller is a member of. */
  members(): string;
}

export interface ModuleScopeSource {
  readonly kind: BlockScope;
  readonly idType: ModuleIdType;
  /** Whether the `access` module is installed, for `platform` outside `tenant` scope. */
  readonly access: boolean;
  /** The tenant module's `member_organization_ids`, as named for the layout. */
  readonly members: () => string;
}

const CALLER = "(select auth.uid())";
const SIGNED_IN = `(${CALLER} is not null)`;

export function moduleScope(source: ModuleScopeSource): ModuleScope {
  const { kind, idType } = source;

  // The sub-select lets Postgres run the call once per statement (an
  // initPlan) when a policy uses it, instead of once per row.
  const platform = (permission: string): string =>
    kind === "tenant" || source.access
      ? `(select coalesce(better_supabase.is_platform(${permission}), false))`
      : "false";

  switch (kind) {
    case "tenant": {
      return {
        kind,
        idType,
        column: () => `${idType} not null`,
        can: (id, permission) =>
          `coalesce(better_supabase.can('tenant', ${id}, ${permission}), false)`,
        canUser: (user, id, permission) =>
          `coalesce(better_supabase.can_user(${user}, 'tenant', ${id}, ${permission}), false)`,
        bind: () => "",
        value: (param) => param,
        ids: (permission) => `better_supabase.tenant_ids_with(${permission})`,
        check: (column, permission) =>
          `${column} in (select better_supabase.tenant_ids_with(${permission}))`,
        eq: (a, b) => `${a} = ${b}`,
        platform,
        members: () => `${source.members()}()`,
      };
    }

    case "user": {
      return {
        kind,
        idType,
        column: () => "uuid default auth.uid()",
        can: (id) => `coalesce(${id} = ${CALLER}, false)`,
        canUser: (user, id) => `coalesce(${id} = ${user}, false)`,
        bind: (param) =>
          `if auth.role() is distinct from 'service_role' then\n    ${param} := ${CALLER};\n  end if;\n  `,
        value: (param) => `coalesce(${param}, ${CALLER})`,
        ids: () => `unnest(array[${CALLER}])`,
        check: (column) => `${column} = ${CALLER}`,
        eq: (a, b) => `${a} = ${b}`,
        platform,
        members: () => `unnest(array[${CALLER}])`,
      };
    }

    case "none": {
      const none = `unnest(case when ${CALLER} is null then '{}'::${idType}[] else array[null::${idType}] end)`;

      return {
        kind,
        idType,
        column: () => idType,
        can: () => SIGNED_IN,
        canUser: (user) => `(${user} is not null)`,
        bind: (param) => `${param} := null;\n  `,
        value: () => `null::${idType}`,
        ids: () => none,
        check: () => SIGNED_IN,
        eq: (a, b) => `${a} is not distinct from ${b}`,
        platform,
        members: () => none,
      };
    }

    default: {
      const never: never = kind;
      throw new TypeError(`Unknown scope "${String(never)}"`);
    }
  }
}
