import type {
  BlockEvent,
  BlockEventPattern,
  BlockEventsMatching,
  EventMap,
  EventMapOf,
  Events,
  MergedEventMap,
} from "../core/block-events.ts";
import type { BlockOptions } from "../core/block-helpers.ts";
import type { BlockHooks } from "../core/block-hooks.ts";
import type { BlockNaming } from "../core/block-names.ts";
import type { EventHub } from "../core/events.ts";
import type { CredentialProvider } from "../credentials/provider.ts";
import type { EventSink } from "../events/cloud-event.ts";
import type { GeneratedBlocks } from "./block-config.ts";
import type { AnyBlock, ClientOf } from "./define-block.ts";
import type { BlockPorts, PortName } from "./ports.ts";

import { onBlockEvent } from "../core/block-events.ts";
import { isRecord } from "../core/block-helpers.ts";
import { withBlockHooks, wrapTransport } from "../core/block-hooks.ts";
import { blockNames } from "../core/block-names.ts";
import { forwardBlockEvents } from "../events/cloud-event.ts";
import { generatedOptions } from "./block-config.ts";

/** The CloudEvents `source` of block events that `createBlocks` forwards. */
export const BLOCK_EVENT_SOURCE = "/better-supabase/blocks";

/** What every block's creator receives from `createBlocks`, before its ports and `with` settings. */
export interface BlockContext extends BlockOptions {
  /** Connectors, ai-providers and the workflow builder store their secrets here. */
  readonly credentials?: CredentialProvider;
  /** `betterSupabase.events`, for the block events of the blocks that emit them. */
  readonly events?: EventHub;
}

export interface CreateBlocksOptions extends Omit<BlockContext, "schema"> {
  /**
   * `blockConfig` from `blocks.generated.ts`: each block gets its schema
   * (the API schema when the module has one) and the options its SQL half
   * shares, such as `attachments.requireScan`, under its own name. Blocks
   * without an entry use the module defaults.
   */
  readonly config?: GeneratedBlocks;
  /**
   * Where block events go, such as `auditLog.sink()`. Needs `events`; the
   * forwarding lasts until `close()`, so build these blocks once rather than
   * per request.
   */
  readonly audit?: EventSink;
}

/** Blocks keyed by the name the app gives each one. */
export type BlockMap = Readonly<Record<string, AnyBlock>>;

type CreatedKeys<B extends BlockMap> = {
  readonly [K in keyof B]: B[K]["create"] extends undefined ? never : K;
}[keyof B];

type BuiltBlocks<B extends BlockMap> = {
  readonly [K in CreatedKeys<B>]: ClientOf<B[K]>;
};

type UnionToIntersection<U> = (
  U extends unknown ? (value: U) => void : never
) extends (value: infer I) => void
  ? I
  : never;

/** The events of every block in `B`. */
export type BlocksEventMap<B extends BlockMap> =
  UnionToIntersection<EventMapOf<B[keyof B]["events"]>> extends infer M extends
    EventMap
    ? M
    : never;

type SinkKeys<B extends BlockMap> = {
  readonly [K in keyof B]: "sink" extends keyof B[K]["provides"] ? K : never;
}[keyof B];

/**
 * Outbox sinks of the blocks that provide one (`search`, `metrics`), keyed
 * like the blocks, for `outbox.relayRoute({ consumers: { ...app.sinks } })`.
 */
export type BlockSinks<B extends BlockMap = BlockMap> = {
  readonly [K in SinkKeys<B>]?: EventSink;
};

/** `withBlockHooks` hooks for each block, keyed like the blocks. */
export type BlocksHooks<B extends BlockMap> = {
  readonly [K in CreatedKeys<B>]?: BlockHooks<ClientOf<B[K]>>;
};

export type Blocks<B extends BlockMap> = BuiltBlocks<B> & {
  /** The outbox sinks of the blocks that provide one. */
  readonly sinks: BlockSinks<B>;
  /** Stops forwarding block events to `audit`. */
  close(): void;
};

/** A set of blocks and the app's own events, from `defineBlocks`. */
export interface BlockSet<B extends BlockMap, M extends EventMap> {
  readonly blocks: B;
  /** The generated config the blocks are built with. */
  readonly config: GeneratedBlocks;
  /** Every block's events and the app's, typed. */
  readonly events: Events<M>;
  /** Builds the blocks with the generated config: `createBlocks({ ...options, config }, blocks)`. */
  create(
    options: Omit<CreateBlocksOptions, "config"> & {
      readonly hooks?: BlocksHooks<B>;
    },
  ): Blocks<B>;
  /** `onBlockEvent` typed by these blocks' events and the app's. */
  on<const P extends BlockEventPattern<M>>(
    betterSupabase: { readonly events: EventHub },
    pattern: P,
    handler: (event: BlockEvent<M, BlockEventsMatching<M, P>>) => void,
  ): () => void;
}

/**
 * The blocks an app uses, built with `blockConfig` from
 * `blocks.generated.ts` (`better-supabase gen`), so each block's schema
 * and the options its SQL half shares come from the `blocks` config, and
 * the app's own events (`defineEvents`). The event types are the union of
 * every block's events, so `on` and `events` type each one's data without
 * `declare module` (invariant 2).
 */
export function defineBlocks<
  const B extends BlockMap,
  const E extends readonly Events[] = [],
>(
  config: GeneratedBlocks,
  blocks: B,
  ...appEvents: E
): BlockSet<B, BlocksEventMap<B> & MergedEventMap<E>> {
  const types = [
    ...new Set([
      ...Object.values(blocks).flatMap((block) => block.events.types),
      ...appEvents.flatMap((each) => each.types),
    ]),
  ];
  // SAFETY: `types` lists every block's events and the app's, which are the
  // keys of the map this set declares.
  const events = { types } as Events<BlocksEventMap<B> & MergedEventMap<E>>;
  return {
    blocks,
    config,
    events,
    create: (options) => buildBlocks({ ...options, config }, blocks),
    on: (betterSupabase, pattern, handler) =>
      onBlockEvent(betterSupabase, events, pattern, handler),
  };
}

/**
 * Builds `blocks` with one set of options and wires them on their ports.
 * Each block gets its schema and shared options from its entry in
 * `config` (`blocks.generated.ts`), keyed by the block's name. Each block
 * that consumes a port (`notifier`, `files`, `attachments`,
 * `workflows`) gets it from the one block in the set that provides it, and
 * `sinks` holds the outbox sinks the blocks provide. `credentials` reaches
 * every block, and block events go to `audit`. Only the blocks you pass are
 * imported, so the rest stay out of the bundle. `hooks` wraps each block's
 * methods with `withBlockHooks`, and the ports are built from the wrapped
 * clients, so a sibling's calls (ai-tasks sending notifications) go through
 * the hooks too.
 */
export function createBlocks<const B extends BlockMap>(
  options: CreateBlocksOptions & { readonly hooks?: NoInfer<BlocksHooks<B>> },
  blocks: B,
): Blocks<B> {
  return buildBlocks(options, blocks);
}

const UNIQUE_PORTS: readonly Exclude<PortName, "sink">[] = [
  "notifier",
  "files",
  "attachments",
  "workflows",
];

/** `key`'s entry in `hooks`, which `BlocksHooks` keys like the blocks. */
function hooksOf(
  hooks: object | undefined,
  key: string,
): BlockHooks<object> | undefined {
  if (hooks === undefined) return undefined;
  const entry: unknown = Object.entries(hooks).find(
    ([name]) => name === key,
  )?.[1];
  return isRecord(entry) ? entry : undefined;
}

function buildBlocks<B extends BlockMap>(
  options: CreateBlocksOptions & { readonly hooks?: BlocksHooks<B> },
  blocks: B,
): Blocks<B> {
  const { audit, hooks, config, ...shared } = options;
  if (audit !== undefined && shared.events === undefined)
    throw new TypeError("createBlocks: `audit` needs `events` to forward");
  const providers = new Map<string, string>();
  for (const port of UNIQUE_PORTS) {
    const keys = Object.keys(blocks).filter(
      (key) => blocks[key]?.provides[port] !== undefined,
    );
    if (keys.length > 1) {
      throw new TypeError(
        `createBlocks: ${keys.map((key) => `"${key}"`).join(" and ")} both provide the ${port} port; pass one`,
      );
    }
    const [key] = keys;
    if (key !== undefined) providers.set(port, key);
  }
  for (const [key, block] of Object.entries(blocks)) {
    for (const [port, need] of Object.entries(block.consumes)) {
      if (need === "required" && !providers.has(port)) {
        throw new TypeError(
          `createBlocks: "${key}" needs a block that provides the ${port} port`,
        );
      }
    }
  }

  const built = new Map<string, unknown>();
  const building = new Set<string>();

  const blockOf = (key: string): AnyBlock => {
    const block = blocks[key];
    if (block === undefined) throw new TypeError(`No block named "${key}"`);
    return block;
  };

  /**
   * The options `key`'s creator gets: shared, then its generated config,
   * then ports, then `with` settings.
   */
  const optionsOf = (key: string): Record<string, unknown> => {
    const ports: Record<string, unknown> = {};
    for (const port of UNIQUE_PORTS) {
      if (blockOf(key).consumes[port] === undefined) continue;
      const provider = providers.get(port);
      if (provider === undefined || provider === key) continue;
      const value = portOf(provider, port);
      if (value !== undefined) ports[port] = value;
    }
    const block = blockOf(key);
    const entry = config?.[block.name];
    return {
      ...shared,
      ...(entry === undefined ? {} : generatedOptions(entry)),
      ...(entry?.naming === undefined ? {} : renamedTransports(entry.naming)),
      ...ports,
      ...block.settings,
    };
  };

  /** `shared`'s transports, calling the block functions by the names the SQL gave them. */
  function renamedTransports(naming: BlockNaming): Partial<BlockContext> {
    const middleware = blockNames(naming);
    return {
      transport: wrapTransport(shared.transport, middleware),
      ...(shared.service === undefined
        ? {}
        : { service: wrapTransport(shared.service, middleware) }),
    };
  }

  function portOf<P extends PortName>(
    key: string,
    port: P,
  ): BlockPorts[P] | undefined {
    const provide = blockOf(key).provides[port];
    if (provide === undefined) return undefined;
    // SAFETY: `provide` takes the client and options of the block it belongs
    // to, which are the ones `build` made and passed for `key`.
    const call = provide as (
      client: unknown,
      options: unknown,
    ) => BlockPorts[P] | undefined;
    return call(build(key), optionsOf(key));
  }

  function build(key: string): unknown {
    if (built.has(key)) return built.get(key);
    const block = blockOf(key);
    if (block.create === undefined) {
      throw new TypeError(
        `The "${block.name}" block has only SQL; it has no client to build`,
      );
    }
    if (building.has(key))
      throw new TypeError(`The "${key}" block depends on itself`);
    building.add(key);
    try {
      // SAFETY: the creator takes the block's options, which are the shared
      // block options, the ports it consumes and its own `with` settings.
      const create = block.create as (options: unknown) => unknown;
      const created = create(optionsOf(key));
      const blockHooks = hooksOf(hooks, key);
      const client =
        blockHooks !== undefined && isRecord(created)
          ? withBlockHooks(created, blockHooks, {
              block: key,
              ...(shared.events === undefined
                ? {}
                : { logger: shared.events.logger }),
            })
          : created;
      built.set(key, client);
      return client;
    } finally {
      building.delete(key);
    }
  }

  const result: Record<string, unknown> = {};
  const sinks: Record<string, EventSink> = {};
  for (const [key, block] of Object.entries(blocks)) {
    if (block.create === undefined) continue;
    result[key] = build(key);
    const sink = portOf(key, "sink");
    if (sink !== undefined) sinks[key] = sink;
  }
  result["sinks"] = sinks;
  const stop =
    audit === undefined || shared.events === undefined
      ? undefined
      : forwardBlockEvents({ events: shared.events }, audit, {
          source: BLOCK_EVENT_SOURCE,
        });
  result["close"] = () => stop?.();
  // SAFETY: `result` holds each created block's client under its key, plus
  // `sinks` and `close`, which is what `Blocks<B>` describes.
  return result as Blocks<B>;
}
