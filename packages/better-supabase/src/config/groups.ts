import type { BetterSupabaseConfig, FlatConfig } from "./types/config.ts";

type Entries = Record<string, unknown>;

type Pairs = readonly (readonly [grouped: string, flat: string])[];

const isObject = (value: unknown): value is Entries =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const objectOr = (value: unknown): Entries => (isObject(value) ? value : {});

/** The flat keys each group holds. `gen` and `auth` also keep their own keys. */
export const CONFIG_GROUPS: Readonly<Record<string, readonly string[]>> = {
  database: [
    "source",
    "schemas",
    "sql",
    "seed",
    "expose",
    "buckets",
    "realtime",
    "topics",
    "vectorSearch",
  ],
  auth: ["claims", "authorization", "entitlements"],
  gen: [
    "output",
    "casing",
    "postgrestVersion",
    "recordTypes",
    "hooks",
    "tables",
    "json",
    "codecs",
    "relations",
    "sensitive",
    "storagePaths",
    "functions",
    "generators",
    "readSets",
  ],
  api: ["openapi", "specs"],
  tooling: ["doctor", "env", "keys", "skills", "scaffold"],
};

/** Top-level keys renamed by the regrouping: the grouped name, then the flat. */
export const RENAMED_CONFIG_KEYS: Pairs = [
  ["records", "subjects"],
  ["tables", "appTables"],
  ["adapters", "integrations"],
];

/** Keys renamed inside `blocks.<name>`: the grouped name, then the flat. */
export const RENAMED_BLOCK_KEYS: Pairs = [
  ["ownership", "mode"],
  ["owner", "scope"],
  ["names", "entities"],
  ["callbacks", "hooks"],
];

const OWNER: Pairs = [["owner", "scope"]];

/** A resolved block entry with the key names a config file writes. */
export function blockEntrySource(entry: object): Entries {
  const out: Entries = {};

  for (const [key, value] of Object.entries(entry)) {
    const pair = RENAMED_BLOCK_KEYS.find(([, flat]) => flat === key);
    out[pair === undefined ? key : pair[0]] = value;
  }

  return out;
}

function renameKeys(value: unknown, pairs: Pairs, back: boolean): unknown {
  if (!isObject(value)) {
    return value;
  }

  const out: Entries = {};

  for (const [key, entry] of Object.entries(value)) {
    const pair = pairs.find(
      ([grouped, flat]) => (back ? flat : grouped) === key,
    );

    out[pair === undefined ? key : back ? pair[0] : pair[1]] = entry;
  }

  return out;
}

function eachEntry(value: unknown, pairs: Pairs, back: boolean): unknown {
  if (!isObject(value)) {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value).map(([name, entry]) => [
      name,
      renameKeys(entry, pairs, back),
    ]),
  );
}

function organizationOf(organization: unknown, out: Entries): Entries {
  if (!isObject(organization)) {
    return {};
  }

  const { claim, ...rest } = organization;
  const patch: Entries = {};

  if (typeof claim === "string") {
    patch["claims"] = { ...objectOr(out["claims"]), tenant: claim };
  }

  if (Object.keys(rest).length > 0) {
    patch["organization"] = rest;
  }

  return patch;
}

/**
 * The grouped config in the flat shape `resolveConfig` reads: every group's
 * keys at the top level, `records`, `tables` and `adapters` under their flat
 * names, `auth.organization` as `claims.tenant` and `organization`, and the
 * renamed block and app table keys under their flat names.
 */
export function flattenConfig(config: BetterSupabaseConfig): FlatConfig {
  const source: Entries = { ...config };
  const out: Entries = {};

  for (const [key, value] of Object.entries(source)) {
    if (key in CONFIG_GROUPS) {
      continue;
    }

    const renamed = RENAMED_CONFIG_KEYS.find(([grouped]) => grouped === key);
    out[renamed === undefined ? key : renamed[1]] = value;
  }

  for (const [group, keys] of Object.entries(CONFIG_GROUPS)) {
    const entries = source[group];

    if (!isObject(entries)) {
      continue;
    }

    const own: Entries = {};

    for (const [key, value] of Object.entries(entries)) {
      if (keys.includes(key) || (group !== "gen" && group !== "auth")) {
        out[key] = value;
      } else {
        own[key] = value;
      }
    }

    if (group === "gen" && Object.keys(own).length > 0) {
      out["gen"] = own;
    } else if (group === "auth") {
      Object.assign(out, organizationOf(own["organization"], out));
    }
  }

  if (isObject(out["sql"])) {
    out["sql"] = renameKeys(out["sql"], OWNER, false);
  }

  if (out["appTables"] !== undefined) {
    out["appTables"] = eachEntry(out["appTables"], OWNER, false);
  }

  if (out["blocks"] !== undefined) {
    out["blocks"] = eachEntry(out["blocks"], RENAMED_BLOCK_KEYS, false);
  }

  return out;
}

const GROUP_OF = new Map<string, string>(
  Object.entries(CONFIG_GROUPS).flatMap(([group, keys]) =>
    keys.map((key): [string, string] => [key, group]),
  ),
);

const ENVIRONMENT_KEY = /^\$(?:development|production|test|ci)$/;

const GROUPED_KEYS = new Set([
  "database",
  "auth",
  "api",
  "tooling",
  "records",
  "adapters",
]);

/**
 * Whether a top-level `tables` is the generator overrides of a config written
 * before 0.15 rather than the app tables of a grouped one.
 */
export function hasFlatTables(keys: readonly string[]): boolean {
  return (
    keys.includes("appTables") || !keys.some((key) => GROUPED_KEYS.has(key))
  );
}

/**
 * Moves `claims.tenant`, the flat `organization` and the 0.14 tenant plugin's
 * column to `auth.organization`.
 */
function withOrganization(out: Entries, groups: Record<string, Entries>): void {
  const auth = groups["auth"];
  const claims = auth?.["claims"];

  if (auth !== undefined && isObject(claims) && "tenant" in claims) {
    const { tenant, ...rest } = claims;
    auth["organization"] = { claim: tenant };

    if (Object.keys(rest).length === 0) {
      delete auth["claims"];
    } else {
      auth["claims"] = rest;
    }
  }

  const flat = out["organization"];

  if (isObject(flat)) {
    delete out["organization"];

    const next = { ...groups["auth"] };
    next["organization"] = { ...objectOr(next["organization"]), ...flat };
    groups["auth"] = next;
  }

  const plugins = out["plugins"];

  if (!isObject(plugins) || !isObject(plugins["tenant"])) {
    return;
  }

  const column = plugins["tenant"]["column"];
  out["plugins"] = { ...plugins, tenant: true };

  if (typeof column === "string") {
    const next = { ...groups["auth"] };
    next["organization"] = { ...objectOr(next["organization"]), column };
    groups["auth"] = next;
  }
}

/** A flat config in the grouped shape: the inverse of `flattenConfig`. */
export function groupConfig(config: FlatConfig): BetterSupabaseConfig {
  return groupEntries(config);
}

/**
 * Any object with the keys of a config written before 0.15, grouped: the keys
 * it doesn't know stay where they are. `$env` blocks are grouped the same way.
 * The 0.15 codemod uses it for JSON configs.
 */
export function groupEntries(config: object): Entries {
  const out: Entries = {};
  const groups: Record<string, Entries> = {};
  const flatTables = hasFlatTables(Object.keys(config));

  for (const [key, value] of Object.entries(config)) {
    const group =
      key === "tables" && !flatTables ? undefined : GROUP_OF.get(key);

    const renamed = RENAMED_CONFIG_KEYS.find(([, flat]) => flat === key);

    if (key === "gen" && isObject(value)) {
      groups["gen"] = { ...value, ...groups["gen"] };
    } else if (key in CONFIG_GROUPS && isObject(value)) {
      groups[key] = { ...value, ...groups[key] };
    } else if (group !== undefined) {
      groups[group] = { ...groups[group], [key]: value };
    } else if (renamed !== undefined) {
      out[renamed[0]] = value;
    } else if (key === "$env" && isObject(value)) {
      out[key] = Object.fromEntries(
        Object.entries(value).map(([name, block]) => [
          name,
          isObject(block) ? groupEntries(block) : block,
        ]),
      );
    } else if (ENVIRONMENT_KEY.test(key) && isObject(value)) {
      out[key] = groupEntries(value);
    } else {
      out[key] = value;
    }
  }

  const database = groups["database"];

  if (database !== undefined && isObject(database["sql"])) {
    database["sql"] = renameKeys(database["sql"], OWNER, true);
  }

  withOrganization(out, groups);

  if (out["tables"] !== undefined && flatTables) {
    out["tables"] = eachEntry(out["tables"], OWNER, true);
  }

  if (out["blocks"] !== undefined) {
    out["blocks"] = eachEntry(out["blocks"], RENAMED_BLOCK_KEYS, true);
  }

  return { ...out, ...groups };
}
