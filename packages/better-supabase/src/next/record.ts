import type { StandardSchemaV1 } from "@standard-schema/spec";

import type {
  BlockClientOptions,
  BlockClientSource,
} from "../blocks/create-blocks.ts";
import type { AnyBlock } from "../blocks/define-block.ts";
import type { PermissionSet } from "../blocks/permissions/permissions-controller.ts";
import type { RecordBindingOptions } from "../blocks/record-bindings.ts";
import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { ListParseOptions, ListSearchParams } from "../list/list-query.ts";
import type { BindingName, BindingOf } from "../records/bindings.ts";
import type {
  RecordList,
  RecordListCells,
  RecordListPage,
} from "../records/list.ts";
import type {
  RecordTypeBlocks,
  RecordTypeWriteInput,
  RecordTypeWriteOutput,
  Plain,
  PlainBindings,
  RecordCan,
  RecordType,
  RecordWriteInput,
  BindingWritesOf,
} from "../records/record-type.ts";
import type { Timeline } from "../records/timeline.ts";
import type { RecordRef } from "../schema/types.ts";
import type { ActionResult } from "../server/kit.ts";

import { createBlockClient } from "../blocks/create-blocks.ts";
import { loadBindings } from "../records/bindings.ts";
import {
  bindingWrites,
  findBindingWrite,
  plainData,
  recordCan,
  recordPermissionKeys,
  recordSubject,
  recordWriteInput,
  runBindingWrite,
} from "../records/record-type.ts";
import { loadTimeline } from "../records/timeline.ts";
import { isStorageApi } from "../storage/storage-api.ts";
import { invalidateBinding, recordTag, bindingTag } from "./records.ts";

/**
 * The context `recordServer` reads: the caller's `Db`, and its supabase-js
 * client, whose `storage` the attachments block deletes files with.
 */
export interface RecordServerContext {
  readonly db: BlockClientSource;
  readonly supabase?: { readonly storage?: unknown };
}

/**
 * What `recordServer` needs of `bsb` (`createNext`): its context and its
 * actions, typed loosely so any app's `bsb` fits.
 */
export interface RecordServerHost {
  context(): Promise<RecordServerContext>;
  action<S extends StandardSchemaV1, T>(
    options: { readonly input: S; readonly requireTenant: true },
    fn: (
      input: StandardSchemaV1.InferOutput<S>,
      ctx: RecordServerContext & { readonly tenant: string },
    ) => Promise<T>,
  ): (input: never) => Promise<ActionResult<unknown>>;
}

export interface RecordLoadOptions<
  B extends RecordTypeBlocks,
  M extends BindingName<B>,
> {
  /** The bindings to load. Default: every binding of the record type. */
  readonly bindings?: readonly M[];
  /** Options for each binding's `load`, such as `{ versions: { pageSize: 5 } }`. */
  readonly options?: {
    readonly [K in M]?: RecordBindingOptions<BindingOf<B, K>>;
  };
}

/** What a generated loader resolves to, safe to pass to a Client Component. */
export interface RecordView<
  T extends string,
  B extends RecordTypeBlocks,
  N extends string,
  M extends N,
> {
  readonly subject: RecordRef<T>;
  /** Each requested binding settled: `ok`, `error` or `hidden`. */
  readonly bindings: PlainBindings<B, M>;
  /** What the caller may do on every binding of the record type. */
  readonly can: RecordCan<B, N>;
  /**
   * Set when the caller's permissions failed to load; every flag is then
   * `false`.
   */
  readonly permissionsError?: DbError;
}

export interface RecordTimelineOptions<N extends string> {
  /** Default: every binding of the record type with a `timeline`. */
  readonly bindings?: readonly N[];
  /** The most entries to return, newest first. */
  readonly limit?: number;
}

/** One Server Action per write of each binding. */
export type RecordServerActions<
  B extends RecordTypeBlocks,
  N extends string,
> = {
  readonly [S in N]: {
    readonly [W in BindingWritesOf<B, S>]: (
      input: RecordWriteInput<RecordTypeWriteInput<B, S, W>>,
    ) => Promise<ActionResult<Plain<RecordTypeWriteOutput<B, S, W>>>>;
  };
};

export interface RecordServer<
  T extends string,
  B extends RecordTypeBlocks,
  N extends BindingName<B>,
> {
  /**
   * Loads one record's bindings and the caller's flags. It reads the request,
   * so call it outside `"use cache"`: a cached binding error would stick.
   */
  load<const M extends N = N>(
    id: string,
    options?: RecordLoadOptions<B, M>,
  ): Promise<RecordView<T, B, N, M>>;
  /**
   * One record's history across its bindings, newest first, with the bindings
   * the caller can't read skipped. Call it outside `"use cache"`, like `load`.
   */
  timeline(
    id: string,
    options?: RecordTimelineOptions<N>,
  ): Promise<Plain<Timeline>>;
  /** The Server Actions; re-export them from a `"use server"` file. */
  readonly actions: RecordServerActions<B, N>;
  /** The record's cache tag and one per binding, scoped to `tenant`. */
  tags(id: string, tenant?: string | null): readonly string[];
}

type Clients = Readonly<Record<string, unknown>>;

/**
 * The options every block client of the record type is built with: the
 * generated config, and the caller's storage for the blocks that keep files.
 */
function clientOptions(
  feature: Pick<RecordType, "config">,
  ctx: RecordServerContext,
): BlockClientOptions {
  const storage = ctx.supabase?.storage;

  return {
    ...(feature.config === undefined ? {} : { config: feature.config }),
    ...(isStorageApi(storage) ? { storage } : {}),
  };
}

function clientsOf(
  feature: Pick<RecordType, "blocks" | "config">,
  ctx: RecordServerContext,
): Clients {
  const options = clientOptions(feature, ctx);

  return Object.fromEntries(
    Object.entries(feature.blocks).map(([key, block]) => [
      key,
      createBlockClient(ctx.db, block, options),
    ]),
  );
}

interface PermissionLoad {
  readonly set: PermissionSet | null | undefined;
  readonly error?: DbError;
}

async function permissionsOf(
  feature: Pick<RecordType, "access" | "blocks" | "config" | "permissions"> & {
    readonly bindings: readonly string[];
  },
  db: BlockClientSource,
): Promise<PermissionLoad> {
  const keys = recordPermissionKeys(feature);

  if (feature.access === undefined || keys.length === 0) {
    return { set: undefined };
  }

  const access = createBlockClient(
    db,
    feature.access,
    feature.config === undefined ? {} : { config: feature.config },
  );

  const result = await access.permissions({ keys });

  return result.ok ? { set: result.data } : { set: null, error: result.error };
}

function readableSections(can: object): ReadonlyMap<string, boolean> {
  // SAFETY: every entry of `RecordCan` has a `read` flag.
  const flags = can as Readonly<Record<string, { readonly read: boolean }>>;

  return new Map(
    Object.entries(flags).map(([name, entry]) => [name, entry.read]),
  );
}

/**
 * The server half of a generated record type for Next.js: a loader for Server
 * Components and one Server Action per binding write. Each action builds the
 * block's client over the caller's `Db` (its tenant), runs the write, and drops
 * the binding's and the record's cache tags (`invalidateBinding`).
 *
 * ```ts
 * const customer = bsb.record(customerRecord);
 * const view = await customer.load(id, { bindings: ["comments"] });
 * ```
 */
export function recordServer<
  T extends string,
  B extends RecordTypeBlocks,
  N extends BindingName<B>,
>(
  bsb: RecordServerHost,
  feature: RecordType<T, B> & { readonly bindings: readonly N[] },
): RecordServer<T, B, N> {
  const actionOf = (binding: string, write: string) => {
    const found = findBindingWrite(feature, binding, write);

    const block: AnyBlock | undefined =
      found === undefined ? undefined : feature.blocks[found.key];

    if (found === undefined || block === undefined) {
      throw new TypeError(
        `bsb.record: binding "${binding}" has no write "${write}"`,
      );
    }

    return bsb.action(
      { input: recordWriteInput(found.write.input), requireTenant: true },
      async ({ id, input }, ctx): Promise<Result<unknown>> => {
        const subject = recordSubject(feature, id);

        const result = await runBindingWrite(
          feature,
          {
            [found.key]: createBlockClient(
              ctx.db,
              block,
              clientOptions(feature, ctx),
            ),
          },
          binding,
          write,
          subject,
          input,
        );

        if (!result.ok) {
          return result;
        }

        invalidateBinding(subject, binding, { tenant: ctx.tenant });

        return { ...result, data: plainData(result.data) };
      },
    );
  };

  // SAFETY: one action per write of each binding, as `RecordServerActions`
  // maps them.
  const actions = Object.fromEntries(
    bindingWrites(feature).map(([binding, writes]) => [
      binding,
      Object.fromEntries(
        writes.map((write) => [write, actionOf(binding, write)]),
      ),
    ]),
  ) as RecordServerActions<B, N>;

  return {
    async load(id, options = {}) {
      const ctx = await bsb.context();
      const subject = recordSubject(feature, id);
      const permissions = await permissionsOf(feature, ctx.db);
      const can = recordCan(feature, permissions.set);
      const readable = readableSections(can);

      // SAFETY: without `bindings` the loader loads every binding, which is
      // `M` at its default `N`.
      const names = (options.bindings ?? feature.bindings) as readonly N[];

      const loaded = await loadBindings(
        { blocks: feature.blocks, clients: clientsOf(feature, ctx) },
        subject,
        names,
        {
          can: ({ binding }) => readable.get(binding) ?? true,
          // SAFETY: `RecordLoadOptions` types each binding's options as
          // `LoadBindingsOptions` does, by binding name.
          ...(options.options === undefined
            ? {}
            : { options: options.options as never }),
        },
      );

      // SAFETY: `plainData` maps each binding's Temporal values to strings,
      // as `PlainBindings` types them.
      return {
        subject,
        bindings: plainData(loaded) as never,
        can,
        ...(permissions.error === undefined
          ? {}
          : { permissionsError: permissions.error }),
      };
    },
    async timeline(id, options = {}) {
      const ctx = await bsb.context();
      const permissions = await permissionsOf(feature, ctx.db);
      const readable = readableSections(recordCan(feature, permissions.set));

      const timeline = await loadTimeline(
        { blocks: feature.blocks, clients: clientsOf(feature, ctx) },
        recordSubject(feature, id),
        { ...options, can: ({ binding }) => readable.get(binding) ?? true },
      );

      return plainData(timeline);
    },
    actions,
    tags(id, tenant) {
      const subject = recordSubject(feature, id);
      const scope = { tenant };

      return [
        recordTag(subject, scope),
        ...feature.bindings.map((binding) =>
          bindingTag(subject, binding, scope),
        ),
      ];
    },
  };
}

/** What `recordListServer(...).load` resolves to, safe for a Client Component. */
export type RecordListView<
  B extends RecordTypeBlocks,
  N extends string,
  Q,
  P extends { readonly items: readonly unknown[] },
  Cols,
> = Result<
  Plain<
    RecordListPage<
      Q,
      P,
      P["items"][number],
      RecordListCells<B, Cols>,
      RecordCan<B, N>
    >
  >
>;

export interface RecordListServer<
  B extends RecordTypeBlocks,
  N extends string,
  Q,
  P extends { readonly items: readonly unknown[] },
  Cols,
> {
  /**
   * Parses the page's `searchParams` and loads the page with its binding
   * columns, over the caller's `Db`. Call it outside `"use cache"`.
   */
  load(
    input: ListSearchParams | undefined,
    options?: ListParseOptions,
  ): Promise<RecordListView<B, N, Q, P, Cols>>;
}

/**
 * The server half of a `defineRecordList` for Next.js: it builds the record
 * type's block clients and the caller's permissions, then runs
 * `recordList.load`.
 *
 * ```ts
 * const customers = recordListServer(bsb, customerRecordList);
 * const view = await customers.load(await searchParams);
 * ```
 */
export function recordListServer<
  T extends string,
  B extends RecordTypeBlocks,
  N extends BindingName<B>,
  Q,
  P extends { readonly items: readonly unknown[] },
  Cols,
>(
  bsb: Pick<RecordServerHost, "context">,
  recordList: RecordList<T, B, N, Q, P, Cols>,
): RecordListServer<B, N, Q, P, Cols> {
  const { feature } = recordList;

  return {
    async load(input, options) {
      const ctx = await bsb.context();
      const permissions = await permissionsOf(feature, ctx.db);

      const result = await recordList.load(
        {
          db: ctx.db,
          clients: clientsOf(feature, ctx),
          ...(permissions.set === undefined
            ? {}
            : { permissions: permissions.set }),
        },
        input,
        options,
      );

      return result.ok ? { ...result, data: plainData(result.data) } : result;
    },
  };
}
