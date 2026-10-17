import type { AnyBlocksConfig } from "../config/blocks.ts";
import type { ModuleFile, ModuleLayout, SqlModule } from "./module-types.ts";

import { sqlIdent } from "../core/template.ts";
import { eventTriggersOf } from "./event-triggers.ts";
import { moduleContext } from "./module-context.ts";
import {
  hasPlatformRoles,
  MODULE_PERMISSION_SCOPES,
  moduleOperations,
  modulePermissionKey,
  type OperationModule,
} from "./modules/access-model.ts";
import { SQL_MODULES, checkModules, resolveModules } from "./registry.ts";

/** A permission key a SQL module checks, from `modulePermissionKeys`. */
export interface ModulePermissionKey {
  readonly module: string;
  /** The action in `blocks.<module>.permissions` that overrides the key. */
  readonly action: string;
  readonly key: string;
  /**
   * `tenant` for keys checked in a tenant (`member_can`, `can`,
   * `tenant_ids_with`), `platform` for `is_platform` and `platform_can`.
   */
  readonly scope: "tenant" | "platform";
}

/** Actions a module checks only when `blocks.<module>.permissions` names a key. */
const OPTIONAL_MODULE_PERMISSIONS: Readonly<
  Record<string, Readonly<Record<string, "tenant" | "platform">>>
> = {
  organizations: {
    create: "platform",
    updatePlatform: "platform",
    deletePlatform: "platform",
    updateRolePlatform: "platform",
    removeMemberPlatform: "platform",
  },
  audit: { reveal: "tenant" },
  "data-lifecycle": { deletePlatform: "platform" },
};

const isPermissionModule = (name: string): name is OperationModule =>
  Object.hasOwn(MODULE_PERMISSION_SCOPES, name);

/**
 * Every permission key the modules `names` install (with what they pull
 * in) check, after `blocks.<module>.permissions` overrides. Modules in custom
 * mode are skipped, and so is `invitations.invitePlatform` without platform
 * roles.
 */
export function modulePermissionKeys(
  config: AnyBlocksConfig,
  names: readonly string[],
): ModulePermissionKey[] {
  const layout: ModuleLayout = { modules: config };
  checkModules(config);
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module): ModulePermissionKey[] => {
    const name = module.name;
    if (!isPermissionModule(name)) return [];
    const ctx = moduleContext(name, layout, installed);
    if (ctx.mode === "custom") return [];
    const scopes: Readonly<Record<string, "tenant" | "platform">> =
      MODULE_PERMISSION_SCOPES[name];
    const optional = Object.entries(
      OPTIONAL_MODULE_PERMISSIONS[name] ?? {},
    ).flatMap(([action, scope]): ModulePermissionKey[] => {
      const key = ctx.permissionKey(action, "");
      return key === "" ? [] : [{ module: name, action, key, scope }];
    });
    return [
      ...Object.entries(moduleOperations(name)).flatMap(
        ([action, fallback]): ModulePermissionKey[] =>
          action === "invitePlatform" && !hasPlatformRoles(ctx)
            ? []
            : [
                {
                  module: name,
                  action,
                  key: modulePermissionKey(ctx, action, fallback),
                  scope: scopes[action]!,
                },
              ],
      ),
      ...optional,
    ];
  });
}

const CREATE_EXTENSION =
  /^create extension if not exists "?([a-z_][a-z0-9_]*)"?(?: with schema "?([a-z_][a-z0-9_]*)"?)?;/gim;

/**
 * The extensions a module's schema file creates, again for its data file. A
 * schema diff can leave an extension out of the migration (pg-delta skips
 * one in a schema it doesn't manage, such as `extensions` or pgmq's own),
 * and `sql data` then still puts it in one.
 */
export function moduleExtensions(body: string): string {
  return extensionsOf([body])
    .map((extension) => extension.statement)
    .join("\n");
}

export interface ModuleExtension {
  readonly name: string;
  readonly statement: string;
}

function extensionsOf(bodies: readonly string[]): ModuleExtension[] {
  const seen = new Set<string>();
  return bodies.flatMap((body) =>
    [...body.matchAll(CREATE_EXTENSION)].flatMap(
      ([, name = "", schema]): ModuleExtension[] => {
        const key = name.toLowerCase();
        if (seen.has(key)) return [];
        seen.add(key);
        return [
          {
            name: key,
            statement: `create extension if not exists ${sqlIdent(name)}${schema === undefined ? "" : ` with schema ${sqlIdent(schema)}`};`,
          },
        ];
      },
    ),
  );
}

export const moduleSchemaExtensions = (
  files: readonly ModuleFile[],
): ModuleExtension[] =>
  extensionsOf(
    files.filter((file) => file.kind === "schema").map((file) => file.contents),
  );

/**
 * The event triggers each of these modules creates, as its default file
 * renders them, for doctor's check of a database.
 */
export function moduleEventTriggers(
  names: readonly string[],
  modules: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): { readonly module: string; readonly name: string }[] {
  return names.flatMap((module) => {
    const definition = modules[module];
    if (!definition) return [];
    let body: string;
    try {
      body = definition.sql;
    } catch {
      return [];
    }
    return eventTriggersOf(body).map(({ name }) => ({ module, name }));
  });
}
