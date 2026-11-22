import type { RestatedEntry, ResolvedConfig } from "../config/index.ts";

import { renderBlocks } from "../sql/index.ts";
import { withLayoutSession } from "./sql-layout.ts";
import { layoutFor } from "./sql/providers.ts";

interface Candidate {
  readonly block: string;
  /** The keys under the block entry, `["options", "a", "b"]`. */
  readonly keys: readonly (string | number)[];
}

/** The most renders a probe spends before it gives up and reports what it has. */
const MAX_RENDERS = 400;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The `on.<type>` keys the render infers from the schema's foreign keys. */
const INFERRED_KEYS = ["links", "column"] as const;

/** The leaf keys of `value`; arrays of entries yield one candidate per element. */
function leaves(
  value: unknown,
  keys: readonly (string | number)[],
): (readonly (string | number)[])[] {
  if (value === undefined) {
    return [];
  }

  if (isRecord(value)) {
    return Object.entries(value).flatMap(([key, child]) =>
      leaves(child, [...keys, key]),
    );
  }

  if (Array.isArray(value) && keys.at(-1) === "sameTenant") {
    return [keys, ...value.map((_, index) => [...keys, index] as const)];
  }

  return [keys];
}

/** The candidates: scalar facts a block's config may restate. */
function candidatesOf(config: ResolvedConfig): Candidate[] {
  return config.blockNames.flatMap((block) => {
    const entry = config.blocks[block];

    if (entry === undefined) {
      return [];
    }

    const bound = isRecord(entry.on)
      ? Object.entries(entry.on).flatMap(([type, each]) =>
          isRecord(each)
            ? INFERRED_KEYS.filter((key) => each[key] !== undefined).map(
                (key) => ({ block, keys: ["on", type, key] }),
              )
            : [],
        )
      : [];

    return [
      ...(["permissions", "options"] as const).flatMap((section) =>
        leaves(entry[section], [section]).map((keys) => ({ block, keys })),
      ),
      ...bound,
    ];
  });
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

/** `config` with every candidate in `removed` taken out of its block entry. */
function patched(
  config: ResolvedConfig,
  removed: readonly Candidate[],
): ResolvedConfig {
  const patch = <T extends object>(name: string, entry: T): T => {
    // Removing array elements from the highest index first keeps the rest valid.
    const mine = removed
      .filter((candidate) => candidate.block === name)
      .toSorted((a, b) => b.keys.length - a.keys.length);

    let result: unknown = entry;

    for (const candidate of mine.toSorted((a, b) => {
      const left = a.keys.at(-1);
      const right = b.keys.at(-1);

      return typeof left === "number" && typeof right === "number"
        ? right - left
        : 0;
    })) {
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
        entry === undefined ? entry : patch(name, entry),
      ]),
    ),
    instances: Object.fromEntries(
      Object.entries(config.instances).map(([name, instance]) => [
        name,
        { ...instance, config: patch(name, instance.config) },
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

const pathOf = (candidate: Candidate): string =>
  candidate.keys.reduce<string>(
    (path, key) =>
      typeof key === "number" ? `${path}[${String(key)}]` : `${path}.${key}`,
    `blocks.${candidate.block}`,
  );

const reasonOf = (candidate: Candidate): string =>
  candidate.keys[0] === "on"
    ? "is the one the schema's foreign keys give"
    : candidate.keys[0] === "permissions"
      ? "names the key the block would use anyway"
      : candidate.keys.at(-1) === "sameTenant" ||
          typeof candidate.keys.at(-1) === "number"
        ? "equals the entry the block derives from the schema"
        : "equals the option's default";

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
    kind:
      candidate.keys[0] === "permissions"
        ? ("permission" as const)
        : ("option" as const),
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
