import type { AccessBlockConfig, AnyBlocksConfig } from "../config/blocks.ts";
import type {
  BlockSqlContext,
  BlockSqlIdType,
  Contributor,
} from "./context.ts";
import type { BlockContributions } from "./contributions.ts";
import type { BlockSqlLayout, BlockSql } from "./module-types.ts";
import type { ViewColumns } from "./view-columns.ts";

import { installedBlockSubjects } from "../config/block-subjects.ts";
import { createModuleContext } from "./context.ts";
import { providerAnswersForGuests } from "./guest-sql.ts";
import { renamedInstances, rendersOwnInstance } from "./instance-names.ts";
import { viewColumns } from "./view-columns.ts";

/** The registry `moduleContext` reads names and integrations from. */
export interface BlockSqlRegistry {
  readonly modules: Readonly<Record<string, BlockSql>>;
  readonly resolve: (
    names: readonly string[],
    layout: BlockSqlLayout,
  ) => readonly BlockSql[];
}

let bound: BlockSqlRegistry | undefined;

/**
 * Called once by `registry.ts`. The registry imports every module, and some
 * modules build their SQL from a context, so the context reads the registry
 * through this binding instead of importing it.
 */
export function bindModuleRegistry(registry: BlockSqlRegistry): void {
  bound = registry;
}

function registry(): BlockSqlRegistry {
  if (!bound) {
    throw new Error("The SQL module registry is not loaded.");
  }

  return bound;
}

/**
 * The context a module renders with for `layout`; with `instance`, the context
 * of that instance of the module.
 */
export function moduleContext(
  name: string,
  layout: BlockSqlLayout = {},
  installed?: readonly string[],
  instance?: string,
): BlockSqlContext {
  const modules = withProviderDefaults(layout);
  const readable = new Map<string, ReadonlySet<string>>();

  return createModuleContext(
    name,
    (module) => registry().modules[module]?.names,
    {
      ...(modules ? { modules } : {}),
      ...(layout.claims ? { claims: layout.claims } : {}),
      ...(layout.subjects
        ? {
            subjects: installed
              ? installedBlockSubjects(
                  layout.subjects,
                  installed,
                  layout.modules ?? {},
                )
              : layout.subjects,
          }
        : {}),
      ...(layout.appTables ? { appTables: Object.keys(layout.appTables) } : {}),
      ...(layout.ownTables ? { ownTables: layout.ownTables } : {}),
      ...(layout.ownViews ? { ownViews: layout.ownViews } : {}),
      ...(installed ? { installed } : {}),
      ...(layout.instances ? { instances: layout.instances } : {}),
      ...(instance === undefined || instance === name ? {} : { instance }),
      contributors: (block) => contributorsOf(block, layout, installed),
      ...(layout.scope ? { scope: layout.scope } : {}),
      ...(layout.blockTenantColumn
        ? { tenantColumn: layout.blockTenantColumn }
        : {}),
      ...providerIdType(layout),
      ...providerGuests(layout),
      ...(modules?.permissions?.model === "provider" &&
      layout.accessProvider?.functions.rowsWith !== undefined
        ? {
            providerRowsWith: layout.accessProvider.functions.rowsWith,
            ...(layout.accessProvider.functions.rowsWithFor === undefined
              ? {}
              : {
                  providerRowsWithFor:
                    layout.accessProvider.functions.rowsWithFor,
                }),
          }
        : {}),
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
 * `blocks` with what the authorization provider already says: a `memberships`
 * block over the app's membership table, whose role the provider reads through
 * a roles table, gets the same `roleThrough`, unless the config sets one.
 */
export function withProviderDefaults(
  layout: BlockSqlLayout,
): AnyBlocksConfig | undefined {
  return viewColumnsOf(layout).modules;
}

/**
 * The provider defaults, then the optional columns the app's views lack mapped
 * to `null`, with the required columns they lack.
 */
export function viewColumnsOf(layout: BlockSqlLayout): ViewColumns {
  return viewColumns(
    layout,
    withProviderRoles(layout, withProviderSuspension(layout)),
    (module) => registry().modules[module]?.names,
  );
}

/**
 * `blocks.permissions.disabled` from the provider's `suspension` under the
 * `provider` model, per subject, unless the config sets that subject.
 */
function withProviderSuspension(
  layout: BlockSqlLayout,
): AnyBlocksConfig | undefined {
  const modules = layout.modules;
  const suspension = layout.accessProvider?.suspension;
  const access = modules?.permissions;

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

  return { ...modules, permissions: { ...access, disabled } };
}

function withProviderRoles(
  layout: BlockSqlLayout,
  modules: AnyBlocksConfig | undefined,
): AnyBlocksConfig | undefined {
  const sources = layout.accessProvider?.roleSources;
  const tenant = modules?.["memberships"];

  if (
    !modules ||
    !sources ||
    tenant === undefined ||
    tenant.mode === "custom" ||
    tenant.options?.["roleThrough"] !== undefined
  ) {
    return modules;
  }

  const mapped = tenant.tables?.["memberships"];

  if (typeof mapped !== "string") {
    return modules;
  }

  const table = mapped.includes(".")
    ? mapped
    : `${tenant.schema ?? "better_supabase"}.${mapped}`;

  if (layout.ownTables?.[table] === undefined) {
    return modules;
  }

  const role = tenant.columns?.["memberships"]?.["role"] ?? "role";

  const source = sources.find(
    (entry) => entry.table === table && entry.role.column === role,
  );

  if (!source) {
    return modules;
  }

  return {
    ...modules,
    memberships: {
      ...tenant,
      options: { ...tenant.options, roleThrough: source.role.through },
    },
  };
}

/**
 * The tenant id type the authorization provider gives, preferring the access
 * model's scope.
 */
export function providerIdType(layout: BlockSqlLayout): {
  providerIdType?: BlockSqlIdType;
} {
  const idType =
    layout.accessProvider?.idType ?? layout.entitlementsProvider?.idType;

  return idType ? { providerIdType: idType } : {};
}

/**
 * Whether the authorization provider answers for guests, which only counts
 * under the `provider` model.
 */
export function providerGuests(layout: BlockSqlLayout): {
  providerGuests?: boolean;
} {
  return providerAnswersForGuests(layout) ? { providerGuests: true } : {};
}

/**
 * The installed instances whose block contributes to `block`, in block order,
 * each with the instance of `block` its `uses` names.
 */
function contributorsOf<K extends keyof BlockContributions>(
  block: K,
  layout: BlockSqlLayout,
  installed: readonly string[] | undefined,
): readonly Contributor<K>[] {
  if (installed === undefined) {
    return [];
  }

  const set = new Set(installed);

  return Object.entries(registry().modules).flatMap(([name, definition]) => {
    const contribute = set.has(name)
      ? definition.contributes?.[block]
      : undefined;

    if (contribute === undefined) {
      return [];
    }

    return [
      ...(rendersOwnInstance(name, layout) ? [name] : []),
      ...renamedInstances(name, layout).map((each) => each.name),
    ].flatMap((instance): Contributor<K>[] => {
      const uses = layout.instances?.[instance]?.uses[block];

      // A renamed instance would repeat its block's subject types and action
      // names, so it contributes only where its `uses` sends it, or to the
      // default instance of a block its block requires.
      if (
        instance !== name &&
        uses === undefined &&
        !definition.requires.includes(block)
      ) {
        return [];
      }

      const own = moduleContext(name, layout, installed, instance);

      return own.mode === "custom"
        ? []
        : [
            {
              instance: uses ?? block,
              contribute: (target) => contribute(own, target),
            },
          ];
    });
  });
}
