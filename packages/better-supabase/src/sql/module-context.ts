import type { AccessBlockConfig, AnyBlocksConfig } from "../config/blocks.ts";
import type { ModuleLayout, SqlModule } from "./module-types.ts";

import {
  createModuleContext,
  type ModuleContext,
  type ModuleIdType,
} from "./context.ts";

/** The registry `moduleContext` reads names and integrations from. */
export interface ModuleRegistry {
  readonly modules: Readonly<Record<string, SqlModule>>;
  readonly resolve: (
    names: readonly string[],
    layout: ModuleLayout,
  ) => readonly SqlModule[];
}

let bound: ModuleRegistry | undefined;

/**
 * Called once by `registry.ts`. The registry imports every module, and some
 * modules build their SQL from a context, so the context reads the registry
 * through this binding instead of importing it.
 */
export function bindModuleRegistry(registry: ModuleRegistry): void {
  bound = registry;
}

function registry(): ModuleRegistry {
  if (!bound) {
    throw new Error("The SQL module registry is not loaded.");
  }

  return bound;
}

/** The context a module renders with for `layout`. */
export function moduleContext(
  name: string,
  layout: ModuleLayout = {},
  installed?: readonly string[],
): ModuleContext {
  const modules = withProviderDefaults(layout);
  const readable = new Map<string, ReadonlySet<string>>();

  return createModuleContext(
    name,
    (module) => registry().modules[module]?.names,
    {
      ...(modules ? { modules } : {}),
      ...(layout.claims ? { claims: layout.claims } : {}),
      ...(layout.subjects ? { subjects: layout.subjects } : {}),
      ...(layout.appTables ? { appTables: Object.keys(layout.appTables) } : {}),
      ...(installed ? { installed } : {}),
      ...(layout.scope ? { scope: layout.scope } : {}),
      ...(layout.naming?.tenant ? { tenantName: layout.naming.tenant } : {}),
      ...providerIdType(layout),
      integrations(module) {
        const definition = registry().modules[module];

        if (!definition || definition.integrates?.includes("*")) {
          return;
        }

        let set = readable.get(module);

        if (!set) {
          set = new Set([
            ...registry()
              .resolve([module], layout)
              .map((entry) => entry.name),
            ...(definition.integrates ?? []),
          ]);
          readable.set(module, set);
        }

        return set;
      },
    },
  );
}

/**
 * The modules that install their functions in `better_supabase` whatever
 * `schema` says.
 */

/**
 * `blocks` with what the authorization provider already says: an adopted
 * `tenant` module on a membership table whose role the provider reads through a
 * roles table gets the same `roleThrough`, unless the config sets one.
 */
export function withProviderDefaults(
  layout: ModuleLayout,
): AnyBlocksConfig | undefined {
  return withProviderRoles(layout, withProviderSuspension(layout));
}

/**
 * `blocks.access.disabled` from the provider's `suspension` under the
 * `provider` model, per subject, unless the config sets that subject.
 */
function withProviderSuspension(
  layout: ModuleLayout,
): AnyBlocksConfig | undefined {
  const modules = layout.modules;
  const suspension = layout.accessProvider?.suspension;
  const access = modules?.access;

  if (!modules || !suspension || access?.model !== "provider") {
    return modules;
  }

  const configured = access.disabled ?? {};

  const disabled: NonNullable<AccessBlockConfig["disabled"]> = {
    ...configured,
    ...(configured.tenant === undefined && suspension.tenant
      ? { tenant: suspension.tenant }
      : {}),
    ...(configured.user === undefined && suspension.user
      ? { user: suspension.user }
      : {}),
  };

  if (
    disabled.tenant === configured.tenant &&
    disabled.user === configured.user
  ) {
    return modules;
  }

  return { ...modules, access: { ...access, disabled } };
}

function withProviderRoles(
  layout: ModuleLayout,
  modules: AnyBlocksConfig | undefined,
): AnyBlocksConfig | undefined {
  const sources = layout.accessProvider?.roleSources;
  const tenant = modules?.["tenant"];

  if (!modules || !sources || tenant?.mode !== "adopt") {
    return modules;
  }

  if (tenant.options?.["roleThrough"] !== undefined) {
    return modules;
  }

  const mapped = tenant.tables?.["memberships"];

  if (typeof mapped !== "string") {
    return modules;
  }

  const table = mapped.includes(".")
    ? mapped
    : `${tenant.schema ?? "better_supabase"}.${mapped}`;

  const role = tenant.columns?.["memberships"]?.["role"] ?? "role";

  const source = sources.find(
    (entry) => entry.table === table && entry.role.column === role,
  );

  if (!source) {
    return modules;
  }

  return {
    ...modules,
    tenant: {
      ...tenant,
      options: { ...tenant.options, roleThrough: source.role.through },
    },
  };
}

/**
 * The tenant id type the authorization provider gives, preferring the access
 * model's scope.
 */
export function providerIdType(layout: ModuleLayout): {
  providerIdType?: ModuleIdType;
} {
  const idType =
    layout.accessProvider?.idType ?? layout.entitlementsProvider?.idType;

  return idType ? { providerIdType: idType } : {};
}
