import { posix } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";

import { PRESET_CATALOG } from "../../preset/index.ts";
import {
  DEFAULT_ROLES,
  defaultOperationKey,
  modulePermissionKeys,
  resolveBlock,
} from "../../sql/index.ts";
import { CliError } from "../core/errors.ts";
import { GENERATED_HEADER } from "./emit.ts";
import { q } from "./shared.ts";

/** The suffix of the migration `gen.permissionCatalog` writes. */
export const PERMISSION_CATALOG_SUFFIX =
  "_better_supabase_permission_catalog.sql";

/** The roles that hold the generated default grants (the managed catalog's). */
const CATALOG_ROLES = ["owner", "admin", "member"] as const;

type CatalogRole = (typeof CATALOG_ROLES)[number];

type CatalogConfig = Pick<
  ResolvedConfig,
  "blocks" | "blockNames" | "subjects" | "output" | "gen"
>;

/** One key of the catalog and the role grants it starts with. */
export interface CatalogKey {
  readonly key: string;
  readonly scope: "tenant" | "platform";
  readonly roles: readonly CatalogRole[];
}

/**
 * Whether the granted key (`*`, `prefix.*` or an exact key) covers `wanted`, as
 * `permission_matches` does in SQL.
 */
export function grantMatches(granted: string, wanted: string): boolean {
  return (
    granted === "*" ||
    granted === wanted ||
    (granted.endsWith(".*") && wanted.startsWith(granted.slice(0, -1)))
  );
}

function rolesOfKey(defaultKey: string, declaredRead: boolean): CatalogRole[] {
  return CATALOG_ROLES.filter((role) => {
    if (role === "member" && declaredRead) {
      return true;
    }

    return (DEFAULT_ROLES[role] ?? []).some((granted) =>
      grantMatches(granted, defaultKey),
    );
  });
}

/**
 * Every permission key the installed blocks check or declare on their entities,
 * with the default roles that hold it. A key a block renamed is granted to the
 * roles that hold its default name.
 */
export function permissionCatalogKeys(config: CatalogConfig): CatalogKey[] {
  const keys = new Map<string, CatalogKey>();

  for (const entry of modulePermissionKeys(
    config.blocks,
    config.blockNames,
    config.subjects,
  )) {
    const held = keys.get(entry.key);

    // One key can be checked in both scopes (`audit.read`); the tenant roles
    // keep it.
    const scope =
      held?.scope === "tenant" || entry.scope === "tenant"
        ? "tenant"
        : "platform";

    keys.set(entry.key, {
      key: entry.key,
      scope,
      roles: [
        ...new Set([
          ...(held?.roles ?? []),
          ...(entry.scope === "platform"
            ? []
            : rolesOfKey(
                defaultOperationKey(entry.module, entry.action) ?? entry.key,
                false,
              )),
        ]),
      ],
    });
  }

  for (const manifest of PRESET_CATALOG.manifests) {
    if (!manifest.sql.some((module) => config.blockNames.includes(module))) {
      continue;
    }

    const declared = Object.values(manifest.entityPermissions ?? {}).flatMap(
      (verbs) => Object.entries(verbs).map(([verb, key]) => ({ verb, key })),
    );

    for (const permission of declared) {
      const held = keys.get(permission.key);

      keys.set(permission.key, {
        key: permission.key,
        scope: "tenant",
        roles: [
          ...new Set([
            ...(held?.roles ?? []),
            ...rolesOfKey(permission.key, permission.verb === "read"),
            "owner" as const,
            "admin" as const,
          ]),
        ],
      });
    }
  }

  return [...keys.values()].toSorted((a, b) => a.key.localeCompare(b.key));
}

function assertManagedTables(config: CatalogConfig): void {
  const settings = config.blocks.permissions;
  const permissions = resolveBlock(settings);

  if (settings?.model !== "catalog") {
    throw new CliError(
      "config_invalid",
      'gen.permissionCatalog needs `blocks.permissions.model: "catalog"`, which keeps keys and role grants as rows.',
    );
  }

  if (
    Object.keys(permissions.tables).length > 0 ||
    Object.keys(permissions.columns).length > 0
  ) {
    throw new CliError(
      "config_invalid",
      "gen.permissionCatalog writes the managed catalog tables; remove `tables` and `columns` from `blocks.permissions` or write the rows yourself.",
    );
  }
}

/**
 * The migration that inserts the catalog rows and the default grants. Every
 * statement is re-runnable, and a later migration holds all of them.
 */
export function permissionCatalogSql(config: CatalogConfig): string {
  assertManagedTables(config);

  const keys = permissionCatalogKeys(config);

  const grants = keys.flatMap((entry) =>
    entry.roles.map((role) => [role, entry.key] as const),
  );

  const lit = (value: string): string => `'${value.replaceAll("'", "''")}'`;

  return [
    "-- The permission catalog of the installed blocks and the default grants of the owner,",
    "-- admin and member roles. Managed by `better-supabase gen` (gen.permissionCatalog):",
    "-- it writes a new migration when the installed blocks or their keys change.",
    "insert into better_supabase.permissions (key)",
    "select v.key",
    "from (values",
    keys.map((entry) => `  (${lit(entry.key)})`).join(",\n"),
    ") as v(key)",
    "where not exists (select 1 from better_supabase.permissions p where p.key = v.key);",
    "",
    "insert into better_supabase.role_permissions (role_id, permission_id)",
    "select r.id, p.id",
    "from (values",
    grants.map(([role, key]) => `  (${lit(role)}, ${lit(key)})`).join(",\n"),
    ") as v(role_key, permission_key)",
    "join better_supabase.roles r on r.key = v.role_key",
    "join better_supabase.permissions p on p.key = v.permission_key",
    "on conflict do nothing;",
    "",
    "select better_supabase.bump_authz_versions(array(select id from auth.users))",
    "where to_regprocedure('better_supabase.bump_authz_versions(uuid[])') is not null;",
    "",
  ].join("\n");
}

/** `permission-scopes.ts`, next to `blocks.config.ts`. */
function permissionScopesPath(config: Pick<ResolvedConfig, "output">): string {
  return posix.join(posix.dirname(config.output), "permission-scopes.ts");
}

/**
 * `permission-scopes.ts`: `apiKeyScopes` (every tenant key) and `oauthScopes`
 * (the same without the `manage` keys, which no OAuth client holds), for the
 * `scopes` of `api-keys` and the scopes an `oauth-server` client may request.
 */
export function emitPermissionScopes(config: CatalogConfig): GeneratedFile {
  const tenant = permissionCatalogKeys(config)
    .filter((entry) => entry.scope === "tenant")
    .map((entry) => entry.key);

  const list = (keys: readonly string[]): string =>
    keys.length === 0
      ? "[]"
      : `[\n${keys.map((key) => `  ${q(key)},`).join("\n")}\n]`;

  return {
    path: permissionScopesPath(config),
    contents: [
      GENERATED_HEADER,
      "",
      "/** The keys an API key may hold, from the permission catalog. */",
      `export const apiKeyScopes = ${list(tenant)} as const;`,
      "",
      "/** The scopes an OAuth client may request: the API key scopes without `manage` keys. */",
      `export const oauthScopes = ${list(tenant.filter((key) => !key.endsWith(".manage")))} as const;`,
      "",
      "export type ApiKeyScope = (typeof apiKeyScopes)[number];",
      "",
      "export type OauthScope = (typeof oauthScopes)[number];",
      "",
    ].join("\n"),
  };
}
