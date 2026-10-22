"use client";

import type { ReactNode } from "react";

import { createContext, createElement, use, useMemo } from "react";

import type { BlockEnv } from "../blocks/block-env.ts";
import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { SubscriptionStatus } from "../realtime/index.ts";
import type {
  FeatureBlocks,
  FeatureWriteInput,
  FeatureWriteOutput,
  Plain,
  PlainSections,
  RecordCan,
  RecordFeature,
  RecordWriteInput,
  SectionWritesOf,
} from "../records/feature.ts";
import type { SectionName } from "../records/sections.ts";
import type { RecordRef } from "../schema/types.ts";

import { createBlocks } from "../blocks/create-blocks.ts";
import { useController } from "../blocks/react-controller.ts";
import { useBlockEnv } from "../blocks/react-env.ts";
import { rpcTransport } from "../core/block-transport.ts";
import { createRecordController } from "../records/controller.ts";
import {
  plainData,
  recordCan,
  recordSubject,
  runSectionWrite,
} from "../records/feature.ts";

/** What a write resolves to: a `Result`, or a Server Action's `ActionResult`. */
type WriteSettled<T> =
  | Result<T>
  | { readonly ok: true; readonly data: T; readonly error: null }
  | { readonly ok: false; readonly data: null; readonly error: DbError };

/**
 * Server Actions for a feature's writes, such as `recordServer(...).actions`
 * re-exported from a `"use server"` file. A write with none runs on the client
 * over the provider's supabase-js client.
 */
export type RecordWriteHandlers<B extends FeatureBlocks, N extends string> = {
  readonly [S in N]?: {
    readonly [W in SectionWritesOf<B, S>]?: (
      input: RecordWriteInput<FeatureWriteInput<B, S, W>>,
    ) => Promise<WriteSettled<Plain<FeatureWriteOutput<B, S, W>>>>;
  };
};

/** What the server loaded, such as `recordServer(...).load(id)`. */
export interface RecordInitial<B extends FeatureBlocks, N extends string> {
  readonly sections?: Partial<PlainSections<B, N>>;
  readonly can?: RecordCan<B, N>;
}

export interface RecordProviderProps<
  B extends FeatureBlocks,
  N extends string,
> {
  /** The record's id. */
  readonly id: string;
  /** Sections and flags the server loaded, shown until the client loads. */
  readonly initial?: RecordInitial<B, N>;
  /** Server Actions for the writes; the rest run on the client. */
  readonly writes?: RecordWriteHandlers<B, N>;
  /**
   * The private topic that hears of the record's changes, such as its block
   * events. A section reloads when the topic carries one of its events.
   */
  readonly topic?: string | null;
  readonly children?: ReactNode;
}

export interface RecordState<B extends FeatureBlocks, N extends string> {
  readonly subject: RecordRef;
  /** Each section settled, with Temporal values as ISO strings. */
  readonly sections: Partial<PlainSections<B, N>>;
  /** What the caller may do; every flag is `true` without `initial.can`. */
  readonly can: RecordCan<B, N>;
  readonly status: SubscriptionStatus;
}

export interface RecordActionsOf<B extends FeatureBlocks, N extends string> {
  /** Loads the named sections again, or every section. */
  refresh(names?: readonly N[]): Promise<void>;
  /** Runs one section write, then loads that section again. */
  write<const S extends N, const W extends SectionWritesOf<B, S>>(
    section: S,
    write: W,
    input: FeatureWriteInput<B, S, W>,
  ): Promise<WriteSettled<Plain<FeatureWriteOutput<B, S, W>>>>;
}

/** The record context: `{ state, actions, meta }`. */
export interface RecordContextValue<
  T extends string,
  B extends FeatureBlocks,
  N extends string,
> {
  readonly state: RecordState<B, N>;
  readonly actions: RecordActionsOf<B, N>;
  readonly meta: { readonly feature: RecordFeature<T, B> };
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
  B extends FeatureBlocks,
  N extends string,
> {
  /** Loads the record's sections and follows `topic` for its children. */
  readonly RecordProvider: (props: RecordProviderProps<B, N>) => ReactNode;
  /** The record context; throws outside the provider. */
  readonly useRecord: () => RecordContextValue<T, B, N>;
}

function clientsOf(
  env: BlockEnv,
  feature: Pick<RecordFeature, "blocks" | "config">,
): object {
  const config = env.config ?? feature.config;
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
 * A provider and hook for one generated feature (ADR 0030): the provider holds
 * a record controller over the client's blocks and the hook reads `{ state,
 * actions, meta }`, so the record page's cards compose without prop drilling.
 * Writes run through `writes` (Server Actions) when given, else on the client.
 *
 * ```tsx
 * const { RecordProvider, useRecord } =
 *   createRecordProvider(customerFeature);
 *
 * <RecordProvider id={id} initial={view} writes={customerActions}>
 *   <CommentsCard />
 * </RecordProvider>;
 * ```
 */
export function createRecordProvider<
  T extends string,
  B extends FeatureBlocks,
  N extends SectionName<B>,
>(
  feature: RecordFeature<T, B> & { readonly sections: readonly N[] },
): RecordProviderKit<T, B, N> {
  const Context = createContext<RecordContextValue<T, B, N> | null>(null);
  const names: readonly N[] = feature.sections;

  function RecordProvider(props: RecordProviderProps<B, N>): ReactNode {
    const { id, initial, writes, topic = null, children } = props;
    const env = useBlockEnv();
    const clients = useMemo(() => clientsOf(env, feature), [env]);
    const subject = useMemo(() => recordSubject(feature, id), [id]);

    const { view } = useController(
      () =>
        createRecordController({
          source: { blocks: feature.blocks, clients },
          auth: env.auth,
          ports: env.ports,
          subject,
          sections: names,
          topic,
        }),
      [clients, env, subject, topic],
    );

    const value = useMemo((): RecordContextValue<T, B, N> => {
      const sections: Partial<PlainSections<B, N>> = {
        ...initial?.sections,
        // SAFETY: `plainData` maps each section's Temporal values to strings,
        // as `PlainSections` types them.
        ...(plainData(view.sections ?? {}) as Partial<PlainSections<B, N>>),
      };

      const write = async (
        section: string,
        name: string,
        input: unknown,
      ): Promise<WriteSettled<unknown>> => {
        // SAFETY: `writes` holds one handler per section write, each taking
        // `{ id, input }`, which `AnyHandlers` reads by name.
        const handler = (writes as AnyHandlers | undefined)?.[section]?.[name];

        const settled =
          handler === undefined
            ? await runSectionWrite(
                feature,
                clients,
                section,
                name,
                subject,
                input,
              )
            : await handler({ id, input });

        if (settled.ok) {
          // SAFETY: `section` is one of the feature's sections.
          await view.refresh([section as N]);

          return { ...settled, data: plainData(settled.data) };
        }

        return settled;
      };

      return {
        state: {
          subject,
          sections,
          can: initial?.can ?? recordCan<B, N>(feature, undefined),
          status: view.status,
        },
        // SAFETY: `write` runs the write the section and name select and
        // resolves to its plain output, as `RecordActionsOf` types it.
        actions: {
          refresh: view.refresh,
          write: write as RecordActionsOf<B, N>["write"],
        },
        meta: { feature },
      };
    }, [clients, id, initial, subject, view, writes]);

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
