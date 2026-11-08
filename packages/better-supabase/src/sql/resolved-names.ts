import type {
  AnyBlocksConfig,
  BlockConfig,
  EntityConfig,
} from "../config/blocks.ts";
import type {
  EntityNames,
  EntityNoun,
  EntityRename,
} from "../core/entity-naming.ts";
import type {
  BlockSqlEntitySpec,
  BlockSqlEntitySubject,
  BlockSqlNames,
} from "./context.ts";

import { tenantNameOf } from "../config/blocks.ts";
import {
  checkEntityName,
  DEFAULT_TENANT,
  entityNames,
  entityNoun,
  tenantRename,
} from "../core/entity-naming.ts";

/** One of a module's entities with the name the config gives it. */
export interface ResolvedEntity {
  readonly key: string;
  /** The logical table that holds it; global entities may have none. */
  readonly table?: string;
  readonly from: EntityNoun;
  readonly to: EntityNoun;
  /** `spec.keyed`: its `<plural>.` keys keep their names. */
  readonly keyed?: boolean;
  readonly primary: boolean;
  /** Renamed in every module (the tenant). */
  readonly global: boolean;
  /** `blocks.<name>.entities.<entity>.url`, with logical column placeholders. */
  readonly url?: string;
  /**
   * What makes the entity a subject, or undefined when it isn't one or the
   * config sets `subject: false`.
   */
  readonly subject?: BlockSqlEntitySubject;
  /** `blocks.<name>.entities.<entity>.team` and `.auditReads`, when set. */
  readonly subjectSettings?: Pick<EntityConfig, "team" | "auditReads">;
}

/**
 * A module's final names for one config: its entities as renamed and the
 * renamer every name goes through (the tenant rename, then the module's own).
 */
export interface ResolvedNames {
  readonly module: string;
  readonly entities: Readonly<Record<string, ResolvedEntity>>;
  /** The tenant's noun, `organization` unless the tenant block renames it. */
  readonly tenant: EntityNoun;
  /** Tables, columns, functions, hooks and triggers: tenant and own entities. */
  readonly naming: EntityNames;
  /**
   * Event types, payload keys, subjects, permission keys and TypeScript names:
   * the module's own entities. The tenant rename leaves them alone, as it
   * always has.
   */
  readonly entityNaming: EntityNames;
  /** Each renamed own entity's singular to the config's name. */
  readonly eventRenames: readonly EntityRename[];
  /** Event types: `eventRenames`, then the module's own entities. */
  readonly eventNaming: EntityNames;
}

const PLACEHOLDER = /\{([^{}]*)\}/g;

function primaryOf(
  where: string,
  entities: Readonly<Record<string, BlockSqlEntitySpec>>,
): string {
  const primary = Object.entries(entities).find(([, spec]) => spec.primary);

  if (primary === undefined) {
    throw new TypeError(
      `${where}: the block has no primary entity, so name one: ${Object.keys(entities).join(", ") || "none"}`,
    );
  }

  return primary[0];
}

/** `blocks.<name>.entities` as entity key to its config, shorthand expanded. */
function configured(
  where: string,
  entities: Readonly<Record<string, BlockSqlEntitySpec>>,
  config: BlockConfig["entities"],
): ReadonlyMap<string, EntityConfig> {
  if (config === undefined) {
    return new Map();
  }

  if (typeof config === "string") {
    return new Map([[primaryOf(where, entities), { name: config }]]);
  }

  const found = new Map<string, EntityConfig>();

  for (const [key, value] of Object.entries(config)) {
    if (value === undefined) {
      continue;
    }

    if (!(key in entities)) {
      throw new TypeError(
        `${where}: unknown entity "${key}". Entities: ${Object.keys(entities).join(", ") || "none"}`,
      );
    }

    found.set(key, typeof value === "string" ? { name: value } : value);
  }

  return found;
}

function checkUrl(
  where: string,
  url: string,
  columns: Readonly<Record<string, string>> | undefined,
): string {
  for (const [, column] of url.matchAll(PLACEHOLDER)) {
    if (columns === undefined || column === undefined || !(column in columns)) {
      throw new TypeError(
        `${where}: "{${column ?? ""}}" is not a column of the entity's table. Columns: ${Object.keys(columns ?? {}).join(", ") || "none"}`,
      );
    }
  }

  return url;
}

/** The noun forms a rename matches, for the containment check. */
const nounForms = (noun: EntityNoun): readonly string[] => [
  noun.singular,
  noun.plural,
];

function checkNoun(
  where: string,
  noun: EntityNoun,
  others: readonly EntityNoun[],
): void {
  for (const other of others) {
    const taken = nounForms(other).find((form) =>
      new RegExp(`(^|_)${form}(_|$)`).test(noun.singular),
    );

    if (taken !== undefined) {
      throw new TypeError(
        `${where}: "${noun.singular}" contains "${taken}", another name the blocks rename. Choose another name.`,
      );
    }
  }
}

function resolveEntity(
  where: string,
  key: string,
  spec: BlockSqlEntitySpec,
  names: BlockSqlNames,
  config: EntityConfig | undefined,
): ResolvedEntity {
  const current = entityNoun(spec.singular, spec.plural);
  const renamed = config?.name !== undefined || config?.plural !== undefined;

  const from = current;

  const to = renamed
    ? entityNoun(
        config.name === undefined
          ? from.singular
          : checkEntityName(`${where}.${key}`, config.name),
        config.plural === undefined
          ? undefined
          : checkEntityName(`${where}.${key}.plural`, config.plural),
      )
    : from;

  const columns =
    spec.table === undefined ? undefined : names.tables[spec.table]?.columns;

  const subject =
    spec.subject === undefined || config?.subject === false
      ? undefined
      : spec.subject;

  const settings = {
    ...(config?.team === undefined ? {} : { team: config.team }),
    ...(config?.auditReads === undefined
      ? {}
      : { auditReads: config.auditReads }),
  };

  if (Object.keys(settings).length > 0 && subject === undefined) {
    throw new TypeError(
      `${where}.${key}: team and auditReads apply to a subject, and "${key}" ${spec.subject === undefined ? "is not one" : "sets subject: false"}`,
    );
  }

  return {
    key,
    from,
    to,
    ...(spec.keyed === true ? { keyed: true } : {}),
    primary: spec.primary === true,
    global: spec.global === true,
    ...(spec.table === undefined ? {} : { table: spec.table }),
    ...(config?.url === undefined
      ? {}
      : { url: checkUrl(`${where}.${key}.url`, config.url, columns) }),
    ...(subject === undefined ? {} : { subject }),
    ...(Object.keys(settings).length === 0
      ? {}
      : { subjectSettings: settings }),
  };
}

/**
 * The final names of `module` under `blocks`: its entities renamed through
 * `blocks.<module>.entities`, and the tenant through
 * `blocks.memberships.names.organization`. Throws on an unknown entity, a name
 * that isn't a lowercase identifier, a `url` placeholder that isn't a column,
 * or a name that contains another noun the blocks rename.
 */
export function resolveNames(
  module: string,
  names: BlockSqlNames,
  blocks: AnyBlocksConfig = {},
): ResolvedNames {
  const where = `blocks.${module}.names`;
  const specs = names.entities ?? {};
  const config = configured(where, specs, blocks[module]?.entities);
  const tenantName = tenantNameOf(blocks);

  const tenant =
    tenantName === undefined ? DEFAULT_TENANT : tenantRename(tenantName).to;

  const entities = Object.fromEntries(
    Object.entries(specs).map(([key, spec]) => [
      key,
      resolveEntity(where, key, spec, names, config.get(key)),
    ]),
  );

  const own = Object.values(entities).filter((entity) => !entity.global);
  const defaults = [DEFAULT_TENANT, ...own.map((entity) => entity.from)];

  for (const entity of own) {
    if (entity.to.singular !== entity.from.singular) {
      checkNoun(
        `${where}.${entity.key}`,
        entity.to,
        defaults.filter((noun) => noun !== entity.from),
      );
    }
  }

  const renames: EntityRename[] = own.map((entity) => ({
    from: entity.from,
    to: entity.to,
    ...(entity.keyed === true ? { keyed: true } : {}),
  }));

  const naming = entityNames([
    ...(tenantName === undefined ? [] : [tenantRename(tenantName)]),
    ...renames,
  ]);

  return {
    module,
    entities,
    tenant,
    naming,
    entityNaming: entityNames(renames),
    eventRenames: renames.filter(
      (rename) =>
        rename.from.singular !== rename.to.singular ||
        rename.from.plural !== rename.to.plural,
    ),
    eventNaming: entityNames(renames),
  };
}

/**
 * The subject type the entity `key` registers under: its singular after
 * `blocks.<module>.entities` (`task`, or `ticket` when renamed).
 */
export function entityType(resolved: ResolvedNames, key: string): string {
  return resolved.entities[key]?.to.singular ?? key;
}
