import type { PresetCatalog } from "./catalog-types.ts";
import type { Preset } from "./fields.ts";

import { CORE_BLOCKS, INSTANCE_NAME } from "../config/instances.ts";
import { PRESET_CATALOG } from "./catalog.generated.ts";
import { resolvePreset } from "./resolve.ts";

export { CORE_BLOCKS as SINGLE_INSTANCE_BLOCKS };

/** Whether a preset can install `block` a second time, under another name. */
export function canAddInstance(block: string): boolean {
  return !CORE_BLOCKS.has(block);
}

/**
 * What `block` requires, at every access level: the dependencies `uses` must
 * name.
 */
export function blockRequires(
  block: string,
  catalog: PresetCatalog = PRESET_CATALOG,
): readonly string[] {
  const entry = catalog.blocks.find((each) => each.name === block);

  return [
    ...new Set([
      ...(entry?.requires ?? []),
      ...Object.values(entry?.requiresByAccess ?? {}).flat(),
    ]),
  ];
}

/** The blocks a preset installs, by name. */
export function installedBlocks(preset: Preset): ReadonlySet<string> {
  return new Set(resolvePreset(preset).blocks.map((block) => block.name));
}

/** One `preset.instances` entry. */
export type PresetInstance = NonNullable<Preset["instances"]>[string];

/** One of a block's entities that an instance can rename. */
export interface BlockEntity {
  readonly key: string;
  /** The logical table that holds it. */
  readonly table: string;
  readonly singular: string;
  /** A second instance of the block has to rename it. */
  readonly required: boolean;
}

/** An installed instance: the block's own one, or another named one. */
export interface BlockInstance {
  readonly name: string;
  readonly block: string;
}

const ENTITIES = new Map(
  PRESET_CATALOG.blocks.map((block) => [
    block.name,
    Object.entries(block.entities?.specs ?? {}).flatMap(
      ([key, spec]): BlockEntity[] =>
        spec.table === undefined || spec.global === true
          ? []
          : [
              {
                key,
                table: spec.table,
                singular: spec.singular,
                required: spec.primary === true || spec.subject !== undefined,
              },
            ],
    ),
  ]),
);

/**
 * The entities `block` lets an instance rename; the tenant is renamed by
 * `tenantName`.
 */
export function blockEntities(block: string): readonly BlockEntity[] {
  return ENTITIES.get(block) ?? [];
}

/** The block `instance` installs. */
export function instanceBlock(preset: Preset, instance: string): string {
  return preset.instances?.[instance]?.block ?? instance;
}

/**
 * Every instance the preset installs: each installed block under its own name,
 * then each `instances` entry that installs a block under another name.
 */
export function presetInstances(preset: Preset): readonly BlockInstance[] {
  return [
    ...resolvePreset(preset).blocks.map(({ name }) => ({ name, block: name })),
    ...Object.entries(preset.instances ?? {}).flatMap(([name, instance]) => {
      const block = instance.block ?? name;

      return block === name ? [] : [{ name, block }];
    }),
  ];
}

/** The instances of `block`, its own one first when the preset selects it. */
export function instancesOf(
  preset: Preset,
  block: string,
): readonly BlockInstance[] {
  return presetInstances(preset).filter((each) => each.block === block);
}

/** The name `instance` gives `entity`, or undefined when it keeps the default. */
export function entityName(
  preset: Preset,
  instance: string,
  entity: string,
): string | undefined {
  return preset.instances?.[instance]?.names?.[entity];
}

function withInstances(
  preset: Preset,
  instances: Readonly<Record<string, PresetInstance>>,
): Preset {
  if (Object.keys(instances).length > 0) {
    return { ...preset, instances };
  }

  const { instances: _instances, ...rest } = preset;

  return rest;
}

/** An instance without its empty `names`, `uses` or `on`. */
function compact(instance: PresetInstance): PresetInstance {
  const { names, uses, on, ...rest } = instance;

  return {
    ...rest,
    ...(names === undefined || Object.keys(names).length === 0
      ? {}
      : { names }),
    ...(uses === undefined || Object.keys(uses).length === 0 ? {} : { uses }),
    ...(on === undefined ||
    (Array.isArray(on) ? on.length === 0 : Object.keys(on).length === 0)
      ? {}
      : { on }),
  };
}

/**
 * The preset with `instance` naming `entity` `name`; undefined, or the entity's
 * default, goes back to the default. An entry left empty is dropped.
 */
export function withEntityName(
  preset: Preset,
  instance: string,
  entity: string,
  name: string | undefined,
): Preset {
  const block = instanceBlock(preset, instance);

  const fallback = blockEntities(block).find(
    (each) => each.key === entity,
  )?.singular;

  const current = preset.instances?.[instance] ?? {};
  const { [entity]: _previous, ...names } = current.names ?? {};

  const next = compact({
    ...current,
    names:
      name === undefined || name === fallback
        ? names
        : { ...names, [entity]: name },
  });

  const { [instance]: _instance, ...others } = preset.instances ?? {};

  return withInstances(
    preset,
    Object.keys(next).length === 0 ? others : { ...others, [instance]: next },
  );
}

/** Why `name` can't name a new instance, or undefined when it can. */
export function instanceNameProblem(
  preset: Preset,
  name: string,
): string | undefined {
  if (!INSTANCE_NAME.test(name)) {
    return "Start with a lowercase letter, then use letters, digits and hyphens.";
  }

  if (PRESET_CATALOG.blocks.some((block) => block.name === name)) {
    return `"${name}" is a block name. Choose another name.`;
  }

  if (presetInstances(preset).some((each) => each.name === name)) {
    return `"${name}" is already an instance. Choose another name.`;
  }

  return undefined;
}

/**
 * The preset with `name` set to `instance`: a new instance, or new settings for
 * one already there. `instance.block` defaults to `name`.
 */
export function withInstance(
  preset: Preset,
  name: string,
  instance: PresetInstance,
): Preset {
  const block = instance.block ?? name;

  const existing = instancesOf(preset, block).filter(
    (each) => each.name !== name,
  );

  const next = withInstances(preset, {
    ...preset.instances,
    [name]: compact(instance),
  });

  const [first] = existing;

  return existing.length === 1 && first !== undefined
    ? pinDependents(next, block, first.name, name)
    : next;
}

/**
 * Keeps the instances that required `block` on `target`, its only instance
 * until `added` joined it, so a second instance changes nothing they read.
 */
function pinDependents(
  preset: Preset,
  block: string,
  target: string,
  added: string,
): Preset {
  const instances = { ...preset.instances };

  for (const each of presetInstances(preset)) {
    const entry = instances[each.name] ?? {};

    if (
      each.name !== added &&
      blockRequires(each.block).includes(block) &&
      entry.uses?.[block] === undefined
    ) {
      instances[each.name] = {
        ...entry,
        uses: { ...entry.uses, [block]: target },
      };
    }
  }

  return withInstances(preset, instances);
}

/**
 * The preset without the instance `name`: its entry, the `uses` entries of
 * other instances that pointed at it, and the ones a dependency left with one
 * instance no longer needs. A block's own instance is removed by deselecting
 * the block instead.
 */
export function withoutInstance(preset: Preset, name: string): Preset {
  const { [name]: _removed, ...rest } = preset.instances ?? {};
  const remaining = presetInstances(withInstances(preset, rest));

  const single = (dependency: string): boolean =>
    remaining.filter((each) => each.block === dependency).length === 1;

  return withInstances(
    preset,
    Object.fromEntries(
      Object.entries(rest).flatMap(([key, instance]) => {
        const kept = compact({
          ...instance,
          uses: Object.fromEntries(
            Object.entries(instance.uses ?? {}).filter(
              ([dependency, target]) =>
                target !== name &&
                !(target === dependency && single(dependency)),
            ),
          ),
        });

        return Object.keys(kept).length === 0 ? [] : [[key, kept]];
      }),
    ),
  );
}
