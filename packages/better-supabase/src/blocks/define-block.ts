import type { EventMap, Events } from "../core/block-events.ts";
import type { BlockContext } from "./create-blocks.ts";
import type { BlockSchemas } from "./entity-schema.ts";
import type { BlockOptionsSchema } from "./options.ts";
import type { BlockPorts, PortName } from "./ports.ts";
import type { AnySection, SectionMap } from "./sections.ts";

/** Where a block sits in the catalog and in presets, in catalog order. */
export const BLOCK_CATEGORIES = [
  "identity",
  "tenancy",
  "collaboration",
  "messaging",
  "growth",
  "crm",
  "work",
  "people",
  "commerce",
  "scheduling",
  "content",
  "ai",
  "automation",
  "developer",
  "admin",
  "database",
] as const;

export type BlockCategory = (typeof BLOCK_CATEGORIES)[number];

/**
 * The ports a block consumes: `required` fails `createBlocks` without a
 * provider.
 */
export type BlockConsumes = {
  readonly [P in PortName]?: "optional" | "required";
};

/** The consumed ports, as the creator receives them. */
export type ConsumedPorts<C extends BlockConsumes> = {
  readonly [P in keyof C & PortName]?: BlockPorts[P];
};

/** How a block builds each port it provides from its client and options. */
export type BlockProvides<Client, Options> = {
  readonly [P in PortName]?: (
    client: Client,
    options: Options,
  ) => BlockPorts[P] | undefined;
};

/**
 * The ports a built block provides, by name. `createBlocks` calls each with the
 * block's client and options.
 */
export type ProvidedPorts<P extends PortName> = {
  readonly [K in P]: (
    client: never,
    options: never,
  ) => BlockPorts[K] | undefined;
};

/** An options schema per SQL module, keyed by module name (`blockOptions`). */
export type BlockOptionSchemas = Readonly<Record<string, BlockOptionsSchema>>;

type Nothing = Record<never, never>;

/** Event pattern to the read methods it makes stale. */
export type BlockInvalidates = Readonly<Record<string, readonly string[]>>;

/** What `defineBlock` takes. */
export interface BlockDefinition<
  Name extends string,
  Options,
  Client,
  M extends EventMap,
  C extends BlockConsumes,
  P extends PortName,
  S extends SectionMap = Nothing,
> {
  readonly name: Name;
  /** The SQL modules (`SqlModule` keys) this block installs. */
  readonly sql?: readonly string[];
  /** The options of each SQL module, for `blocks.<module>.options`. */
  readonly options?: BlockOptionSchemas;
  /** The block's own events. */
  readonly events?: Events<M>;
  readonly consumes?: C;
  readonly provides?: Pick<Required<BlockProvides<Client, Options>>, P>;
  /** The creator, `create<Name>(options)`; absent for a block with only SQL. */
  readonly create?: (options: Options) => Client;
  /** The headless controller's name (ADR 0030), when the block has one. */
  readonly client?: string;
  readonly category: BlockCategory;
  /** UI recipe slugs on `/recipes`. */
  readonly recipes?: readonly string[];
  /**
   * Standard Schemas for what the client takes, by entity key: the create
   * input, update change and list filter (`entitySchema`).
   */
  readonly schemas?: BlockSchemas;
  /**
   * The read methods each event pattern (`"work_item.*"`) makes stale, for
   * `invalidateOnBlockEvents`. An event no pattern matches makes every read
   * method of the block stale.
   */
  readonly invalidates?: BlockInvalidates;
  /**
   * The parts of a record page the block owns (`defineSection`), by name, for
   * `loadSections` and `createRecordController`.
   */
  readonly sections?: S;
}

/**
 * What `using` passes its creator: the shared block options and the consumed
 * ports.
 */
export type UsingOptions<C extends BlockConsumes> = BlockContext &
  ConsumedPorts<C>;

/**
 * One block (ADR 0029): its SQL modules, options, events, the ports it provides
 * and consumes, and its creator. `createBlocks` wires blocks on their ports,
 * never on their names.
 */
export interface Block<
  Name extends string = string,
  Options = BlockContext,
  Client = unknown,
  M extends EventMap = Nothing,
  C extends BlockConsumes = Nothing,
  P extends PortName = never,
  S extends SectionMap = Nothing,
> {
  readonly apiVersion: 1;
  readonly name: Name;
  readonly sql: readonly string[];
  readonly options: BlockOptionSchemas;
  readonly events: Events<M>;
  readonly consumes: C;
  readonly provides: ProvidedPorts<P>;
  readonly create: ((options: Options) => Client) | undefined;
  readonly client: string | undefined;
  readonly category: BlockCategory;
  readonly recipes: readonly string[];
  /** Standard Schemas for what the client takes, by entity key. */
  readonly schemas: BlockSchemas;
  /**
   * The read methods each event pattern (`"work_item.*"`) makes stale, for
   * `invalidateOnBlockEvents`. An event no pattern matches makes every read
   * method of the block stale.
   */
  readonly invalidates: BlockInvalidates;
  /** The parts of a record page the block owns, by name. */
  readonly sections: S;
  /**
   * The options `with` set, passed to `create` and the providers over the
   * shared ones.
   */
  readonly settings: object;
  /**
   * This block with `settings` merged into the options `createBlocks` passes
   * it.
   */
  with(settings: Partial<Options>): Block<Name, Options, Client, M, C, P, S>;
  /**
   * This block built by `create` instead, keeping its SQL, events and ports:
   * for a creator's type parameters (`notificationsBlock.using((options) =>
   * createNotifications({ ...options, types }))`) or a definition the creator
   * needs (`settingsBlock.using((options) => createSettings({ ...options,
   * settings }))`). The ports it provides receive the new client. Settings from
   * an earlier `with` still reach `create` and the providers.
   */
  using<Next>(
    create: (options: UsingOptions<C>) => Next,
  ): Block<Name, UsingOptions<C>, Next, M, C, P, S>;
}

/** Any block, for constraints. */
export interface AnyBlock {
  readonly apiVersion: 1;
  readonly name: string;
  readonly sql: readonly string[];
  readonly options: BlockOptionSchemas;
  readonly events: Events;
  readonly consumes: BlockConsumes;
  readonly provides: Partial<ProvidedPorts<PortName>>;
  readonly create: ((options: never) => unknown) | undefined;
  readonly client: string | undefined;
  readonly category: BlockCategory;
  readonly recipes: readonly string[];
  readonly schemas?: BlockSchemas;
  readonly invalidates?: BlockInvalidates;
  readonly sections?: Readonly<Record<string, AnySection>>;
  readonly settings: object;
  with(settings: never): AnyBlock;
  using(create: never): AnyBlock;
}

/**
 * The block a creator makes, with its event map, consumed ports and provided
 * ports.
 */
export type BlockOf<
  Name extends string,
  Create extends (options: never) => unknown,
  M extends EventMap = Nothing,
  C extends BlockConsumes = Nothing,
  P extends PortName = never,
  S extends SectionMap = Nothing,
> = Block<Name, Parameters<Create>[0], ReturnType<Create>, M, C, P, S>;

/** The client a block's creator returns. */
export type ClientOf<B> = B extends {
  readonly create: ((options: never) => infer Client) | undefined;
}
  ? Client
  : never;

/** Describes a block with one manifest (ADR 0029). */
export function defineBlock<
  const Name extends string,
  Options = BlockContext,
  Client = unknown,
  M extends EventMap = Nothing,
  const C extends BlockConsumes = Nothing,
  P extends PortName = never,
  const S extends SectionMap = Nothing,
>(
  definition: BlockDefinition<Name, Options, Client, M, C, P, S>,
): Block<Name, Options, Client, M, C, P, S> {
  const { create, consumes, provides, sections, ...rest } = definition;

  return blockOf(
    {
      ...rest,
      // SAFETY: a block without `consumes` consumes nothing, which is
      // `Nothing` when `C` is left to its default.
      consumes: consumes ?? ({} as C),
      // SAFETY: each provider takes this block's client and options, which
      // `createBlocks` passes it; a block without `provides` provides
      // nothing, which is `ProvidedPorts<never>` when `P` is left to its default.
      provides: (provides ?? {}) as ProvidedPorts<P>,
      // SAFETY: a block without `sections` has none, which is `Nothing` when
      // `S` is left to its default.
      sections: sections ?? ({} as S),
    },
    create,
    {},
  );
}

interface BlockParts<
  Name extends string,
  M extends EventMap,
  C extends BlockConsumes,
  P extends PortName,
  S extends SectionMap,
> extends Omit<
  BlockDefinition<Name, never, never, M, C, P, S>,
  "create" | "consumes" | "provides" | "sections"
> {
  readonly consumes: C;
  readonly provides: ProvidedPorts<P>;
  readonly sections: S;
}

function blockOf<
  Name extends string,
  Options,
  Client,
  M extends EventMap,
  C extends BlockConsumes,
  P extends PortName,
  S extends SectionMap,
>(
  parts: BlockParts<Name, M, C, P, S>,
  create: ((options: Options) => Client) | undefined,
  settings: object,
): Block<Name, Options, Client, M, C, P, S> {
  return {
    apiVersion: 1,
    name: parts.name,
    sql: parts.sql ?? [],
    options: parts.options ?? {},
    events: parts.events ?? { types: [] },
    consumes: parts.consumes,
    provides: parts.provides,
    create,
    client: parts.client,
    category: parts.category,
    recipes: parts.recipes ?? [],
    schemas: parts.schemas ?? {},
    invalidates: parts.invalidates ?? {},
    sections: parts.sections,
    settings,
    with: (more) => blockOf(parts, create, { ...settings, ...more }),
    using: (next) => blockOf(parts, next, settings),
  };
}
