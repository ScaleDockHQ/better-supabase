import type { EntitySeedJson } from "./entity-ui.ts";

/** The id of a row that the page of `entity` seeds, found by its name. */
export interface EntitySeedRef {
  readonly $seedRef: { readonly entity: string; readonly name: string };
}

/** A day, counted from the day the seed runs (negative is in the past). */
export type EntitySeedDate = { readonly $seedDate: number };

/**
 * Names a row that another page seeds, in a `seed.rows` value. `gen` records
 * the dependency and a runner inserts that page first, then replaces the marker
 * with the id of the row whose first identity column (its name) is `name`.
 */
export const seedRef = (entity: string, name: string): EntitySeedRef => ({
  $seedRef: { entity, name },
});

/**
 * A date relative to the day the seed runs, so a deal's close date or a
 * contract's end does not age. A runner replaces it with `YYYY-MM-DD`.
 */
export const seedDate = (days: number): EntitySeedDate => ({ $seedDate: days });

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The ref a value is, when it is the marker `seedRef` returns. */
export const asSeedRef = (value: unknown): EntitySeedRef | undefined => {
  if (!isRecord(value) || Object.keys(value).length !== 1) {
    return;
  }

  const ref = value["$seedRef"];

  return isRecord(ref) &&
    typeof ref["entity"] === "string" &&
    typeof ref["name"] === "string"
    ? { $seedRef: { entity: ref["entity"], name: ref["name"] } }
    : undefined;
};

/** The days a value is, when it is the marker `seedDate` returns. */
const asSeedDate = (value: unknown): EntitySeedDate | undefined => {
  if (!isRecord(value) || Object.keys(value).length !== 1) {
    return;
  }

  const days = value["$seedDate"];

  return typeof days === "number" ? { $seedDate: days } : undefined;
};

/** Every ref in a value, in order of use. */
export const seedRefs = (value: unknown): readonly EntitySeedRef[] => {
  const found: EntitySeedRef[] = [];

  const walk = (node: unknown): void => {
    const ref = asSeedRef(node);

    if (ref !== undefined) {
      found.push(ref);
    } else if (Array.isArray(node)) {
      for (const item of node) {
        walk(item);
      }
    } else if (isRecord(node)) {
      for (const item of Object.values(node)) {
        walk(item);
      }
    }
  };

  walk(value);

  return found;
};

/** Every entity a value refers to, once, in order of first use. */
export const seedRefEntities = (value: unknown): readonly string[] => [
  ...new Set(seedRefs(value).map((ref) => ref.$seedRef.entity)),
];

export interface SeedResolver {
  /** The id of the row of `entity` named `name`. */
  ref(entity: string, name: string): string;
  /** The day the seed runs. */
  readonly today: Date;
}

const DAY = 86_400_000;

/**
 * The value with its markers replaced: a ref by the id the resolver finds, a
 * date by its `YYYY-MM-DD`. Everything else is returned as it is.
 */
export const resolveSeedValue = (
  value: EntitySeedJson,
  resolver: SeedResolver,
): EntitySeedJson => {
  const ref = asSeedRef(value);

  if (ref !== undefined) {
    return resolver.ref(ref.$seedRef.entity, ref.$seedRef.name);
  }

  const date = asSeedDate(value);

  if (date !== undefined) {
    return new Date(resolver.today.getTime() + date.$seedDate * DAY)
      .toISOString()
      .slice(0, 10);
  }

  if (Array.isArray(value)) {
    return value.map((item: EntitySeedJson) =>
      resolveSeedValue(item, resolver),
    );
  }

  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]: [string, EntitySeedJson]) => [
        key,
        resolveSeedValue(item, resolver),
      ]),
    );
  }

  return value;
};

/**
 * The seeds ordered so a page's `dependsOn` entities come first; seeds with no
 * dependency keep their order. A dependency on an entity not in `seeds` and a
 * cycle throw.
 */
export const orderSeeds = <
  T extends {
    readonly entity: string;
    readonly dependsOn?: readonly string[] | undefined;
  },
>(
  seeds: readonly T[],
): readonly T[] => {
  const byEntity = new Map(seeds.map((seed) => [seed.entity, seed]));
  const done = new Set<string>();
  const visiting: string[] = [];
  const ordered: T[] = [];

  const visit = (seed: T): void => {
    if (done.has(seed.entity)) {
      return;
    }

    if (visiting.includes(seed.entity)) {
      throw new Error(
        `Seeds depend on each other: ${[...visiting, seed.entity].join(" > ")}.`,
      );
    }

    visiting.push(seed.entity);

    for (const entity of seed.dependsOn ?? []) {
      const dependency = byEntity.get(entity);

      if (dependency === undefined) {
        throw new Error(
          `The ${seed.entity} seed refers to ${entity}, which has no seed.`,
        );
      }

      visit(dependency);
    }

    visiting.pop();
    done.add(seed.entity);
    ordered.push(seed);
  };

  for (const seed of seeds) {
    visit(seed);
  }

  return ordered;
};
