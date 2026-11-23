import type {
  RestatedEntry,
  RestatedKind,
  ResolvedConfig,
} from "../config/index.ts";

import { renderBlocks, SQL_MODULES } from "../sql/index.ts";
import { withLayoutSession } from "./sql-layout.ts";
import { layoutFor } from "./sql/providers.ts";

interface Candidate {
  /** A block name, or a record type for `recordTypes` candidates. */
  readonly block: string;
  /** `blocks.<name>` entries and `recordTypes.<type>` entries. */
  readonly scope: "blocks" | "recordTypes";
  /** The keys under the entry, `["options", "a", "b"]`. */
  readonly keys: readonly (string | number)[];
}

/** The most renders a probe spends before it gives up and reports what it has. */
const MAX_RENDERS = 400;

/** An option nested deeper than this is data (steps, effects), not a default. */
const MAX_OPTION_DEPTH = 4;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The block entry sections the probe takes out one entry at a time. */
const SECTIONS = [
  "permissions",
  "options",
  "hooks",
  "tables",
  "columns",
  "api",
] as const;

/** The `on.<type>` keys the render may infer from the schema. */
const ON_KEYS: ReadonlySet<string> = new Set(["links", "column", "table"]);

/** The record type keys the render may derive. */
const TYPE_KEYS: ReadonlySet<string> = new Set(["idType", "table", "cascade"]);

/** The key a config file writes for a resolved block key. */
const FILE_KEYS: Readonly<Record<string, string>> = { hooks: "callbacks" };

/** The leaf keys of `value`; arrays of entries yield one candidate per element. */
function leaves(
  value: unknown,
  keys: readonly (string | number)[],
): (readonly (string | number)[])[] {
  if (value === undefined) {
    return [];
  }

  // The foreign keys the render infers go whole: a part of them is no entry.
  if (isRecord(value) && keys.at(-1) !== "links") {
    return Object.entries(value).flatMap(([key, child]) =>
      leaves(child, [...keys, key]),
    );
  }

  if (Array.isArray(value) && keys.at(-1) === "sameTenant") {
    return [keys, ...value.map((_, index) => [...keys, index] as const)];
  }

  return [keys];
}

/**
 * Whether the entry at `keys` could equal what the block uses without it. A
 * hook that keeps its name, a table that keeps its logical name and a column
 * that keeps the default name may; the rest cost a render for nothing.
 */
function plausible(
  module: string,
  entry: object,
  keys: readonly (string | number)[],
): boolean {
  const [section, first, second] = keys;
  const value = valueAt(entry, keys);

  switch (String(section)) {
    case "hooks": {
      return first === "schema" ? value === "public" : value === second;
    }

    case "tables": {
      return (
        value === null ||
        (typeof value === "string" &&
          value.slice(value.lastIndexOf(".") + 1) === first)
      );
    }

    case "columns": {
      const spec = SQL_MODULES[module]?.names?.tables[String(first)];

      return (
        value === null ||
        (typeof value === "string" &&
          typeof second === "string" &&
          spec?.columns[second] === value)
      );
    }

    default: {
      return true;
    }
  }
}

function valueAt(value: unknown, keys: readonly (string | number)[]): unknown {
  let current = value;

  for (const key of keys) {
    if (!isRecord(current) && !Array.isArray(current)) {
      return undefined;
    }

    // SAFETY: a record or an array is indexed by the key the path names.
    current = (current as Record<string | number, unknown>)[key];
  }

  return current;
}

/** The candidates: scalar facts a block's or a record type's config may restate. */
function candidatesOf(config: ResolvedConfig): Candidate[] {
  const blocks = config.blockNames.flatMap((block) => {
    const entry = config.blocks[block];

    if (entry === undefined) {
      return [];
    }

    const own = SECTIONS.flatMap((section) => {
      // A default the project's `sql.api` filled in is not in the config file.
      if (section === "api" && entry.api === config.sql.blockDefaults?.api) {
        return [];
      }

      return leaves(entry[section], [section]).filter(
        (keys) =>
          plausible(entry.block ?? block, entry, keys) &&
          (section !== "options" ||
            keys.length <= MAX_OPTION_DEPTH ||
            keys.includes("sameTenant")),
      );
    });

    const bound = leaves(entry.on, ["on"]).filter((keys) =>
      ON_KEYS.has(String(keys.at(-1))),
    );

    return [...own, ...bound].map((keys) => ({
      block,
      scope: "blocks" as const,
      keys,
    }));
  });

  const types = Object.keys(config.subjects).flatMap((type) =>
    leaves(config.subjects[type], [])
      .filter((keys) => TYPE_KEYS.has(String(keys.at(-1))))
      .map((keys) => ({ block: type, scope: "recordTypes" as const, keys })),
  );

  // The entries that most often equal a default go first, so the render cap
  // spends its renders on them before the options.
  const rank = (candidate: Candidate): number =>
    candidate.keys[0] === "options"
      ? 2
      : candidate.keys[0] === "permissions"
        ? 1
        : 0;

  return [...blocks, ...types].toSorted((a, b) => rank(a) - rank(b));
}

/** `value` without the entry at `keys`; empty parents are left alone. */
function without(value: unknown, keys: readonly (string | number)[]): unknown {
  const [head, ...rest] = keys;

  if (head === undefined) {
    return value;
  }

  if (Array.isArray(value) && typeof head === "number") {
    const list: unknown[] = value;

    return rest.length === 0
      ? list.filter((_, index) => index !== head)
      : list.map((child, index) =>
          index === head ? without(child, rest) : child,
        );
  }

  if (isRecord(value)) {
    if (rest.length === 0) {
      return Object.fromEntries(
        Object.entries(value).filter(([key]) => key !== head),
      );
    }

    return Object.fromEntries(
      Object.entries(value).map(([key, child]) => [
        key,
        key === head ? without(child, rest) : child,
      ]),
    );
  }

  return value;
}

/** `config` with every candidate in `removed` taken out of its entry. */
function patched(
  config: ResolvedConfig,
  removed: readonly Candidate[],
): ResolvedConfig {
  // Array elements go from the highest index first, so the rest stay valid.
  const order = (a: Candidate, b: Candidate): number => {
    const left = a.keys.at(-1);
    const right = b.keys.at(-1);

    return typeof left === "number" && typeof right === "number"
      ? right - left
      : 0;
  };

  const patch = <T extends object>(
    scope: Candidate["scope"],
    name: string,
    entry: T,
  ): T => {
    let result: unknown = entry;

    for (const candidate of removed
      .filter((each) => each.scope === scope && each.block === name)
      .toSorted(order)) {
      result = without(result, candidate.keys);
    }

    // SAFETY: `without` only drops keys, so the entry keeps its shape.
    return result as T;
  };

  return {
    ...config,
    blocks: Object.fromEntries(
      Object.entries(config.blocks).map(([name, entry]) => [
        name,
        entry === undefined ? entry : patch("blocks", name, entry),
      ]),
    ),
    instances: Object.fromEntries(
      Object.entries(config.instances).map(([name, instance]) => [
        name,
        { ...instance, config: patch("blocks", name, instance.config) },
      ]),
    ),
    subjects: Object.fromEntries(
      Object.entries(config.subjects).map(([type, entry]) => [
        type,
        patch("recordTypes", type, entry),
      ]),
    ),
  };
}

async function renderOf(
  config: ResolvedConfig,
): Promise<ReadonlyMap<string, string>> {
  const layout = await layoutFor(config, {}, config.blockNames);

  return new Map(
    renderBlocks(config.blockNames, layout).map((file) => [
      file.path,
      file.contents,
    ]),
  );
}

const sameRender = (
  a: ReadonlyMap<string, string>,
  b: ReadonlyMap<string, string>,
): boolean =>
  a.size === b.size && [...a].every(([path, text]) => b.get(path) === text);

const kindOf = (candidate: Candidate): RestatedKind => {
  if (candidate.scope === "recordTypes") {
    return "recordType";
  }

  switch (String(candidate.keys[0])) {
    case "permissions": {
      return "permission";
    }

    case "hooks": {
      return "hook";
    }

    case "tables": {
      return "table";
    }

    case "columns": {
      return "column";
    }

    case "api": {
      return "api";
    }

    case "on": {
      return "binding";
    }

    default: {
      return "option";
    }
  }
};

const pathOf = (candidate: Candidate): string =>
  candidate.keys.reduce<string>(
    (path, key, index) =>
      typeof key === "number"
        ? `${path}[${String(key)}]`
        : `${path}.${index === 0 && candidate.scope === "blocks" ? (FILE_KEYS[key] ?? key) : key}`,
    `${candidate.scope}.${candidate.block}`,
  );

const reasonOf = (candidate: Candidate): string => {
  if (candidate.scope === "recordTypes") {
    return "is the value the block derives without it";
  }

  switch (String(candidate.keys[0])) {
    case "on": {
      return "is the one the schema's foreign keys give";
    }

    case "permissions": {
      return "names the key the block would use anyway";
    }

    case "hooks": {
      return "names the hook function the block looks up anyway";
    }

    case "tables":
    case "columns": {
      return "names the table or column the catalog gives without it";
    }

    case "api": {
      return "equals the exposure the block gets without it";
    }

    default: {
      return candidate.keys.at(-1) === "sameTenant" ||
        typeof candidate.keys.at(-1) === "number"
        ? "equals the entry the block derives from the schema"
        : "equals the option's default";
    }
  }
};

/**
 * The `permissions` and `options` entries of the installed blocks that equal
 * their default: a render without the entry gives the same files. It removes
 * the whole set, and splits the set until each survivor is a single entry, so a
 * clean config costs one render. It stops after a fixed number of renders and
 * reports what it found. `budgetMs` also stops it after that much time, so
 * doctor stays fast on a large project; `codemod config --prune` has no
 * budget.
 */
export async function probeRestated(
  config: ResolvedConfig,
  options: { readonly budgetMs?: number } = {},
): Promise<RestatedEntry[]> {
  return withLayoutSession(() => probeWithin(config, options.budgetMs));
}

async function probeWithin(
  config: ResolvedConfig,
  budgetMs: number | undefined,
): Promise<RestatedEntry[]> {
  const deadline = budgetMs === undefined ? undefined : Date.now() + budgetMs;
  const base = await renderOf(config);
  const found: Candidate[] = [];
  let renders = 0;

  const unchanged = async (group: readonly Candidate[]): Promise<boolean> => {
    renders += 1;

    // A removal the render refuses (a column without its table) is not restated.
    try {
      return sameRender(base, await renderOf(patched(config, group)));
    } catch {
      return false;
    }
  };

  const search = async (group: readonly Candidate[]): Promise<void> => {
    if (
      group.length === 0 ||
      renders >= MAX_RENDERS ||
      (deadline !== undefined && Date.now() > deadline)
    ) {
      return;
    }

    if (await unchanged(group)) {
      found.push(...group);

      return;
    }

    if (group.length === 1) {
      return;
    }

    const half = Math.ceil(group.length / 2);
    await search(group.slice(0, half));
    await search(group.slice(half));
  };

  await search(candidatesOf(config));

  const entries = found.map((candidate) => ({
    kind: kindOf(candidate),
    path: pathOf(candidate),
    reason: reasonOf(candidate),
    value: undefined,
  }));

  // An element of an array that goes whole is not reported again.
  return entries.filter(
    (entry) =>
      !entries.some(
        (other) => other !== entry && entry.path.startsWith(`${other.path}[`),
      ),
  );
}

/** `structural` entries, then the probed ones whose path they do not name. */
export function mergeRestated(
  structural: readonly RestatedEntry[],
  probed: readonly RestatedEntry[],
): RestatedEntry[] {
  const named = new Set(structural.map((entry) => entry.path));

  return [...structural, ...probed.filter((entry) => !named.has(entry.path))];
}
