import type { EventMap } from "../core/block-events.ts";
import type { BlockHooks } from "../core/block-hooks.ts";
import type { BlockNaming } from "../core/block-names.ts";
import type { EntityNames } from "../core/entity-naming.ts";
import type { DbError } from "../core/errors.ts";
import type { Logger } from "../core/logger.ts";
import type { AnyBlock, Block, BlockConsumes } from "./define-block.ts";
import type { PortName } from "./ports.ts";
import type { AnyRecordBinding } from "./record-bindings.ts";

import { withBlockHooks } from "../core/block-hooks.ts";
import { renameKeys } from "../core/block-names.ts";
import { entityNames } from "../core/entity-naming.ts";
import { AsyncResult } from "../core/result.ts";
import { renameSchemas } from "./rename-schemas.ts";

/** One renamed noun as `blocks.generated.ts` writes it. */
export interface NounRename {
  readonly from: { readonly singular: string; readonly plural: string };
  readonly to: { readonly singular: string; readonly plural: string };
}

/** The renames a block's generated `names` carries, in order. */
export type NounRenames = readonly NounRename[];

/** The renames in a block's generated `names`, or none. */
export type RenamesOf<N> = N extends {
  readonly entities: infer E extends NounRenames;
}
  ? E
  : [];

/**
 * The renames a block's event types go through: the generated `names.events`
 * (`task` to `ticket`), then its entity renames.
 */
export type EventRenamesOf<N> = N extends {
  readonly events: infer E extends NounRenames;
}
  ? readonly [...E, ...RenamesOf<N>]
  : RenamesOf<N>;

type Upper =
  | "A"
  | "B"
  | "C"
  | "D"
  | "E"
  | "F"
  | "G"
  | "H"
  | "I"
  | "J"
  | "K"
  | "L"
  | "M"
  | "N"
  | "O"
  | "P"
  | "Q"
  | "R"
  | "S"
  | "T"
  | "U"
  | "V"
  | "W"
  | "X"
  | "Y"
  | "Z";

type Digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9";

type LowerOrDigit = Lowercase<Upper> | Digit;

type Camel<S extends string> = S extends `${infer Head}_${infer Tail}`
  ? `${Head}${Capitalize<Camel<Tail>>}`
  : S;

/**
 * One form a rename matches: `bounded` forms need a word start before them
 * (snake and camel), and `camel` is the target when an uppercase letter
 * follows.
 */
interface Form {
  readonly match: string;
  readonly snake: string;
  readonly camel: string;
  readonly bounded: boolean;
}

type FormsOf<From extends string, To extends string> = [
  { match: From; snake: To; camel: Camel<To>; bounded: true },
  { match: Camel<From>; snake: Camel<To>; camel: Camel<To>; bounded: true },
  {
    match: Capitalize<Camel<From>>;
    snake: Capitalize<Camel<To>>;
    camel: Capitalize<Camel<To>>;
    bounded: false;
  },
];

type FormsFor<
  R extends NounRenames,
  N extends "plural" | "singular",
> = R extends readonly [
  infer Head extends NounRename,
  ...infer Tail extends NounRenames,
]
  ? [...FormsOf<Head["from"][N], Head["to"][N]>, ...FormsFor<Tail, N>]
  : [];

/**
 * Every form of every rename, plurals first so `work_items` wins over
 * `work_item`.
 */
type FormsOfRenames<R extends NounRenames> = [
  ...FormsFor<R, "plural">,
  ...FormsFor<R, "singular">,
];

// What may sit before a snake or camel form for it to start a word.
type WordBreak = "_" | "-" | "." | ":" | " " | "/";

type Starts<Before extends string> = Before extends ""
  ? true
  : Before extends `${string}${WordBreak}`
    ? true
    : false;

// A matched form waits as `\u0001<index>\u0003<case>\u0002` until every form
// has run, so a new name is never matched again.
type Marker<
  I extends number,
  Case extends "camel" | "snake",
> = `\u0001${I}\u0003${Case}\u0002`;

type CaseAfter<Rest extends string> = Rest extends `${Upper}${string}`
  ? "camel"
  : "snake";

type Matches<
  F extends Form,
  Before extends string,
  Rest extends string,
> = Rest extends `${LowerOrDigit}${string}`
  ? false
  : F["bounded"] extends true
    ? Starts<Before>
    : true;

/** `S` with every bounded occurrence of `F` marked. */
type MarkForm<
  S extends string,
  F extends Form,
  I extends number,
  Done extends string = "",
> = S extends `${infer A}${F["match"]}${infer B}`
  ? Matches<F, `${Done}${A}`, B> extends true
    ? MarkForm<B, F, I, `${Done}${A}${Marker<I, CaseAfter<B>>}`>
    : MarkForm<B, F, I, `${Done}${A}${F["match"]}`>
  : `${Done}${S}`;

type MarkAll<
  S extends string,
  Forms extends readonly Form[],
  I extends readonly unknown[] = [],
> = Forms extends readonly [
  infer F extends Form,
  ...infer Others extends readonly Form[],
]
  ? MarkAll<
      string extends F["match"] ? S : MarkForm<S, F, I["length"]>,
      Others,
      [...I, unknown]
    >
  : S;

type Unmark<
  S extends string,
  Forms extends readonly Form[],
  Done extends string = "",
> = S extends `${infer A}\u0001${infer N extends number}\u0003${infer C extends "camel" | "snake"}\u0002${infer B}`
  ? Unmark<B, Forms, `${Done}${A}${Forms[N] extends Form ? Forms[N][C] : ""}`>
  : `${Done}${S}`;

type Rename<S extends string, Forms extends readonly Form[]> = Unmark<
  MarkAll<S, Forms>,
  Forms
>;

/**
 * An identifier with every renamed noun in its new name, in snake, camel and
 * pascal case: `RenameKey<"projectId", R>` is `initiativeId` when `R` renames
 * `project` to `initiative`.
 */
export type RenameKey<K, R extends NounRenames> = K extends string
  ? Rename<K, FormsOfRenames<R>>
  : K;

// Values a rename never looks into.
type Leaf =
  | string
  | number
  | boolean
  | bigint
  | symbol
  | null
  | undefined
  | Date
  | Uint8Array
  | DbError
  | Temporal.Instant
  | Temporal.PlainDate
  | Temporal.PlainDateTime
  | Temporal.PlainTime
  | Temporal.ZonedDateTime
  | Temporal.Duration;

type Opaque = "fields" | "metadata";

// The nesting a rename follows: client, method, result, row, nested row.
type MaxDepth = 6;

type Deeper<D extends readonly unknown[]> = [...D, unknown];

type RenamedEntry<
  K,
  V,
  R extends NounRenames,
  D extends readonly unknown[],
> = K extends Opaque
  ? V
  : K extends "field"
    ? RenameKey<V, R>
    : RenamedValue<V, R, D>;

type RenamedValue<
  T,
  R extends NounRenames,
  D extends readonly unknown[],
> = D["length"] extends MaxDepth
  ? T
  : T extends Leaf
    ? T
    : T extends AsyncResult<infer V>
      ? AsyncResult<RenamedValue<V, R, Deeper<D>>>
      : T extends Promise<infer V>
        ? Promise<RenamedValue<V, R, Deeper<D>>>
        : T extends (...args: infer A) => infer Ret
          ? (
              ...args: RenamedValue<A, R, Deeper<D>>
            ) => RenamedValue<Ret, R, Deeper<D>>
          : T extends readonly unknown[]
            ? { [K in keyof T]: RenamedValue<T[K], R, Deeper<D>> }
            : T extends object
              ? {
                  [K in keyof T as RenameKey<K, R>]: RenamedEntry<
                    K,
                    T[K],
                    R,
                    Deeper<D>
                  >;
                }
              : T;

/**
 * `T` with every key renamed through `R`, nested up to six levels: rows, inputs
 * and filters. The values under `fields` and `metadata` keep their keys.
 * `RenamedType<WorkItem, R>` has `initiativeId` where `WorkItem` has
 * `projectId`.
 */
export type RenamedType<T, R extends NounRenames> = R extends readonly []
  ? T
  : RenamedValue<T, R, []>;

/**
 * A block client with its method names, argument keys and result keys renamed:
 * `saveProject` becomes `saveInitiative` and its rows carry `initiativeId`.
 */
export type RenamedClient<C, R extends NounRenames> = RenamedType<C, R>;

/** An event map with renamed types and payload keys. */
export type RenamedEvents<
  M extends EventMap,
  R extends NounRenames,
> = R extends readonly []
  ? M
  : {
      readonly [K in keyof M as RenameKey<K, R>]: RenamedType<M[K], R>;
    };

/** A creator's options with hooks keyed by the renamed client's methods. */
export type RenamedOptions<
  O,
  Client,
  R extends NounRenames,
> = R extends readonly []
  ? O
  : O extends { readonly hooks?: unknown }
    ? Omit<O, "hooks"> & {
        readonly hooks?: BlockHooks<RenamedClient<Client, R>>;
      }
    : O;

/**
 * A block with its client, events and hooks under the renamed nouns; its event
 * types go through `E`.
 */
export type RenamedBlock<B, R extends NounRenames, E extends NounRenames = R> =
  B extends Block<
    infer Name,
    infer O,
    infer Client,
    infer M,
    infer C,
    infer P,
    infer S
  >
    ? Block<
        Name,
        RenamedOptions<O, Client, R>,
        RenamedClient<Client, R>,
        RenamedEvents<M, E>,
        C,
        P,
        S
      >
    : never;

type Fn = (...args: unknown[]) => unknown;

function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const prototype: unknown = Object.getPrototypeOf(value);

  return prototype === Object.prototype || prototype === null;
}

/** Translates values between the default and the renamed nouns. */
class Renamer {
  readonly #names: EntityNames;
  readonly #originals = new WeakMap<object, unknown>();

  constructor(names: EntityNames) {
    this.#names = names;
  }

  /** The client `renamed` wraps, for the ports that read the default names. */
  originalOf(renamed: unknown): unknown {
    return typeof renamed === "object" && renamed !== null
      ? (this.#originals.get(renamed) ?? renamed)
      : renamed;
  }

  /** A client with renamed method names, argument keys and result keys. */
  client(client: unknown): unknown {
    if (typeof client !== "object" || client === null) {
      return client;
    }

    const renamed: Record<string, unknown> = {};

    for (const key of methodNames(client)) {
      // SAFETY: a read of one key `methodNames` found on the client.
      const value = (client as Readonly<Record<string, unknown>>)[key];

      if (typeof value === "function") {
        // SAFETY: any function accepts unknown arguments at runtime.
        renamed[this.#names.rename(key)] = this.#outward(
          value.bind(client) as Fn,
        );
        continue;
      }

      renamed[this.#names.rename(key)] = this.forward(value);
    }

    this.#originals.set(renamed, client);

    return renamed;
  }

  /** A value from the client, renamed for the caller. */
  forward(value: unknown): unknown {
    if (value instanceof AsyncResult) {
      return value.map((data: unknown) => this.forward(data));
    }

    if (value instanceof Promise) {
      return value.then((data: unknown) => this.forward(data));
    }

    if (typeof value === "function") {
      // SAFETY: any function accepts unknown arguments at runtime.
      return this.#outward(value as Fn);
    }

    return this.#keys(value, (key) => this.#names.rename(key), "forward");
  }

  /** A value from the caller, renamed back for the client. */
  back(value: unknown): unknown {
    if (typeof value === "function") {
      // SAFETY: any function accepts unknown arguments at runtime.
      const inner = value as Fn;

      return (...args: unknown[]): unknown =>
        this.back(inner(...args.map((arg) => this.forward(arg))));
    }

    return this.#keys(value, (key) => this.#names.reverse(key), "back");
  }

  #outward(fn: Fn): Fn {
    return (...args: unknown[]): unknown =>
      this.forward(fn(...args.map((arg) => this.back(arg))));
  }

  #keys(
    value: unknown,
    rename: (key: string) => string,
    direction: "forward" | "back",
  ): unknown {
    if (Array.isArray(value)) {
      return value.map((each) =>
        direction === "forward" ? this.forward(each) : this.back(each),
      );
    }

    if (!isPlainObject(value)) {
      return value;
    }

    const hasFunctions = Object.values(value).some(
      (each) => typeof each === "function",
    );

    if (!hasFunctions) {
      return renameKeys(value, rename);
    }

    return Object.fromEntries(
      Object.entries(value).map(([key, each]) => [
        rename(key),
        direction === "forward" ? this.forward(each) : this.back(each),
      ]),
    );
  }
}

/** The client's own and inherited method and property names. */
function methodNames(client: object): readonly string[] {
  const found = new Set<string>();
  let current: object | null = client;

  while (current !== null && current !== Object.prototype) {
    for (const key of Object.getOwnPropertyNames(current)) {
      if (key !== "constructor") {
        found.add(key);
      }
    }

    // SAFETY: a prototype is an object or null.
    current = Object.getPrototypeOf(current) as object | null;
  }

  return [...found];
}

interface HookOptions {
  readonly hooks?: unknown;
  readonly logger?: Logger;
}

/**
 * `binding` for a renamed block: it reads the default names, so it gets the
 * original client and its rows come back renamed.
 */
function renamedBinding(
  binding: AnyRecordBinding,
  renamer: Renamer,
  events: EntityNames,
): AnyRecordBinding {
  // SAFETY: a binding's functions take the client its block's creator made,
  // which `originalOf` returns, and values it renames back.
  const load = binding.load as (...args: unknown[]) => AsyncResult<unknown>;

  // SAFETY: as for `load`.
  const count = binding.count as
    | ((...args: unknown[]) => AsyncResult<Readonly<Record<string, number>>>)
    | undefined;

  // SAFETY: as for `load`.
  const optimistic = binding.optimistic as
    | ((state: unknown, action: unknown) => unknown)
    | undefined;

  return {
    ...binding,
    events: binding.events.map((type) => events.rename(type)),
    load: (client: never, subject, options: never) =>
      load(renamer.originalOf(client), subject, options).map((data) =>
        renamer.forward(data),
      ),
    ...(count === undefined
      ? {}
      : {
          count: (client: never, subjects) =>
            count(renamer.originalOf(client), subjects),
        }),
    ...(optimistic === undefined
      ? {}
      : {
          optimistic: (state: never, action: never) =>
            renamer.forward(
              optimistic(renamer.back(state), renamer.back(action)),
            ),
        }),
  };
}

function renamed(
  block: AnyBlock,
  renamer: Renamer,
  names: EntityNames,
  events: EntityNames,
): AnyBlock {
  const create = block.create;

  const provides = Object.fromEntries(
    Object.entries(block.provides).map(([port, provide]) => [
      port,
      // SAFETY: the provider takes the client its block's creator made, which
      // `originalOf` returns for the renamed one createBlocks passes.
      (client: never, options: never) =>
        (provide as (client: unknown, options: unknown) => unknown)(
          renamer.originalOf(client),
          options,
        ),
    ]),
  );

  return {
    ...block,
    events: { types: block.events.types.map((type) => events.rename(type)) },
    schemas: renameSchemas(block.schemas ?? {}, names, renamer),
    invalidates: Object.fromEntries(
      Object.entries(block.invalidates ?? {}).map(([pattern, methods]) => [
        events.rename(pattern),
        methods.map((method) => names.rename(method)),
      ]),
    ),
    provides,
    record:
      block.record === undefined
        ? undefined
        : renamedBinding(block.record, renamer, events),
    create:
      create === undefined
        ? undefined
        : (options: never) => {
            // SAFETY: a block's options are an object; `hooks` and `logger`
            // are read when present.
            const given = options as HookOptions;
            const { hooks, ...rest } = given;
            const logger = given.logger;
            // SAFETY: the creator gets the options it was given, without the
            // hooks, which apply to the renamed client instead.
            const client = renamer.client(create(rest as never));

            // SAFETY: `RenamedOptions` types `hooks` for the renamed client.
            return withBlockHooks(
              client as object,
              hooks as BlockHooks<object> | undefined,
              {
                block: block.name,
                ...(logger === undefined ? {} : { logger }),
              },
            );
          },
    with: (settings: never) =>
      renamed(block.with(settings), renamer, names, events),
    using: (next: never) => renamed(block.using(next), renamer, names, events),
  };
}

/**
 * `block` under the names `blocks.<name>.entities` gives its entities: method
 * names (`saveProject` to `saveInitiative`), argument and result keys
 * (`projectId` to `initiativeId`) and event types (`task.created` to
 * `ticket.created`, through `names.events`), with the same `name`, SQL and
 * ports. Hooks see the renamed client. Pass the block's `names` from
 * `blocks.generated.ts`, which `gen` writes as `export const tasksBlock =
 * renameBlock(tasksBlock, blockConfig["tasks"].names)`; with no renamed entity
 * it returns `block`.
 */
export function renameBlock<
  Name extends string,
  O,
  Client,
  M extends EventMap,
  C extends BlockConsumes,
  P extends PortName,
  R extends AnyRecordBinding | undefined,
  const N extends BlockNaming | undefined,
>(
  block: Block<Name, O, Client, M, C, P, R>,
  names: N,
): RenamedBlock<
  Block<Name, O, Client, M, C, P, R>,
  RenamesOf<N>,
  EventRenamesOf<N>
>;
export function renameBlock(
  block: AnyBlock,
  names: BlockNaming | undefined,
): AnyBlock {
  const entities = entityNames(names?.entities);

  const events = entityNames([
    ...(names?.events ?? []),
    ...(names?.entities ?? []),
  ]);

  return entities.renamed
    ? renamed(block, new Renamer(entities), entities, events)
    : block;
}
