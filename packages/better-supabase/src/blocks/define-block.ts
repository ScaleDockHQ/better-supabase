import type { EventMap, Events } from "../core/block-events.ts";
import type { StandardSchemaV1 } from "../core/standard.ts";
import type { BlockPorts, PortName } from "./ports.ts";

import { isRecord } from "../core/block-helpers.ts";

/** Where a block sits in the catalog and in presets. */
export type BlockCategory =
  | "foundation"
  | "collaboration"
  | "crm"
  | "work"
  | "commerce"
  | "scheduling"
  | "ai"
  | "content"
  | "operations"
  | "platform";

/** The ports a block consumes: `required` fails `createBlocks` without a provider. */
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

/** An options schema per SQL module, keyed by module name. */
export type BlockOptionSchemas = Readonly<
  Record<string, StandardSchemaV1<unknown, Readonly<Record<string, unknown>>>>
>;

type NoEvents = Record<never, never>;

/** What `defineBlock` takes. */
export interface BlockDefinition<
  Name extends string,
  Options,
  Client,
  M extends EventMap,
  C extends BlockConsumes,
> {
  readonly name: Name;
  /** The SQL modules (`SqlModule` keys) this block installs. */
  readonly sql?: readonly string[];
  /** The options of each SQL module, for `blocks.<module>.options`. */
  readonly options?: BlockOptionSchemas;
  /** The block's own events. */
  readonly events?: Events<M>;
  readonly consumes?: C;
  readonly provides?: BlockProvides<Client, Options>;
  /** The creator, `create<Name>(options)`; absent for a block with only SQL. */
  readonly create?: (options: Options) => Client;
  /** The headless controller's name (ADR 0030), when the block has one. */
  readonly client?: string;
  readonly category: BlockCategory;
  /** UI recipe slugs on `/recipes`. */
  readonly recipes?: readonly string[];
}

/**
 * One block (ADR 0029): its SQL modules, options, events, the ports it
 * provides and consumes, and its creator. `createBlocks` wires blocks on
 * their ports, never on their names.
 */
export interface Block<
  Name extends string = string,
  Options = never,
  Client = never,
  M extends EventMap = NoEvents,
  C extends BlockConsumes = NoEvents,
> {
  readonly apiVersion: 1;
  readonly name: Name;
  readonly sql: readonly string[];
  readonly options: BlockOptionSchemas;
  readonly events: Events<M>;
  readonly consumes: C;
  readonly provides: BlockProvides<Client, Options>;
  readonly create: ((options: Options) => Client) | undefined;
  readonly client: string | undefined;
  readonly category: BlockCategory;
  readonly recipes: readonly string[];
  /** The options `with` set, passed to `create` over the shared ones. */
  readonly settings: Partial<Options>;
  /** This block with `settings` merged into the options `createBlocks` passes it. */
  with(settings: Partial<Options>): Block<Name, Options, Client, M, C>;
}

/** Any block, for constraints. */
export interface AnyBlock {
  readonly apiVersion: 1;
  readonly name: string;
  readonly sql: readonly string[];
  readonly options: BlockOptionSchemas;
  readonly events: Events;
  readonly consumes: BlockConsumes;
  readonly provides: {
    readonly [P in PortName]?: (
      client: never,
      options: never,
    ) => BlockPorts[P] | undefined;
  };
  readonly create: ((options: never) => unknown) | undefined;
  readonly client: string | undefined;
  readonly category: BlockCategory;
  readonly recipes: readonly string[];
  readonly settings: object;
  with(settings: never): AnyBlock;
}

/** The block a creator makes, with its event map and the ports it consumes. */
export type BlockOf<
  Name extends string,
  Create extends (options: never) => unknown,
  M extends EventMap = NoEvents,
  C extends BlockConsumes = NoEvents,
> = Block<Name, Parameters<Create>[0], ReturnType<Create>, M, C>;

/** The client a block's creator returns. */
export type ClientOf<B> = B extends {
  readonly create: ((options: never) => infer Client) | undefined;
}
  ? Client
  : never;

/** Describes a block with one manifest (ADR 0029). */
export function defineBlock<
  const Name extends string,
  Options = never,
  Client = never,
  M extends EventMap = NoEvents,
  const C extends BlockConsumes = NoEvents,
>(
  definition: BlockDefinition<Name, Options, Client, M, C>,
): Block<Name, Options, Client, M, C> {
  const build = (
    settings: Partial<Options>,
  ): Block<Name, Options, Client, M, C> => ({
    apiVersion: 1,
    name: definition.name,
    sql: definition.sql ?? [],
    options: definition.options ?? {},
    events: definition.events ?? { types: [] },
    // SAFETY: a block without `consumes` consumes nothing, which is
    // `NoEvents` when `C` is left to its default.
    consumes: definition.consumes ?? ({} as C),
    provides: definition.provides ?? {},
    create: definition.create,
    client: definition.client,
    category: definition.category,
    recipes: definition.recipes ?? [],
    settings,
    with: (more) => build({ ...settings, ...more }),
  });
  return build({});
}

/**
 * A Standard Schema for a SQL module's options that accepts an object with
 * only `keys`, for a manifest's `options`.
 */
export function optionKeys<const K extends string>(
  keys: readonly K[],
): StandardSchemaV1<unknown, Readonly<Partial<Record<K, unknown>>>> {
  const known = new Set<string>(keys);
  return {
    "~standard": {
      version: 1,
      vendor: "better-supabase",
      validate: (value) => {
        if (!isRecord(value)) {
          return { issues: [{ message: "Expected an object" }] };
        }
        const unknown = Object.keys(value).filter((key) => !known.has(key));
        if (unknown.length > 0) {
          return {
            issues: unknown.map((key) => ({
              message: `Unknown option "${key}"`,
              path: [key],
            })),
          };
        }
        // SAFETY: every key of `value` is one of `keys`, and the values are
        // typed `unknown`.
        return { value: value as Readonly<Partial<Record<K, unknown>>> };
      },
    },
  };
}
