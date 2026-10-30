import type { EntityNoun, EntityRename } from "../core/entity-naming.ts";
import type { BlockSqlNames } from "../sql/context.ts";
import type { AnyBlocksConfig } from "./blocks.ts";
import type { SubjectConfig, SubjectsConfig } from "./types/subjects.ts";

import { SUBJECT_TYPE_RENAMES } from "../core/renames.ts";
import { PRESET_CATALOG } from "../preset/catalog.generated.ts";
import { clientFunctions } from "../sql/client-functions.ts";
import { resolveNames } from "../sql/resolved-names.ts";
import { blockColumnName } from "../sql/tenant-column.ts";
import { resolveBlock } from "./blocks.ts";

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
function catalogNames(module: string): BlockSqlNames | undefined {
  const entities = CATALOG.get(module)?.entities;

  return entities === undefined
    ? undefined
    : { tables: entities.tables, entities: entities.specs };
}

/**
 * The entities `blocks.<module>.names` gives a new name, such as `work_item` to
 * `task`, for the block's TypeScript client (`blocks.generated.ts`). Empty when
 * the module renames none.
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

/**
 * The renames `module`'s event types start from: a renamed entity's current
 * singular to the config's name (`task` to `ticket`), since its events name the
 * current singular. Empty when no renamed entity changed its singular.
 */
export function blockEventRenames(
  module: string,
  blocks: AnyBlocksConfig,
): readonly EntityRename[] {
  const names = catalogNames(module);

  return names === undefined
    ? []
    : resolveNames(module, names, blocks).eventRenames;
}

/**
 * The SQL name of each client function of `module` that the entity renames
 * write under the noun it had before 0.47: with `tasks: { names: { task:
 * "ticket" } }`, `create_task` is still `create_ticket`, as it was from
 * `create_work_item`. Empty when no renamed entity changed its singular.
 */
export function blockFormerFunctions(
  module: string,
  blocks: AnyBlocksConfig,
): Readonly<Record<string, string>> {
  const names = catalogNames(module);

  if (names === undefined) {
    return {};
  }

  const resolved = resolveNames(module, names, blocks);

  if (!resolved.functionNouns.renamed) {
    return {};
  }

  return Object.fromEntries(
    clientFunctions(module).flatMap((name) => {
      const former = resolved.functionNouns.rename(name);
      const written = resolved.naming.rename(former);

      return former === name || written === name ? [] : [[name, written]];
    }),
  );
}

/**
 * The subject types of the installed blocks that 0.47 renamed, new to old:
 * `task` to `work_item` for a tasks block that names no entity. An install that
 * names the entity keeps its type, and so does an old type `subjects` still
 * declares.
 */
export function blockFormerSubjectTypes(
  installed: readonly string[],
  blocks: AnyBlocksConfig,
  subjects: SubjectsConfig,
): ReadonlyMap<string, string> {
  return new Map(
    installed.flatMap((module) => {
      const names = catalogNames(module);

      return names === undefined
        ? []
        : Object.values(resolveNames(module, names, blocks).entities).flatMap(
            (entity): [string, string][] => {
              const old = entity.formerly?.from.singular;
              const next = entity.to.singular;

              return old === undefined ||
                entity.subject === undefined ||
                SUBJECT_TYPE_RENAMES[old] !== next ||
                Object.hasOwn(subjects, old)
                ? []
                : [[next, old]];
            },
          );
    }),
  );
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
  /** `blocks.<name>.names.<entity>.url`, with column placeholders. */
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
  const mapped = resolveBlock(blocks[module]).tables;

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
  tenantColumn?: string,
): Readonly<Record<string, SubjectConfig>> {
  const entities = CATALOG.get(module)?.entities;
  const names = catalogNames(module);
  const config = resolveBlock(blocks[module]);

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
        blockColumnName(
          { module, table: logical },
          table.columns,
          table.columns[name] ?? name,
          tenantColumn,
          (each) => resolved.naming.rename(each),
        );

      const titled = (key: string): string =>
        config.columns[logical]?.[key] === null &&
        subject.fallbackTitle !== undefined
          ? column(subject.fallbackTitle)
          : column(key);

      const name = mapped ?? resolved.naming.rename(table.name);
      const url = entity.url ?? subject.url;

      const entry: SubjectConfig = {
        table: name.includes(".") ? name : `${config.schema}.${name}`,
        idType: "uuid",
        tenant: column("tenant"),
        title: titled(subject.title),
        permissions: {
          read: key(subject.permissions.read),
          write: key(subject.permissions.write),
          ...(subject.permissions.upload === undefined
            ? {}
            : { upload: key(subject.permissions.upload) }),
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
                title: titled(subject.search.title),
                body: subject.search.body
                  .filter((name) => config.columns[logical]?.[name] !== null)
                  .map(column),
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
/** The subject types one installed block registers, by renamed entity. */
export function blockSubjectTypes(
  module: string,
  blocks: AnyBlocksConfig,
): readonly string[] {
  return Object.keys(subjectsOf(module, blocks));
}

export function withBlockSubjects(
  subjects: SubjectsConfig,
  blockNames: readonly string[],
  blocks: AnyBlocksConfig,
  tenantColumn?: string,
): SubjectsConfig {
  const merged: Record<string, SubjectConfig> = {};

  for (const module of withRequired(blockNames)) {
    for (const [type, entry] of Object.entries(
      subjectsOf(module, blocks, tenantColumn),
    )) {
      if (Object.hasOwn(subjects, type)) {
        throw new TypeError(
          `records.${type}: the ${module} block registers "${type}" itself; remove records.${type}, or set blocks.${module}.names.<entity>.subject to false to keep your own`,
        );
      }

      merged[type] = entry;
    }
  }

  return { ...merged, ...subjects };
}

export function installedBlockSubjects(
  subjects: SubjectsConfig,
  installed: readonly string[],
  blocks: AnyBlocksConfig,
): SubjectsConfig {
  const dropped = new Set(
    withRequired(installed)
      .filter((module) => !installed.includes(module))
      .flatMap((module) => blockSubjectTypes(module, blocks)),
  );

  return dropped.size === 0
    ? subjects
    : Object.fromEntries(
        Object.entries(subjects).filter(([type]) => !dropped.has(type)),
      );
}
