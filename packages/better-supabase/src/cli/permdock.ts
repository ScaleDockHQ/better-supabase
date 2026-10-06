import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type {
  BlockAccessPermdock,
  BlockIdType,
  BlockPermdock,
  BlockPermissionKey,
  PermdockCatalog,
  PermdockKeyStatus,
} from "../sql/index.ts";

import {
  BLOCK_ID_TYPES,
  blockIdType,
  permdockKeyStatus,
} from "../sql/index.ts";

const PERMDOCK_CONFIGS = [
  "permdock.config.ts",
  "permdock.config.mts",
  "permdock.config.js",
  "permdock.config.mjs",
] as const;

/** The PermDock config file in `root`, if there is one. */
function permdockConfig(root: string): string | undefined {
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
    /** The claim PermDock's helpers read the active tenant from. */
    readonly tenantClaim?: string;
    readonly scopes: readonly {
      readonly name: string;
      /** The id's Postgres type; missing means unknown. */
      readonly type?: string;
      /** The parent scope; the root scope has none. */
      readonly within?: string;
    }[];
    readonly helpers: readonly ManifestHelper[];
    /**
     * The tables `member_<scope>_ids_for` reads. Missing in manifests from a
     * PermDock that didn't write it; the hook's `memberships` stand in.
     */
    readonly memberships?: readonly ManifestMembership[];
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
  /** The catalog's keys and their `rowConditions` flags, when it could be read. */
  readonly catalog?: PermdockCatalog;
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
  if (isRecord(rls) && rls["mode"] !== "jwt" && rls["mode"] !== "database") {
    throw new TypeError(
      `rls.mode ${JSON.stringify(rls["mode"])} is not supported (this release reads "jwt" and "database")`,
    );
  }
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
            ...(isString(rls["tenantClaim"])
              ? { tenantClaim: rls["tenantClaim"] }
              : {}),
            scopes: (Array.isArray(rls["scopes"]) ? rls["scopes"] : []).flatMap(
              (scope) =>
                isRecord(scope) && isString(scope["name"])
                  ? [
                      {
                        name: scope["name"],
                        ...(isString(scope["type"])
                          ? { type: scope["type"] }
                          : {}),
                        ...(isString(scope["within"])
                          ? { within: scope["within"] }
                          : {}),
                      },
                    ]
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
            ...(Array.isArray(rls["memberships"])
              ? {
                  memberships: rls["memberships"].flatMap((entry) => {
                    const parsed = membership(entry);
                    return parsed ? [parsed] : [];
                  }),
                }
              : {}),
          },
        }
      : {}),
    decidingColumns: strings(json["decidingColumns"]),
  };
}

/**
 * The keys of a parsed `permissions.catalog.json`, each with its scope and
 * its `rowConditions` flag when it is a boolean. A non-boolean flag is
 * dropped, so `permdockKeyStatus` reads the key as unknown. Throws unless
 * the catalog is version 1.
 */
export function parseCatalog(json: unknown): PermdockCatalog {
  if (!isRecord(json) || !Array.isArray(json["permissions"]))
    throw new TypeError("has no permissions array");
  if (json["version"] !== 1) {
    throw new TypeError(
      `version ${String(json["version"])} is not supported (this release reads version 1)`,
    );
  }
  return {
    permissions: json["permissions"].flatMap((permission) => {
      if (!isRecord(permission) || !isString(permission["key"])) return [];
      const flag = permission["rowConditions"];
      const scope = permission["scope"];
      return [
        {
          key: permission["key"],
          ...(typeof flag === "boolean" ? { rowConditions: flag } : {}),
          ...(isString(scope) ? { scope } : {}),
        },
      ];
    }),
  };
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
  let catalog: PermdockCatalog | undefined;
  if ("json" in catalogFile) {
    try {
      catalog = parseCatalog(catalogFile.json);
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
    ...(catalog ? { catalog } : {}),
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

/** How the `entitlements` SQL module finds memberships. */
export type EntitlementsMode =
  | { readonly kind: "tenant" }
  | { readonly kind: "permdock"; readonly permdock: BlockPermdock }
  | { readonly kind: "invalid"; readonly problem: string };

/** Who resolves a PermDock scope, for the messages `manifestScope` writes. */
interface ScopeReader {
  /** `the entitlements module`, `the access model`. */
  readonly subject: string;
  /** What the reader calls: `membership helpers`, `permission helpers`. */
  readonly helpers: string;
  /** The config key with `{ scope }`: `entitlements.permdock`. */
  readonly setting: string;
  /** How to stop using PermDock here, ending the sentence. */
  readonly optOut: string;
}

type ManifestScope =
  | {
      readonly kind: "ok";
      readonly manifest: PermdockManifest;
      readonly rls: NonNullable<PermdockManifest["rls"]>;
      readonly scope: string;
      readonly idType: BlockIdType;
    }
  | { readonly kind: "invalid"; readonly problem: string };

/**
 * The PermDock scope tenants are: `explicit`, which must be one of the
 * manifest's `rls.scopes`, else the one scope without `within`. A missing or
 * unreadable manifest, no `rls` block, no root scope or several, and a scope
 * without a type this block renders are invalid rather than a guess.
 */
function manifestScope(
  project: PermdockProject,
  explicit: string | undefined,
  reader: ScopeReader,
): ManifestScope {
  const { subject, helpers, setting, optOut } = reader;
  if (!project.manifest) {
    const problem = project.problems.find((entry) =>
      entry.startsWith(project.manifestPath),
    );
    return {
      kind: "invalid",
      problem: problem
        ? `Could not read PermDock's manifest: ${problem}. Run \`permdock supabase inspect --out\` with a current PermDock, ${optOut}`
        : `${permdockSource(project)} is a PermDock project, but there is no ${project.manifestPath}. Run \`permdock supabase inspect --out\`, ${optOut}`,
    };
  }
  const rls = project.manifest.rls;
  if (!rls) {
    return {
      kind: "invalid",
      problem: `${project.manifestPath} has no rls block, so ${subject} can't find PermDock's ${helpers}. Run \`permdock rls generate\`, then \`permdock supabase inspect --out\`, ${optOut}`,
    };
  }
  const names = rls.scopes.map((scope) => scope.name).join(", ") || "none";
  let scope: string;
  if (explicit === undefined) {
    const roots = rls.scopes.filter((entry) => entry.within === undefined);
    if (roots.length !== 1) {
      return {
        kind: "invalid",
        problem: `${project.manifestPath} has no single root scope (${roots.map((entry) => entry.name).join(", ") || "none"}), so ${subject} can't tell which scope tenants are. Set ${setting}: { scope } to one of ${names}.`,
      };
    }
    scope = roots[0]!.name;
  } else {
    scope = explicit;
    if (!rls.scopes.some((entry) => entry.name === scope)) {
      return {
        kind: "invalid",
        problem: `${setting}.scope is "${scope}", but ${project.manifestPath} has the scopes ${names}. Set ${setting}: { scope } to one of them, or remove it to use the root scope.`,
      };
    }
  }
  const declared = rls.scopes.find((entry) => entry.name === scope)?.type;
  if (declared === undefined) {
    return {
      kind: "invalid",
      problem: `${project.manifestPath} gives scope "${scope}" no type, so ${subject} can't tell its id type. Run \`permdock supabase inspect --out\` with a current PermDock.`,
    };
  }
  const idType = blockIdType(declared);
  if (idType === undefined) {
    return {
      kind: "invalid",
      problem: `${project.manifestPath} gives scope "${scope}" the type ${declared}, but ${subject} renders only ${BLOCK_ID_TYPES.join(", ").replace(/, (?=[^,]*$)/, " or ")} ids.`,
    };
  }
  return { kind: "ok", manifest: project.manifest, rls, scope, idType };
}

/**
 * The membership tables PermDock's `member_<scope>_ids_for` reads for
 * `scope`: the manifest's `rls.memberships` that can cover it (a scope
 * column, or a fixed scope equal to `scope`). A manifest from a PermDock
 * without `rls.memberships` falls back to the hook's sources.
 */
export function scopeMemberships(
  manifest: PermdockManifest,
  scope: string,
): {
  readonly sources: readonly ManifestMembership[];
  readonly from: "rls" | "hook";
} {
  const rls = manifest.rls?.memberships;
  return {
    sources: (rls ?? manifest.memberships).filter(
      (source) => !("value" in source.scope) || source.scope.value === scope,
    ),
    from: rls === undefined ? "hook" : "rls",
  };
}

/**
 * PermDock mode, when the project uses PermDock and `entitlements.permdock`
 * is not `false`. The scope is `entitlements.permdock.scope`, which must be
 * one of the manifest's `rls.scopes`, else the one scope without `within`.
 * No root scope, or more than one, is invalid rather than a guess. A
 * PermDock project without a readable manifest or without its `rls` block
 * is invalid too, so the module never falls back to `tenant` on its own.
 * Memberships come from `rls.memberships`, the tables PermDock's helpers
 * read, and from the hook's sources only when the manifest has none.
 */
export function entitlementsMode(
  config: Pick<ResolvedConfig, "entitlements">,
  project: PermdockProject | undefined,
): EntitlementsMode {
  const setting = config.entitlements.permdock;
  if (setting === false || !project) return { kind: "tenant" };
  const chosen = manifestScope(project, setting.scope, {
    subject: "the entitlements module",
    helpers: "membership helpers",
    setting: "entitlements.permdock",
    optOut:
      "or set entitlements.permdock: false to keep the tenant module's memberships.",
  });
  if (chosen.kind === "invalid") return chosen;
  return {
    kind: "permdock",
    permdock: {
      schema: chosen.rls.schema,
      scope: chosen.scope,
      idType: chosen.idType,
      memberships: scopeMemberships(chosen.manifest, chosen.scope).sources.map(
        (source) => ({
          table: source.table,
          userColumn: source.user.column,
          scope: source.scope,
          idColumn: source.id.column,
        }),
      ),
    },
  };
}

/** How the `access` module's `permdock` model reaches PermDock's helpers. */
export type AccessPermdockMode =
  | { readonly kind: "off" }
  | { readonly kind: "permdock"; readonly access: BlockAccessPermdock }
  | { readonly kind: "invalid"; readonly problem: string };

/**
 * The `permdock` access model's helpers, read from the manifest whatever
 * `entitlements` says: `rls.schema`, the root scope (or
 * `blocks.access.permdock.scope`, which the manifest must declare) and that
 * scope's id type. `off` when another model is chosen. Without a PermDock
 * project or a usable manifest the model is invalid, never a default.
 */
export function accessPermdockMode(
  config: Pick<ResolvedConfig, "blocks">,
  project: PermdockProject | undefined,
): AccessPermdockMode {
  const access = config.blocks.access;
  if (access?.model !== "permdock") return { kind: "off" };
  const optOut = "or choose another blocks.access.model.";
  if (!project) {
    return {
      kind: "invalid",
      problem: `blocks.access.model is "permdock", but there is no PermDock project here (no permdock.config.ts and no manifest). Run \`permdock supabase inspect --out\` to write the manifest, ${optOut}`,
    };
  }
  const chosen = manifestScope(project, access.permdock?.scope, {
    subject: "the permdock access model",
    helpers: "permission helpers",
    setting: "blocks.access.permdock",
    optOut,
  });
  if (chosen.kind === "invalid") return chosen;
  const schema = access.permdock?.schema;
  if (schema !== undefined && schema !== chosen.rls.schema) {
    return {
      kind: "invalid",
      problem: `blocks.access.permdock.schema is "${schema}", but ${project.manifestPath} puts PermDock's helpers in "${chosen.rls.schema}". Set it to "${chosen.rls.schema}", or remove it to use the manifest's.`,
    };
  }
  const idType =
    access.idType === undefined ? undefined : blockIdType(access.idType);
  if (idType !== undefined && idType !== chosen.idType) {
    return {
      kind: "invalid",
      problem: `blocks.access.idType is "${access.idType}", but ${project.manifestPath} gives scope "${chosen.scope}" the type ${chosen.idType}. Set blocks.access.idType to "${chosen.idType}", or remove it to use the manifest's.`,
    };
  }
  return {
    kind: "permdock",
    access: {
      schema: chosen.rls.schema,
      scope: chosen.scope,
      idType: chosen.idType,
    },
  };
}

const ROW_CONDITIONS_FIX =
  "Use the policies `permdock rls generate` writes for it, or a permission whose catalog entry has rowConditions: false.";
const REGENERATE_FIX =
  "Regenerate it with a current `permdock catalog`, which writes rowConditions for every permission.";

/**
 * Why the SQL helpers can't be trusted with `key`, or `undefined` when the
 * catalog marks it `rowConditions: false`. An entry without the flag and a
 * key the catalog doesn't list are unknown, so they count as unsafe.
 */
export function unsafeKey(
  catalog: PermdockCatalog,
  key: string,
  catalogPath: string,
):
  | {
      readonly status: Exclude<PermdockKeyStatus, "scope-only">;
      readonly reason: string;
      readonly fix: string;
    }
  | undefined {
  const status = permdockKeyStatus(catalog, key);
  switch (status) {
    case "scope-only":
      return undefined;
    case "row-conditions":
      return {
        status,
        reason: `has row conditions in ${catalogPath}`,
        fix: ROW_CONDITIONS_FIX,
      };
    case "no-flag":
      return {
        status,
        reason: `has no rowConditions flag in ${catalogPath}, so whether it has row conditions is unknown`,
        fix: REGENERATE_FIX,
      };
    case "missing":
      return {
        status,
        reason: `is not in ${catalogPath}`,
        fix: REGENERATE_FIX,
      };
    default: {
      const unreachable: never = status;
      return unreachable;
    }
  }
}

/** A block permission key PermDock's helpers can't answer for fully, or a catalog that can't tell. */
export interface BlockKeyProblem {
  /** `blocks.<module>.permissions.<action>`, or the catalog path. */
  readonly target: string;
  readonly message: string;
}

/**
 * Checks the keys the SQL modules pass to PermDock's helpers against
 * `permissions.catalog.json`, with the statuses bucket policies use: only
 * `rowConditions: false` passes. A missing or unreadable catalog is a
 * problem too, since every key is then unknown.
 */
export function blockKeyProblems(
  project: PermdockProject,
  keys: readonly BlockPermissionKey[],
  access: BlockAccessPermdock,
): BlockKeyProblem[] {
  if (keys.length === 0) return [];
  const catalog = project.catalog;
  if (!catalog) {
    const unreadable = project.problems.find((problem) =>
      problem.startsWith(project.catalogPath),
    );
    return [
      {
        target: project.catalogPath,
        message: unreadable
          ? `Could not read PermDock's catalog: ${unreadable}. The permdock access model passes ${keys.length} block permission keys to PermDock's helpers, so whether they have row conditions is unknown. Run \`permdock catalog\` with a current PermDock.`
          : `The permdock access model passes ${keys.length} block permission keys to PermDock's helpers, but there is no ${project.catalogPath}, so whether they have row conditions is unknown. Run \`permdock catalog\`, or set permdock.catalog in the config.`,
      },
    ];
  }
  return keys.flatMap((entry): BlockKeyProblem[] => {
    const problem = unsafeKey(catalog, entry.key, project.catalogPath);
    if (!problem) return [];
    const helper =
      entry.scope === "platform"
        ? `${access.schema}.permdock_has`
        : `${access.schema}.permitted_${access.scope}_ids`;
    const setting = `blocks.${entry.module}.permissions.${entry.action}`;
    const fix =
      problem.status === "row-conditions"
        ? `PermDock's SQL helpers check role and scope, not row conditions, so the module would grant it everywhere in the scope. Set ${setting} to a permission whose catalog entry has rowConditions: false.`
        : `${problem.fix} If PermDock doesn't define it, set ${setting} to a key the catalog lists.`;
    return [
      {
        target: setting,
        message: `The ${entry.module} module checks "${entry.key}" (${entry.action}) with ${helper}, but it ${problem.reason}. ${fix}`,
      },
    ];
  });
}

/** A helper the `permdock` access model calls, as `schema.name`, and the role it runs as. */
export const accessRequirements = (
  access: BlockAccessPermdock,
): readonly { readonly helper: string; readonly role: "authenticated" }[] => [
  {
    helper: `${access.schema}.permitted_${access.scope}_ids`,
    role: "authenticated",
  },
  { helper: `${access.schema}.permdock_has`, role: "authenticated" },
];

/** A helper PermDock mode calls (`schema.name`), the block function that calls it and the role it runs as. */
export interface EntitlementRequirement {
  readonly kind: "member" | "member-for";
  readonly helper: string;
  readonly caller: string;
  readonly role: "authenticated" | "supabase_auth_admin";
}

/**
 * The helpers the `entitlements` module calls for the chosen scope:
 * `member_<scope>_ids` from `has_entitlement` as `authenticated`, and
 * `member_<scope>_ids_for` from `feature_claims`, which PermDock's hook runs
 * as `supabase_auth_admin`.
 */
export const entitlementRequirements = (
  permdock: BlockPermdock,
): readonly EntitlementRequirement[] => [
  {
    kind: "member",
    helper: `${permdock.schema}.member_${permdock.scope}_ids`,
    caller: "has_entitlement",
    role: "authenticated",
  },
  {
    kind: "member-for",
    helper: `${permdock.schema}.member_${permdock.scope}_ids_for`,
    caller: "feature_claims",
    role: "supabase_auth_admin",
  },
];
