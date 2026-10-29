import type { AnyBlocksConfig } from "../config/blocks.ts";
import type { BlockSqlFile, BlockSqlLayout, BlockSql } from "./module-types.ts";

import { sqlIdent } from "../core/template.ts";
import { eventTriggersOf } from "./event-triggers.ts";
import { moduleContext } from "./module-context.ts";
import {
  isOperationModule,
  moduleOperations,
  modulePermissionKey,
} from "./modules/permissions-model.ts";
import { hasPlatformRoles } from "./modules/permissions-platform.ts";
import { MODULE_PERMISSION_SCOPES } from "./modules/permissions-scopes.ts";
import { OPTIONAL_MODULE_PERMISSIONS } from "./optional-permissions.ts";
import { SQL_MODULES, checkModules, resolveBlocks } from "./registry.ts";

/** A permission key a SQL module checks, from `modulePermissionKeys`. */
export interface BlockSqlPermissionKey {
  readonly module: string;
  /** The action in `blocks.<module>.permissions` that overrides the key. */
  readonly action: string;
  readonly key: string;
  /**
   * `tenant` for keys checked in a tenant (`member_can`, `can`,
   * `tenant_ids_with`), `platform` for `is_platform` and `platform_can`.
   */
  readonly scope: "tenant" | "platform";
  readonly setting?: string;
}

/**
 * Every permission key the modules `names` install (with what they pull in)
 * check, after `blocks.<module>.permissions` overrides. Modules in custom mode
 * are skipped, and so is `invitations.invitePlatform` without platform roles.
 */
export function modulePermissionKeys(
  config: AnyBlocksConfig,
  names: readonly string[],
  subjects?: BlockSqlLayout["subjects"],
): BlockSqlPermissionKey[] {
  const layout: BlockSqlLayout = {
    modules: config,
    ...(subjects === undefined ? {} : { subjects }),
  };

  checkModules(config);
  const modules = resolveBlocks(names, layout);
  const installed = modules.map((module) => module.name);

  return modules.flatMap((module): BlockSqlPermissionKey[] => {
    const name = module.name;

    if (!isOperationModule(name)) {
      return [];
    }

    const ctx = moduleContext(name, layout, installed);

    if (ctx.mode === "custom") {
      return [];
    }

    const scopes: Readonly<Record<string, "tenant" | "platform">> =
      MODULE_PERMISSION_SCOPES[name];

    const optional = Object.entries(
      OPTIONAL_MODULE_PERMISSIONS[name] ?? {},
    ).flatMap(([action, scope]): BlockSqlPermissionKey[] => {
      const key = ctx.permissionKey(action, "");

      return key === "" ? [] : [{ module: name, action, key, scope }];
    });

    const unused = new Set(SQL_MODULES[name]?.unusedPermissions?.(ctx));

    return [
      ...Object.entries(moduleOperations(name)).flatMap(
        ([action, fallback]): BlockSqlPermissionKey[] =>
          unused.has(action) ||
          (action === "invitePlatform" && !hasPlatformRoles(ctx))
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
      ...(SQL_MODULES[name]?.permissionKeys?.(ctx) ?? []).map(
        (entry): BlockSqlPermissionKey => ({ module: name, ...entry }),
      ),
    ];
  });
}

const CREATE_EXTENSION =
  /^create extension if not exists "?([a-z_][a-z0-9_]*)"?(?: with schema "?([a-z_][a-z0-9_]*)"?)?;/gim;

/**
 * The extensions a module's schema file creates, again for its data file. A
 * schema diff can leave an extension out of the migration (pg-delta skips one
 * in a schema it doesn't manage, such as `extensions` or pgmq's own), and `sql
 * data` then still puts it in one.
 */
export function moduleExtensions(body: string): string {
  return extensionsOf([body])
    .map((extension) => extension.statement)
    .join("\n");
}

export interface BlockSqlExtension {
  readonly name: string;
  readonly statement: string;
}

function extensionsOf(bodies: readonly string[]): BlockSqlExtension[] {
  const seen = new Set<string>();

  return bodies.flatMap((body) =>
    [...body.matchAll(CREATE_EXTENSION)].flatMap(
      ([, name = "", schema]): BlockSqlExtension[] => {
        const key = name.toLowerCase();

        if (seen.has(key)) {
          return [];
        }

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
  files: readonly BlockSqlFile[],
): BlockSqlExtension[] =>
  extensionsOf(
    files.filter((file) => file.kind === "schema").map((file) => file.contents),
  );

/**
 * The installed modules' soft-delete columns (`BlockSql.hidingColumns`), as
 * `schema.table.column` after the layout's renames, for doctor BS213.
 */
export function moduleHidingColumns(
  installed: readonly string[],
  layout: BlockSqlLayout,
): string[] {
  return resolveBlocks(installed, layout).flatMap((module) => {
    if (!module.hidingColumns) {
      return [];
    }

    const ctx = moduleContext(module.name, layout, installed);

    return module.hidingColumns.flatMap((entry) => {
      const [table = "", column = ""] = entry.split(".");

      if (!ctx.hasTable(table) || !ctx.has(table, column)) {
        return [];
      }

      const { schema, name } = ctx.tableName(table);

      return [`${schema}.${name}.${ctx.colName(table, column)}`];
    });
  });
}

/**
 * The event triggers each of these modules creates, as its default file renders
 * them, for doctor's check of a database.
 */
export function moduleEventTriggers(
  names: readonly string[],
  modules: Readonly<Record<string, BlockSql>> = SQL_MODULES,
): { readonly module: string; readonly name: string }[] {
  return names.flatMap((module) => {
    const definition = modules[module];

    if (!definition) {
      return [];
    }

    let body: string;

    try {
      body = definition.sql;
    } catch {
      return [];
    }

    return eventTriggersOf(body).map(({ name }) => ({ module, name }));
  });
}
