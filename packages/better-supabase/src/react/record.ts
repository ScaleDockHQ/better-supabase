"use client";

import type { ReactNode } from "react";

import {
  createContext,
  createElement,
  use,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";

import type { BlockEnv } from "../blocks/block-env.ts";
import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { SubscriptionStatus } from "../realtime/index.ts";
import type { BindingName } from "../records/bindings.ts";
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
import type { RecordRef } from "../schema/types.ts";

import { createBlocks } from "../blocks/create-blocks.ts";
import { useController } from "../blocks/react-controller.ts";
import { useBlockEnv } from "../blocks/react-env.ts";
import { rpcTransport } from "../core/block-transport.ts";
import { dbError } from "../core/errors.ts";
import { createRecordController } from "../records/controller.ts";
import {
  plainData,
  recordCan,
  recordSubject,
  runBindingWrite,
} from "../records/record-type.ts";
import { OfflineContext } from "./offline.ts";

/** What a write resolves to: a `Result`, or a Server Action's `ActionResult`. */
type WriteSettled<T> =
  | Result<T>
  | { readonly ok: true; readonly data: T; readonly error: null }
  | { readonly ok: false; readonly data: null; readonly error: DbError };

/**
 * Server Actions for a record type's writes, such as `bsb.record(...).actions`
 * re-exported from a `"use server"` file. A write with none runs on the client
 * over the provider's supabase-js client.
 */
export type RecordWriteHandlers<
  B extends RecordTypeBlocks,
  N extends string,
> = {
  readonly [S in N]?: {
    readonly [W in BindingWritesOf<B, S>]?: (
      input: RecordWriteInput<RecordTypeWriteInput<B, S, W>>,
    ) => Promise<WriteSettled<Plain<RecordTypeWriteOutput<B, S, W>>>>;
  };
};

/** What the server loaded, such as `bsb.record(...).load(id)`. */
export interface RecordInitial<B extends RecordTypeBlocks, N extends string> {
  readonly bindings?: Partial<PlainBindings<B, N>>;
  readonly can?: RecordCan<B, N>;
}

export interface RecordProviderProps<
  B extends RecordTypeBlocks,
  N extends string,
> {
  /** The record's id. */
  readonly id: string;
  /** Bindings and flags the server loaded, shown until the client loads. */
  readonly initial?: RecordInitial<B, N>;
  /** Server Actions for the writes; the rest run on the client. */
  readonly writes?: RecordWriteHandlers<B, N>;
  /**
   * The private topic that hears of the record's changes, such as its block
   * events. A binding reloads when the topic carries one of its events.
   */
  readonly topic?: string | null;
  readonly children?: ReactNode;
}

export interface RecordState<B extends RecordTypeBlocks, N extends string> {
  readonly subject: RecordRef;
  /** Each binding settled, with Temporal values as ISO strings. */
  readonly bindings: Partial<PlainBindings<B, N>>;
  /** What the caller may do; every flag is `true` without `initial.can`. */
  readonly can: RecordCan<B, N>;
  readonly status: SubscriptionStatus;
  /**
   * `true` while the app is offline (`OfflineContext`): loads wait, the
   * bindings keep their last data and a write queues until the connection
   * returns. Absent until the provider is told the app's online state.
   */
  readonly offline?: boolean;
}

export interface RecordActionsOf<B extends RecordTypeBlocks, N extends string> {
  /** Loads the named bindings again, or every binding. */
  refresh(names?: readonly N[]): Promise<void>;
  /**
   * Runs one binding write, then loads that binding again. While offline, a
   * write queues in one slot per binding and write name: a later call replaces
   * its input and shares its promise, and the write runs once on reconnect.
   */
  write<const S extends N, const W extends BindingWritesOf<B, S>>(
    binding: S,
    write: W,
    input: RecordTypeWriteInput<B, S, W>,
  ): Promise<WriteSettled<Plain<RecordTypeWriteOutput<B, S, W>>>>;
}

/** The record context: `{ state, actions, meta }`. */
export interface RecordContextValue<
  T extends string,
  B extends RecordTypeBlocks,
  N extends string,
> {
  readonly state: RecordState<B, N>;
  readonly actions: RecordActionsOf<B, N>;
  readonly meta: { readonly feature: RecordType<T, B> };
}

/** A write that waits for the connection, and the promise its callers share. */
interface QueuedWrite {
  input: unknown;
  readonly promise: Promise<WriteSettled<unknown>>;
  readonly settle: (settled: WriteSettled<unknown>) => void;
  readonly run: (input: unknown) => Promise<WriteSettled<unknown>>;
}

type AnyHandlers = Readonly<
  Record<
    string,
    | Readonly<
        Record<
          string,
          | ((
              input: RecordWriteInput<unknown>,
            ) => Promise<WriteSettled<unknown>>)
          | undefined
        >
      >
    | undefined
  >
>;

export interface RecordProviderKit<
  T extends string,
  B extends RecordTypeBlocks,
  N extends string,
> {
  /** Loads the record's bindings and follows `topic` for its children. */
  readonly RecordProvider: (props: RecordProviderProps<B, N>) => ReactNode;
  /** The record context; throws outside the provider. */
  readonly useRecord: () => RecordContextValue<T, B, N>;
}

function clientsOf(
  env: BlockEnv,
  feature: Pick<RecordType, "blocks" | "config">,
): object {
  // The client's slices win; the record's own cover the blocks it binds.
  const config =
    env.config === undefined || feature.config === undefined
      ? (env.config ?? feature.config)
      : { ...feature.config, ...env.config };

  const files = { storage: env.supabase.storage };

  return createBlocks(
    {
      transport: rpcTransport(env.supabase),
      ...files,
      tenant: env.tenant,
      ...(config === undefined ? {} : { config }),
    },
    feature.blocks,
  );
}

/**
 * A provider and hook for one generated record type (ADR 0030): the provider
 * holds a record controller over the client's blocks and the hook reads `{
 * state, actions, meta }`, so the record page's cards compose without prop
 * drilling. Writes run through `writes` (Server Actions) when given, else on
 * the client.
 *
 * ```tsx
 * const { RecordProvider, useRecord } =
 *   createRecordProvider(customerRecord);
 *
 * <RecordProvider id={id} initial={view} writes={customerActions}>
 *   <CommentsCard />
 * </RecordProvider>;
 * ```
 */
export function createRecordProvider<
  T extends string,
  B extends RecordTypeBlocks,
  N extends BindingName<B>,
>(
  feature: RecordType<T, B> & { readonly bindings: readonly N[] },
): RecordProviderKit<T, B, N> {
  const Context = createContext<RecordContextValue<T, B, N> | null>(null);
  const names: readonly N[] = feature.bindings;

  function RecordProvider(props: RecordProviderProps<B, N>): ReactNode {
    const { id, initial, writes, topic = null, children } = props;
    const env = useBlockEnv();
    const clients = useMemo(() => clientsOf(env, feature), [env]);
    const subject = useMemo(() => recordSubject(feature, id), [id]);

    const offline = useContext(OfflineContext);
    const [queued] = useState(() => new Map<string, QueuedWrite>());

    const { controller, view } = useController(
      () =>
        createRecordController({
          source: { blocks: feature.blocks, clients },
          auth: env.auth,
          ports: env.ports,
          subject,
          bindings: names,
          topic,
          offline,
        }),
      [clients, env, subject, topic],
    );

    useEffect(() => {
      controller.actions.setOffline(offline);

      if (offline) {
        return;
      }

      const waiting = [...queued.values()];
      queued.clear();

      for (const each of waiting) {
        void each.run(each.input).then(each.settle);
      }
    }, [controller, offline, queued]);

    useEffect(() => {
      const waiting = queued;

      return () => {
        for (const each of waiting.values()) {
          each.settle({
            ok: false,
            data: null,
            error: dbError("network", "The queued write was cancelled.", {
              status: 503,
            }),
          });
        }

        waiting.clear();
      };
    }, [queued]);

    const value = useMemo((): RecordContextValue<T, B, N> => {
      const bindings: Partial<PlainBindings<B, N>> = {
        ...initial?.bindings,
        // SAFETY: `plainData` maps each binding's Temporal values to strings,
        // as `PlainBindings` types them.
        ...(plainData(view.bindings ?? {}) as Partial<PlainBindings<B, N>>),
      };

      const perform = async (
        binding: string,
        name: string,
        input: unknown,
      ): Promise<WriteSettled<unknown>> => {
        // SAFETY: `writes` holds one handler per binding write, each taking
        // `{ id, input }`, which `AnyHandlers` reads by name.
        const handler = (writes as AnyHandlers | undefined)?.[binding]?.[name];

        const settled =
          handler === undefined
            ? await runBindingWrite(
                feature,
                clients,
                binding,
                name,
                subject,
                input,
              )
            : await handler({ id, input });

        if (settled.ok) {
          // SAFETY: `binding` is one of the record type's bindings.
          await view.refresh([binding as N]);

          return { ...settled, data: plainData(settled.data) };
        }

        return settled;
      };

      const write = (
        binding: string,
        name: string,
        input: unknown,
      ): Promise<WriteSettled<unknown>> => {
        if (!offline) {
          return perform(binding, name, input);
        }

        const key = `${binding}.${name}`;
        const waiting = queued.get(key);

        if (waiting !== undefined) {
          waiting.input = input;

          return waiting.promise;
        }

        let settle: QueuedWrite["settle"] = () => undefined;

        const promise = new Promise<WriteSettled<unknown>>((resolve) => {
          settle = resolve;
        });

        queued.set(key, {
          input,
          promise,
          settle,
          run: (latest) => perform(binding, name, latest),
        });

        return promise;
      };

      return {
        state: {
          subject,
          bindings,
          can: initial?.can ?? recordCan<B, N>(feature, undefined),
          status: view.status,
          ...(view.offline === undefined ? {} : { offline: view.offline }),
        },
        // SAFETY: `write` runs the write the binding and name select and
        // resolves to its plain output, as `RecordActionsOf` types it.
        actions: {
          refresh: view.refresh,
          write: write as RecordActionsOf<B, N>["write"],
        },
        meta: { feature },
      };
    }, [clients, id, initial, offline, queued, subject, view, writes]);

    return createElement(Context, { value }, children);
  }

  function useRecord(): RecordContextValue<T, B, N> {
    const value = use(Context);

    if (value === null) {
      throw new Error(
        `better-supabase: wrap the ${feature.type} record in its <RecordProvider>`,
      );
    }

    return value;
  }

  return { RecordProvider, useRecord };
}
