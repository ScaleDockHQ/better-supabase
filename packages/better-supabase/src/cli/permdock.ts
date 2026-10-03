import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type { KitPermdock } from "../sql/index.ts";

const PERMDOCK_CONFIGS = [
  "permdock.config.ts",
  "permdock.config.mts",
  "permdock.config.js",
  "permdock.config.mjs",
] as const;

/** The PermDock config file in `root`, if there is one. */
export function permdockConfig(root: string): string | undefined {
  return PERMDOCK_CONFIGS.find((file) => existsSync(resolve(root, file)));
}

/** A manifest value read from a column or fixed in the config. */
type ManifestValue<T> = { readonly column: string } | { readonly value: T };

/** One membership source, as `permdock supabase inspect --out` writes it. */
interface ManifestMembership {
  /** `schema.table`. */
  readonly table: string;
  readonly user: { readonly column: string };
  readonly scope: ManifestValue<string>;
  readonly id: { readonly column: string };
  readonly role?: ManifestValue<string | readonly string[]>;
  readonly expiresAt?: { readonly column: string };
  /** Every column that decides the membership. */
  readonly columns: readonly string[];
}

interface ManifestHelper {
  readonly name: string;
  readonly args: string;
  readonly returns: string;
  readonly execute: readonly string[];
}

/**
 * The parts of PermDock's `supabase-manifest-v1.json` better-supabase reads.
 * Other fields are kept by PermDock and ignored here.
 */
export interface PermdockManifest {
  readonly version: 1;
  readonly hook?: { readonly schema: string; readonly function: string };
  readonly tenantClaim?: string;
  /** `supabase.hook.budget`: bytes of `memberships` plus `attrs`. */
  readonly budget?: number;
  /** `source` is `permdock` or the `schema.function` from `supabase.hook.claims`. */
  readonly claims: readonly {
    readonly name: string;
    readonly source: string;
  }[];
  readonly memberships: readonly ManifestMembership[];
  readonly rls?: {
    readonly schema: string;
    readonly mode: "jwt" | "database";
    readonly scopes: readonly {
      readonly name: string;
      readonly type: string;
    }[];
    readonly helpers: readonly ManifestHelper[];
  };
  /** `schema.table.column`. */
  readonly decidingColumns: readonly string[];
}

/** What a PermDock project in `root` tells better-supabase. */
export interface PermdockProject {
  /** `permdock.config.ts` (or `.mts`, `.js`, `.mjs`), when present. */
  readonly config?: string;
  /** The manifest path, relative to the root. */
  readonly manifestPath: string;
  readonly manifest?: PermdockManifest;
  /** The catalog path, relative to the root. */
  readonly catalogPath: string;
  /** Permission keys whose catalog entry has `rowConditions: true`. */
  readonly rowConditions?: ReadonlySet<string>;
  /** Files that exist but could not be read, with the reason. */
  readonly problems: readonly string[];
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const isString = (value: unknown): value is string => typeof value === "string";

const strings = (value: unknown): string[] =>
  Array.isArray(value) ? value.filter(isString) : [];

const column = (value: unknown): { column: string } | undefined =>
  isRecord(value) && isString(value["column"])
    ? { column: value["column"] }
    : undefined;

function manifestValue<T>(
  value: unknown,
  accept: (inner: unknown) => inner is T,
): ManifestValue<T> | undefined {
  if (!isRecord(value)) return undefined;
  if (isString(value["column"])) return { column: value["column"] };
  return accept(value["value"]) ? { value: value["value"] } : undefined;
}

const roleValue = (value: unknown): value is string | readonly string[] =>
  isString(value) || (Array.isArray(value) && value.every(isString));

function membership(value: unknown): ManifestMembership | undefined {
  if (!isRecord(value) || !isString(value["table"])) return undefined;
  const user = column(value["user"]);
  const id = column(value["id"]);
  const scope = manifestValue(value["scope"], isString);
  if (!user || !id || !scope) return undefined;
  const role = manifestValue(value["role"], roleValue);
  const expiresAt = column(value["expiresAt"]);
  return {
    table: value["table"],
    user,
    scope,
    id,
    ...(role ? { role } : {}),
    ...(expiresAt ? { expiresAt } : {}),
    columns: strings(value["columns"]),
  };
}

/** Reads a parsed manifest; throws with the reason when it isn't version 1. */
export function parseManifest(json: unknown): PermdockManifest {
  if (!isRecord(json)) throw new TypeError("not a JSON object");
  if (json["version"] !== 1) {
    throw new TypeError(
      `version ${String(json["version"])} is not supported (this release reads version 1)`,
    );
  }
  const hook = json["hook"];
  const rls = json["rls"];
  const budget = isRecord(json["budget"]) ? json["budget"]["bytes"] : undefined;
  return {
    version: 1,
    ...(typeof budget === "number" ? { budget } : {}),
    ...(isRecord(hook) && isString(hook["schema"]) && isString(hook["function"])
      ? { hook: { schema: hook["schema"], function: hook["function"] } }
      : {}),
    ...(isString(json["tenantClaim"])
      ? { tenantClaim: json["tenantClaim"] }
      : {}),
    claims: (Array.isArray(json["claims"]) ? json["claims"] : []).flatMap(
      (claim) =>
        isRecord(claim) && isString(claim["name"]) && isString(claim["source"])
          ? [{ name: claim["name"], source: claim["source"] }]
          : [],
    ),
    memberships: (Array.isArray(json["memberships"])
      ? json["memberships"]
      : []
    ).flatMap((entry) => {
      const parsed = membership(entry);
      return parsed ? [parsed] : [];
    }),
    ...(isRecord(rls) && isString(rls["schema"])
      ? {
          rls: {
            schema: rls["schema"],
            mode: rls["mode"] === "jwt" ? "jwt" : "database",
            scopes: (Array.isArray(rls["scopes"]) ? rls["scopes"] : []).flatMap(
              (scope) =>
                isRecord(scope) &&
                isString(scope["name"]) &&
                isString(scope["type"])
                  ? [{ name: scope["name"], type: scope["type"] }]
                  : [],
            ),
            helpers: (Array.isArray(rls["helpers"])
              ? rls["helpers"]
              : []
            ).flatMap((helper) =>
              isRecord(helper) &&
              isString(helper["name"]) &&
              isString(helper["args"]) &&
              isString(helper["returns"])
                ? [
                    {
                      name: helper["name"],
                      args: helper["args"],
                      returns: helper["returns"],
                      execute: strings(helper["execute"]),
                    },
                  ]
                : [],
            ),
          },
        }
      : {}),
    decidingColumns: strings(json["decidingColumns"]),
  };
}

/** The keys of a parsed `permissions.catalog.json` whose entry has `rowConditions: true`. */
export function rowConditionKeys(json: unknown): ReadonlySet<string> {
  if (!isRecord(json) || !Array.isArray(json["permissions"]))
    throw new TypeError("has no permissions array");
  const keys = new Set<string>();
  for (const permission of json["permissions"]) {
    if (
      isRecord(permission) &&
      isString(permission["key"]) &&
      permission["rowConditions"] === true
    )
      keys.add(permission["key"]);
  }
  return keys;
}

async function readJson(
  root: string,
  path: string,
): Promise<{ json: unknown } | { missing: true } | { problem: string }> {
  const absolute = resolve(root, path);
  if (!existsSync(absolute)) return { missing: true };
  try {
    // SAFETY: JSON.parse returns any; callers parse the value.
    return { json: JSON.parse(await readFile(absolute, "utf8")) as unknown };
  } catch (cause) {
    return {
      problem: `${path}: ${cause instanceof Error ? cause.message : String(cause)}`,
    };
  }
}

/**
 * Reads PermDock's JSON outputs: the manifest `permdock supabase inspect
 * --out` writes and the catalog `permdock catalog` writes. Nothing is
 * imported from PermDock. Returns `undefined` when the project has neither a
 * PermDock config nor a manifest.
 */
export async function readPermdock(
  root: string,
  paths: { readonly manifest: string; readonly catalog: string },
): Promise<PermdockProject | undefined> {
  const config = permdockConfig(root);
  const problems: string[] = [];
  const manifestFile = await readJson(root, paths.manifest);
  let manifest: PermdockManifest | undefined;
  if ("json" in manifestFile) {
    try {
      manifest = parseManifest(manifestFile.json);
    } catch (cause) {
      problems.push(
        `${paths.manifest}: ${cause instanceof Error ? cause.message : String(cause)}`,
      );
    }
  } else if ("problem" in manifestFile) problems.push(manifestFile.problem);
  if (!config && !manifest && "missing" in manifestFile) return undefined;
  const catalogFile = await readJson(root, paths.catalog);
  let rowConditions: ReadonlySet<string> | undefined;
  if ("json" in catalogFile) {
    try {
      rowConditions = rowConditionKeys(catalogFile.json);
    } catch (cause) {
      problems.push(
        `${paths.catalog}: ${cause instanceof Error ? cause.message : String(cause)}`,
      );
    }
  } else if ("problem" in catalogFile) problems.push(catalogFile.problem);
  return {
    ...(config ? { config } : {}),
    manifestPath: paths.manifest,
    ...(manifest ? { manifest } : {}),
    catalogPath: paths.catalog,
    ...(rowConditions ? { rowConditions } : {}),
    problems,
  };
}

/** How findings name the PermDock project: its config file or its manifest. */
export const permdockSource = (project: PermdockProject): string =>
  project.config ?? project.manifestPath;

export interface HookMarker {
  readonly version: number;
  readonly schema?: string;
  readonly tenantClaim?: string;
  readonly budget?: number;
  readonly claims: readonly string[];
}

const HOOK_MARKER = /^--\s*permdock:hook\s+v(\d+)([^\n]*)$/m;
const GRANTS_MARKER = /^--\s*permdock:grants\s+v(\d+)([^\n]*)$/m;

function markerFields(rest: string): Map<string, string> {
  const fields = new Map<string, string>();
  for (const match of rest.matchAll(/(\w+)=(\S*)/g))
    fields.set(match[1]!, match[2]!);
  return fields;
}

/** The `-- permdock:hook v1 schema=... tenant=... budget=... claims=...` line PermDock's hook file starts with. */
export function parseHookMarker(sql: string): HookMarker | undefined {
  const match = HOOK_MARKER.exec(sql);
  if (!match) return undefined;
  const fields = markerFields(match[2]!);
  const budget = Number(fields.get("budget"));
  const schema = fields.get("schema");
  const tenantClaim = fields.get("tenant");
  return {
    version: Number(match[1]),
    ...(schema ? { schema } : {}),
    ...(tenantClaim ? { tenantClaim } : {}),
    ...(Number.isFinite(budget) && fields.has("budget") ? { budget } : {}),
    claims: (fields.get("claims") ?? "").split(",").filter(Boolean),
  };
}

/** The `-- permdock:grants v1 schema=...` line of the migration `--grants-out` writes. */
export function parseGrantsMarker(
  sql: string,
): { readonly version: number; readonly schema?: string } | undefined {
  const match = GRANTS_MARKER.exec(sql);
  if (!match) return undefined;
  const schema = markerFields(match[2]!).get("schema");
  return { version: Number(match[1]), ...(schema ? { schema } : {}) };
}

/** How the `entitlements` kit module finds memberships. */
export type EntitlementsMode =
  | { readonly kind: "tenant" }
  | { readonly kind: "permdock"; readonly permdock: KitPermdock }
  | { readonly kind: "invalid"; readonly problem: string };

/**
 * PermDock mode, when the manifest has an `rls` block and
 * `entitlements.permdock` is not `false`: the scope must be one of the
 * manifest's `rls.scopes`. Without a manifest the module keeps using `tenant`.
 */
export function entitlementsMode(
  config: Pick<ResolvedConfig, "entitlements">,
  project: PermdockProject | undefined,
): EntitlementsMode {
  const setting = config.entitlements.permdock;
  const rls = project?.manifest?.rls;
  if (setting === false || !project?.manifest || !rls)
    return { kind: "tenant" };
  if (!rls.scopes.some((scope) => scope.name === setting.scope)) {
    return {
      kind: "invalid",
      problem: `entitlements.permdock.scope is "${setting.scope}", but ${project.manifestPath} has the scopes ${rls.scopes.map((scope) => scope.name).join(", ") || "(none)"}. Set entitlements.permdock: { scope } to one of them.`,
    };
  }
  return {
    kind: "permdock",
    permdock: {
      schema: rls.schema,
      scope: setting.scope,
      memberships: project.manifest.memberships.map((source) => ({
        table: source.table,
        userColumn: source.user.column,
        scope: source.scope,
        idColumn: source.id.column,
      })),
    },
  };
}

/** The `member_<scope>_ids` helpers PermDock mode calls, as `schema.name`. */
export const entitlementHelpers = (permdock: KitPermdock): string[] => [
  `${permdock.schema}.member_${permdock.scope}_ids`,
  `${permdock.schema}.member_${permdock.scope}_ids_for`,
];
