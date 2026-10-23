import type { PresetCatalog } from "../preset/catalog-types.ts";
import type { AnyBlocksConfig, BlockConfig, InstanceOn } from "./blocks.ts";

import { PRESET_CATALOG } from "../preset/catalog.generated.ts";

/**
 * Blocks that install once: they hold the app's identity, tenancy, access and
 * plumbing, so a second copy would split what every other block reads.
 */
export const CORE_BLOCKS: ReadonlySet<string> = new Set([
  "api-keys",
  "audit",
  "created-by",
  "grants",
  "data-lifecycle",
  "entitlements",
  "flags",
  "field-encryption",
  "field-history",
  "guests",
  "idempotency",
  "invitations",
  "jsonb-schemas",
  "identities",
  "memberships",
  "mfa",
  "oauth-server",
  "organizations",
  "outbox",
  "permissions",
  "pgtap",
  "profiles",
  "queue",
  "rate-limit",
  "read-sets",
  "realtime-tables",
  "reserved-slugs",
  "rls-guard",
  "search",
  "security-events",
  "service-accounts",
  "sessions",
  "settings",
  "signing-keys",
  "sso",
  "subjects",
  "teams",
  "trash",
  "updated-at",
  "usage",
  "vector-search",
]);

/** One named install of a block. */
export interface ResolvedInstance {
  /** The key in `blocks`. */
  readonly name: string;
  /** The block it installs. */
  readonly block: string;
  /** The record types it attaches to; unset, every record type. */
  readonly on?: InstanceOn;
  /**
   * Each dependency block to the instance it resolves to, when that is not the
   * instance named after the block: what `uses` sets, and a dependency's only
   * instance when it has another name.
   */
  readonly uses: Readonly<Record<string, string>>;
  /** Its config, without `block`. */
  readonly config: BlockConfig;
}

const INSTANCE_NAME = /^[a-z][a-zA-Z0-9-]*$/;

/**
 * The prefix an instance gives the names its block's renames leave unchanged:
 * `hiring-pipelines` and `hiringPipelines` both give `hiring_pipelines`.
 */
export function instancePrefix(name: string): string {
  return name
    .replaceAll(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)
    .replaceAll("-", "_");
}

/** Whether `instance` installs its block under another name. */
export const isRenamedInstance = (instance: ResolvedInstance): boolean =>
  instance.name !== instance.block;

/** The blocks `block` may bind with `uses`: what it requires or works with. */
function dependenciesOf(
  block: string,
  catalog: PresetCatalog,
): {
  readonly requires: ReadonlySet<string>;
  readonly known: ReadonlySet<string>;
} {
  const entry = catalog.blocks.find((each) => each.name === block);

  const requires = new Set([
    ...(entry?.requires ?? []),
    ...Object.values(entry?.requiresByAccess ?? {}).flat(),
  ]);

  return {
    requires,
    known: new Set([...requires, ...(entry?.integrates ?? [])]),
  };
}

function instanceProblems(
  entries: readonly (readonly [string, BlockConfig])[],
  catalog: PresetCatalog,
): string[] {
  const blocks = new Set(catalog.blocks.map((block) => block.name));
  const byBlock = new Map<string, string[]>();

  for (const [name, entry] of entries) {
    const block = entry.block ?? name;
    byBlock.set(block, [...(byBlock.get(block) ?? []), name]);
  }

  const problems: string[] = [];

  for (const [name, entry] of entries) {
    if (!INSTANCE_NAME.test(name)) {
      problems.push(
        `blocks.${name}: an instance name starts with a lowercase letter and holds letters, digits and -.`,
      );
      continue;
    }

    if (entry.block !== undefined && !blocks.has(entry.block)) {
      problems.push(
        `blocks.${name}.block: "${entry.block}" is not a block. See \`better-supabase blocks list\`.`,
      );
      continue;
    }

    const block = entry.block ?? name;

    if (CORE_BLOCKS.has(block) && name !== block) {
      problems.push(
        `blocks.${name}: "${block}" is a core block and installs once, under its own name. Rename the key to "${block}".`,
      );
    }

    const { requires, known } = dependenciesOf(block, catalog);

    for (const [dependency, instance] of Object.entries(entry.uses ?? {})) {
      if (!known.has(dependency)) {
        problems.push(
          `blocks.${name}.uses.${dependency}: "${block}" doesn't use "${dependency}".`,
        );
      } else if (!(byBlock.get(dependency) ?? []).includes(instance)) {
        problems.push(
          `blocks.${name}.uses.${dependency}: "${instance}" is not an instance of "${dependency}".`,
        );
      }
    }

    for (const dependency of requires) {
      const installed = byBlock.get(dependency) ?? [];

      if (installed.length > 1 && entry.uses?.[dependency] === undefined) {
        problems.push(
          `blocks.${name}.uses.${dependency}: "${dependency}" is installed as ${installed.map((each) => `"${each}"`).join(" and ")}; name the one "${name}" uses.`,
        );
      }
    }
  }

  return problems;
}

function isNameList(
  blocks: AnyBlocksConfig | readonly string[],
): blocks is readonly string[] {
  return Array.isArray(blocks);
}

/**
 * The instances in `blocks`, keyed by instance name. A list of names installs
 * each block once under its own name. Throws one error that lists every
 * instance whose `block` is unknown, that renames or repeats a core block, or
 * whose `uses` doesn't name an installed instance of a dependency.
 */
export function resolveInstances(
  blocks: AnyBlocksConfig | readonly string[] | undefined,
  catalog: PresetCatalog = PRESET_CATALOG,
): Readonly<Record<string, ResolvedInstance>> {
  const entries: (readonly [string, BlockConfig])[] =
    blocks === undefined
      ? []
      : isNameList(blocks)
        ? blocks.map((name) => [name, {}] as const)
        : Object.entries(blocks).flatMap(([name, entry]) =>
            entry === undefined ? [] : [[name, entry] as const],
          );

  const problems = instanceProblems(entries, catalog);

  if (problems.length > 0) {
    throw new TypeError(problems.join("\n"));
  }

  const byBlock = new Map<string, string[]>();

  for (const [name, entry] of entries) {
    const block = entry.block ?? name;
    byBlock.set(block, [...(byBlock.get(block) ?? []), name]);
  }

  return Object.fromEntries(
    entries.map(([name, entry]) => {
      const block = entry.block ?? name;
      const { known } = dependenciesOf(block, catalog);

      const implied = [...known].flatMap((dependency) => {
        const installed = byBlock.get(dependency) ?? [];

        return installed.length === 1 && installed[0] !== dependency
          ? [[dependency, installed[0]!] as const]
          : [];
      });

      const uses = Object.fromEntries(
        [...implied, ...Object.entries(entry.uses ?? {})].filter(
          ([dependency, instance]) => instance !== dependency,
        ),
      );

      return [
        name,
        {
          name,
          block,
          ...(entry.on === undefined ? {} : { on: entry.on }),
          uses,
          config: withoutBlockKey(entry),
        },
      ];
    }),
  );
}

/**
 * `blocks` keyed by block name: the instances named after their block. The
 * other instances render on their own, from `instances`.
 */
export function blocksByName(
  instances: Readonly<Record<string, ResolvedInstance>>,
): AnyBlocksConfig {
  return Object.fromEntries(
    Object.values(instances)
      .filter((instance) => !isRenamedInstance(instance))
      .map((instance) => [instance.block, instance.config]),
  );
}

function withoutBlockKey<T extends BlockConfig>(entry: T): T {
  if (entry.block === undefined) {
    return entry;
  }

  const { block: _, ...rest } = entry;

  // SAFETY: dropping `block`, an optional key of T, leaves a valid T.
  return rest as T;
}
