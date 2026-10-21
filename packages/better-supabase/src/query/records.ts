import type { QueryClient, SkipToken } from "@tanstack/query-core";

import type { PermissionSet } from "../blocks/access/permissions.ts";
import type {
  SectionData,
  SectionOptions,
  SectionResult,
} from "../blocks/sections.ts";
import type { EventHub } from "../core/events.ts";
import type { AsyncResult, Result } from "../core/result.ts";
import type {
  FeatureBlocks,
  FeatureWriteInput,
  FeatureWriteOutput,
  RecordCan,
  RecordFeature,
  SectionWritesOf,
} from "../records/feature.ts";
import type {
  SectionName,
  SectionNamed,
  SectionSource,
} from "../records/sections.ts";
import type {
  MutationOptionsOf,
  QueriesOptions,
  QueryOptionsOf,
} from "./queries.ts";

import { sectionEventMatches } from "../blocks/sections.ts";
import { DbException } from "../core/errors.ts";
import {
  featureWrites,
  recordCan,
  recordPermissionKeys,
  recordSubject,
  runSectionWrite,
} from "../records/feature.ts";
import { findSection, loadSections } from "../records/sections.ts";
import { keyPart } from "./queries.ts";

/** The first key part of every record query. */
const RECORD_KEY = "bs-record";

/** The key part of a record's `can` query. */
const CAN_KEY = "$can";

/** Query options for each section of a feature, by section name. */
export type RecordSectionQueries<B extends FeatureBlocks, N extends string> = {
  readonly [S in N]: (
    id: string | SkipToken,
    options?: SectionOptions<SectionNamed<B, S>>,
  ) => QueryOptionsOf<SectionData<SectionNamed<B, S>>>;
};

/** Mutation options for each write of each section, by section and write. */
export type RecordWriteMutations<B extends FeatureBlocks, N extends string> = {
  readonly [S in N]: {
    readonly [W in SectionWritesOf<B, S>]: (
      id: string,
    ) => MutationOptionsOf<
      FeatureWriteInput<B, S, W>,
      FeatureWriteOutput<B, S, W>
    >;
  };
};

export interface RecordQueries<
  T extends string,
  B extends FeatureBlocks,
  N extends string,
> {
  /** Prefix of every key of this feature's queries. */
  readonly $key: readonly [typeof RECORD_KEY, T];
  /** The key of one record's queries, or of one of its sections. */
  key(id: string, section?: N): readonly unknown[];
  /** Query options per section, keyed `["bs-record", type, id, section]`. */
  readonly sections: RecordSectionQueries<B, N>;
  /**
   * Mutation options per section write; each one makes the section's queries of
   * that record stale.
   */
  readonly writes: RecordWriteMutations<B, N>;
  /** What the caller may do on each section, from the `access` client. */
  can(): QueryOptionsOf<RecordCan<B, N>>;
}

export interface RecordQueriesOptions extends QueriesOptions {
  /**
   * The access block's client, which loads the caller's keys for `can`. Without
   * it every flag is `true` and RLS decides.
   */
  readonly access?: {
    permissions(keys: readonly string[]): AsyncResult<PermissionSet>;
  };
}

function scoped(
  options: QueriesOptions,
  key: readonly unknown[],
): readonly unknown[] {
  return options.scope === undefined ? key : [...key, { scope: options.scope }];
}

async function unwrap<T>(result: PromiseLike<Result<T>>): Promise<T> {
  const settled = await result;

  if (!settled.ok) {
    throw new DbException(settled.error);
  }

  return settled.data;
}

/**
 * TanStack Query bindings of a generated feature, for apps that load records on
 * the client (Vite, Expo, TanStack Start): query options per section, mutation
 * options per section write, and the caller's `can` flags. Pass the block
 * clients keyed like the feature's blocks, such as `blocks(supabase)` from
 * `lib/blocks.ts`. A section that fails throws a `DbException`, like
 * `blockQueries`.
 *
 * ```ts
 * const customer = recordQueries(customerFeature, clients);
 * const comments = useQuery(customer.sections.comments(id));
 * const add = useMutation(customer.writes.comments.add(id));
 * ```
 */
export function recordQueries<
  T extends string,
  B extends FeatureBlocks,
  N extends SectionName<B>,
>(
  feature: RecordFeature<T, B> & { readonly sections: readonly N[] },
  clients: object,
  options: RecordQueriesOptions = {},
): RecordQueries<T, B, N> {
  const prefix = [RECORD_KEY, feature.type] as const;
  const names: readonly N[] = feature.sections;

  const source: SectionSource<B> = { blocks: feature.blocks, clients };

  const keyOf = (id: string, section?: string): readonly unknown[] =>
    section === undefined ? [...prefix, id] : [...prefix, id, section];

  const stale =
    options.staleTime === undefined ? {} : { staleTime: options.staleTime };

  const section =
    (name: N) =>
    (id: string | SkipToken, given?: unknown): QueryOptionsOf<unknown> => {
      const skip = typeof id !== "string";

      const queryKey = scoped(options, [
        ...prefix,
        ...(skip ? [] : [id, name]),
        ...(given === undefined ? [] : [keyPart(given)]),
      ]);

      // SAFETY: the key is tagged with the section's data, which `queryFn`
      // resolves to.
      return {
        queryKey: queryKey as QueryOptionsOf<unknown>["queryKey"],
        queryFn: skip
          ? id
          : async () => {
              const loaded: Readonly<Record<string, SectionResult<unknown>>> =
                await loadSections(
                  source,
                  recordSubject(feature, id),
                  [name],
                  // SAFETY: `given` is the options the section's `load` takes.
                  given === undefined
                    ? {}
                    : { options: { [name]: given } as never },
                );

              const result = loaded[name];

              if (result?.kind === "error") {
                throw new DbException(result.error);
              }

              return result?.kind === "ok" ? result.data : undefined;
            },
        meta: { bsTables: [] },
        ...stale,
      };
    };

  const write =
    (name: string, writeName: string) =>
    (id: string): MutationOptionsOf<unknown, unknown> => ({
      mutationKey: [...prefix, id, name, writeName],
      mutationFn: (input) =>
        unwrap(
          runSectionWrite(
            feature,
            clients,
            name,
            writeName,
            recordSubject(feature, id),
            input,
          ),
        ),
      onSuccess: (_data, _input, _result, context) =>
        context.client.invalidateQueries({ queryKey: keyOf(id, name) }),
    });

  // SAFETY: one query option per section and one mutation option per write,
  // as `RecordSectionQueries` and `RecordWriteMutations` map them.
  return {
    $key: prefix,
    key: keyOf,
    sections: Object.fromEntries(
      names.map((name) => [name, section(name)]),
    ) as never,
    writes: Object.fromEntries(
      featureWrites(feature).map(([name, writes]) => [
        name,
        Object.fromEntries(
          writes.map((writeName) => [writeName, write(name, writeName)]),
        ),
      ]),
    ) as never,
    can: () =>
      // SAFETY: the key is tagged with `RecordCan`, which `queryFn` resolves to.
      ({
        queryKey: scoped(options, [...prefix, CAN_KEY]) as never,
        queryFn: async () => {
          const keys = recordPermissionKeys(feature);

          const set =
            options.access === undefined || keys.length === 0
              ? undefined
              : await unwrap(options.access.permissions(keys));

          return recordCan<B, N>(feature, set);
        },
        meta: { bsTables: [] },
        ...stale,
      }),
  };
}

/**
 * Makes a feature's section queries stale when a block event that the section
 * lists in `events` arrives on `source.events`, for every record of the
 * feature. Returns a function that stops listening.
 */
export function invalidateOnRecordEvents(
  queryClient: QueryClient,
  source: { readonly events: EventHub },
  feature: Pick<RecordFeature, "blocks" | "type"> & {
    readonly sections: readonly string[];
  },
): () => void {
  const patterns = feature.sections.map(
    (name) =>
      [name, findSection(feature.blocks, name)?.section.events ?? []] as const,
  );

  return source.events.on("block", (event) => {
    const names = new Set(
      patterns
        .filter(([, events]) =>
          events.some((pattern) => sectionEventMatches(pattern, event.type)),
        )
        .map(([name]) => name),
    );

    if (names.size === 0) {
      return;
    }

    void queryClient.invalidateQueries({
      predicate: ({ queryKey }) =>
        queryKey[0] === RECORD_KEY &&
        queryKey[1] === feature.type &&
        names.has(String(queryKey[3])),
    });
  });
}
