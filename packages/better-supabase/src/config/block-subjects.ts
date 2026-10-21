import type { EntityNoun, EntityRename } from "../core/entity-naming.ts";
import type { ModuleNames } from "../sql/context.ts";
import type { AnyBlocksConfig } from "./blocks.ts";
import type { SubjectConfig, SubjectsConfig } from "./types/subjects.ts";

import { PRESET_CATALOG } from "../preset/catalog.generated.ts";
import { resolveNames } from "../sql/resolved-names.ts";
import { resolveModule } from "./blocks.ts";

const CATALOG = new Map(
  PRESET_CATALOG.blocks.map((block) => [block.name, block]),
);

/** `names` and every block they require, from the catalog, in order. */
function withRequired(names: readonly string[]): readonly string[] {
  const found = new Set<string>();

  const add = (name: string): void => {
    if (found.has(name)) {
      return;
    }

    found.add(name);

    for (const required of CATALOG.get(name)?.requires ?? []) {
      add(required);
    }
  };

  for (const name of names) {
    add(name);
  }

  return [...found];
}

const PLACEHOLDER = /\{([^{}]*)\}/g;

/** One installed module's names under `blocks`, from the catalog. */
function catalogNames(module: string): ModuleNames | undefined {
  const entities = CATALOG.get(module)?.entities;

  return entities === undefined
    ? undefined
    : { tables: entities.tables, entities: entities.specs };
}

/**
 * The entities `blocks.<module>.entities` gives a new name, such as `work_item`
 * to `task`, for the block's TypeScript client (`blocks.generated.ts`). Empty
 * when the module renames none.
 */
export function blockEntityRenames(
  module: string,
  blocks: AnyBlocksConfig,
): readonly EntityRename[] {
  const names = catalogNames(module);

  if (names === undefined) {
    return [];
  }

  return Object.values(resolveNames(module, names, blocks).entities)
    .filter(
      (entity) =>
        !entity.global &&
        (entity.to.singular !== entity.from.singular ||
          entity.to.plural !== entity.from.plural),
    )
    .map((entity) => ({ from: entity.from, to: entity.to }));
}

/** One installed block's entity under the name the config gives it. */
export interface BlockEntity {
  /** The entity's key in the block's manifest: its default singular noun. */
  readonly key: string;
  readonly from: EntityNoun;
  readonly to: EntityNoun;
  readonly primary: boolean;
  /**
   * The table that holds it as the SQL writes it (`tasks`, or the
   * `blocks.<name>.tables` mapping), or undefined when it has none.
   */
  readonly table: string | undefined;
  /** `blocks.<name>.entities.<entity>.url`, with column placeholders. */
  readonly url: string | undefined;
}

/** The entities one installed block declares, with their final names. */
export function blockEntities(
  module: string,
  blocks: AnyBlocksConfig,
): readonly BlockEntity[] {
  const names = catalogNames(module);

  if (names === undefined) {
    return [];
  }

  const resolved = resolveNames(module, names, blocks);
  const mapped = resolveModule(blocks[module]).tables;

  return Object.values(resolved.entities).map((entity) => {
    const logical = entity.table;
    const spec = logical === undefined ? undefined : names.tables[logical];
    const target = logical === undefined ? undefined : mapped[logical];

    const table =
      spec === undefined || target === null
        ? undefined
        : (target ?? resolved.naming.rename(spec.name));

    return {
      key: entity.key,
      from: entity.from,
      to: entity.to,
      primary: entity.primary,
      table,
      url: entity.url,
    };
  });
}

/** The subjects one installed block registers, keyed by renamed entity. */
function subjectsOf(
  module: string,
  blocks: AnyBlocksConfig,
): Readonly<Record<string, SubjectConfig>> {
  const entities = CATALOG.get(module)?.entities;
  const names = catalogNames(module);
  const config = resolveModule(blocks[module]);

  if (
    entities === undefined ||
    names === undefined ||
    config.mode === "custom"
  ) {
    return {};
  }

  const resolved = resolveNames(module, names, blocks);

  const key = (action: string): string =>
    config.permissions[action] ??
    resolved.entityNaming.rename(
      entities.keys[action] ?? `${module}.${action}`,
    );

  return Object.fromEntries(
    Object.values(resolved.entities).flatMap((entity) => {
      const subject = entity.subject;

      const table =
        entity.table === undefined ? undefined : names.tables[entity.table];

      const mapped =
        entity.table === undefined ? undefined : config.tables[entity.table];

      if (
        subject === undefined ||
        entity.table === undefined ||
        table === undefined ||
        mapped === null
      ) {
        return [];
      }

      const logical = entity.table;

      const column = (name: string): string =>
        config.columns[logical]?.[name] ??
        resolved.naming.rename(table.columns[name] ?? name);

      const name = mapped ?? resolved.naming.rename(table.name);
      const url = entity.url ?? subject.url;

      const entry: SubjectConfig = {
        table: name.includes(".") ? name : `${config.schema}.${name}`,
        idType: "uuid",
        tenant: column("tenant"),
        title: column(subject.title),
        permissions: {
          read: key(subject.permissions.read),
          write: key(subject.permissions.write),
        },
        ...(subject.deletedAt === undefined
          ? {}
          : { deletedAt: column(subject.deletedAt) }),
        ...(subject.rank === undefined
          ? {}
          : {
              rank: {
                column: column(subject.rank.column),
                group: column(subject.rank.group),
              },
            }),
        ...(subject.search === undefined
          ? {}
          : {
              search: {
                title: column(subject.search.title),
                body: subject.search.body.map(column),
              },
            }),
        ...(url === undefined
          ? {}
          : {
              url: url.replaceAll(
                PLACEHOLDER,
                (_, placeholder: string) => `{${column(placeholder)}}`,
              ),
            }),
        ...(subject.cascade === true ? { cascade: true } : {}),
      };

      return [[entity.to.singular, entry]];
    }),
  );
}

/**
 * The entities of every installed block that registers one (work items, deals,
 * companies and people, products, employees), under their renamed type, then
 * `subjects`. Throws when `subjects` already has a block's type.
 */
export function withBlockSubjects(
  subjects: SubjectsConfig,
  blockNames: readonly string[],
  blocks: AnyBlocksConfig,
): SubjectsConfig {
  const merged: Record<string, SubjectConfig> = {};

  for (const module of withRequired(blockNames)) {
    for (const [type, entry] of Object.entries(subjectsOf(module, blocks))) {
      if (Object.hasOwn(subjects, type)) {
        throw new TypeError(
          `subjects.${type}: the ${module} block registers "${type}" itself; remove subjects.${type}, or set blocks.${module}.entities.<entity>.subject to false to keep your own`,
        );
      }

      merged[type] = entry;
    }
  }

  return { ...merged, ...subjects };
}
