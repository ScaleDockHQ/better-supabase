import type {
  EmbeddingModel,
  EmbeddingModelMiddleware,
  RerankingModel,
  SourceDocumentUIPart,
  Tool,
} from "ai";

import { embed, embedMany, jsonSchema, rerank, tool } from "ai";

import type { AiCache } from "../../blocks/ai-cache/ai-cache.ts";
import type {
  Embedder,
  EmbedderV2,
  Knowledge,
  KnowledgeHit,
  KnowledgeSearchOptions,
} from "../../blocks/knowledge/knowledge.ts";
import type { DbError } from "../../core/errors.ts";

import { cacheKey } from "../../blocks/ai-cache/ai-cache.ts";
import { DbException } from "../../core/db-exception.ts";

type ProviderOptions = Parameters<typeof embedMany>[0]["providerOptions"];

export interface EmbedWithOptions {
  /** Concurrent calls when the values need more than one. Default 4. */
  readonly maxParallelCalls?: number;
  readonly providerOptions?: ProviderOptions;
  /** The name stored with each embedding; the provider and model id by default. */
  readonly name?: string;
  /**
   * The output size to request from the model (`embed` and `embedMany`
   * `dimensions`). An explicit setting in `providerOptions` wins.
   */
  readonly dimensions?: number;
}

/** The name of an SDK model: the string itself, or `provider/modelId`. */
export function modelName(
  model: string | { readonly provider: string; readonly modelId: string },
): string {
  return typeof model === "string"
    ? model
    : `${model.provider}/${model.modelId}`;
}

/** An `Embedder` for the knowledge and memory blocks over `embedMany`. */
export function embedWith(
  model: EmbeddingModel,
  options: EmbedWithOptions = {},
): EmbedderV2 {
  return {
    apiVersion: 2,
    model: options.name ?? modelName(model),
    embed: async (values, embedOptions) => {
      if (values.length === 0) {
        return { embeddings: [] };
      }

      const shared = {
        model,
        ...(options.providerOptions === undefined
          ? {}
          : { providerOptions: options.providerOptions }),
        ...(options.dimensions === undefined
          ? {}
          : { dimensions: options.dimensions }),
        ...(embedOptions?.signal === undefined
          ? {}
          : { abortSignal: embedOptions.signal }),
      };

      const [only] = values;

      if (values.length === 1 && only !== undefined) {
        const { embedding, usage } = await embed({ ...shared, value: only });

        return { embeddings: [embedding], usage: { tokens: usage.tokens } };
      }

      const { embeddings, usage } = await embedMany({
        ...shared,
        values: [...values],
        maxParallelCalls: options.maxParallelCalls ?? 4,
      });

      return { embeddings, usage: { tokens: usage.tokens } };
    },
  };
}

export interface EmbeddingCacheMiddlewareOptions {
  /** The AI cache block with a service transport. */
  readonly cache: Pick<AiCache, "get" | "upsert">;
  /** Seconds an entry lives, capped by the module's `maxTtl`. */
  readonly ttl: number;
  /** Keeps tenants' entries apart, so `clear` and tenant deletion find them. */
  readonly organizationId?: string;
  /** Called when the cache can't be read or written; the call still runs. */
  readonly onError?: (error: DbError) => void;
}

type EmbedCall = Parameters<
  NonNullable<EmbeddingModelMiddleware["wrapEmbed"]>
>[0];

/**
 * A `wrapEmbeddingModel` middleware that answers repeated values from the AI
 * cache block (kind `embed`). Each value has its own entry, keyed by the
 * tenant, provider, model, dimensions, provider options and the value's hash,
 * so a call with some cached values only sends the others to the model. A cache
 * that fails only costs the lookup.
 */
export function embeddingCacheMiddleware(
  options: EmbeddingCacheMiddlewareOptions,
): EmbeddingModelMiddleware {
  const keyOf = (call: EmbedCall, value: string): Promise<string> =>
    cacheKey({
      type: "embed",
      tenant: options.organizationId ?? null,
      provider: call.model.provider,
      model: call.model.modelId,
      dimensions: call.params.dimensions ?? null,
      providerOptions: call.params.providerOptions ?? null,
      value,
    });

  const isVector = (value: unknown): value is number[] =>
    Array.isArray(value) && value.every((x) => typeof x === "number");

  return {
    specificationVersion: "v4",
    wrapEmbed: async (call) => {
      const { values } = call.params;
      const keys = await Promise.all(values.map((v) => keyOf(call, v)));

      const found = await Promise.all(
        keys.map(async (key) => {
          const entry = await options.cache.get(key);

          if (!entry.ok) {
            options.onError?.(entry.error);

            return;
          }

          return isVector(entry.data?.value) ? entry.data.value : undefined;
        }),
      );

      const missing = found.flatMap((vector, index) =>
        vector === undefined ? [index] : [],
      );

      if (missing.length === 0) {
        return { embeddings: found.filter(isVector), warnings: [] };
      }

      const result = await call.model.doEmbed({
        ...call.params,
        values: missing.map((index) => values[index] ?? ""),
      });

      await Promise.all(
        missing.map(async (index, position) => {
          const vector = result.embeddings[position];
          const key = keys[index];

          if (vector === undefined || key === undefined) {
            return;
          }

          found[index] = vector;

          const saved = await options.cache.upsert({
            key,
            value: vector,
            options: {
              ttl: options.ttl,
              kind: "embed",
              model: `${call.model.provider}/${call.model.modelId}`,
              ...(options.organizationId === undefined
                ? {}
                : { organizationId: options.organizationId }),
            },
          });

          if (!saved.ok) {
            options.onError?.(saved.error);
          }
        }),
      );

      return { ...result, embeddings: found.filter(isVector) };
    },
  };
}

/**
 * Reorders the hits of any search (the vector search of the search block, a
 * memory lookup, a SQL function) with a reranking model. `text` reads the text
 * to rank from a hit, and the hits keep their other fields.
 */
export function rerankHits<T>(
  model: RerankingModel,
  options: {
    readonly topN?: number;
    readonly text: (hit: T) => string;
    /** Writes the rerank score onto the hit; the hit is kept as is by default. */
    readonly withScore?: (hit: T, score: number) => T;
  },
): (
  query: string,
  hits: readonly T[],
  rerankOptions?: { readonly signal?: AbortSignal },
) => Promise<readonly T[]> {
  return async (query, hits, rerankOptions) => {
    if (hits.length <= 1) {
      return hits;
    }

    const { ranking } = await rerank({
      model,
      query,
      documents: hits.map(options.text),
      ...(options.topN === undefined ? {} : { topN: options.topN }),
      ...(rerankOptions?.signal === undefined
        ? {}
        : { abortSignal: rerankOptions.signal }),
    });

    return ranking.flatMap((entry) => {
      const hit = hits[entry.originalIndex];

      if (hit === undefined) {
        return [];
      }

      return [options.withScore ? options.withScore(hit, entry.score) : hit];
    });
  };
}

export type Reranker = (
  query: string,
  hits: readonly KnowledgeHit[],
  options?: {
    readonly signal?: AbortSignal;
    /** The tenant of the search, so the rerank call is metered for it. */
    readonly organizationId?: string;
  },
) => Promise<readonly KnowledgeHit[]>;

/** Reorders search hits with a reranking model, keeping the best `topN`. */
export function rerankWith(
  model: RerankingModel,
  options: { readonly topN?: number } = {},
): Reranker {
  return async (query, hits, rerankOptions) => {
    if (hits.length <= 1) {
      return hits;
    }

    const { ranking } = await rerank({
      model,
      query,
      documents: hits.map((hit) => hit.content),
      ...(options.topN === undefined ? {} : { topN: options.topN }),
      ...(rerankOptions?.signal === undefined
        ? {}
        : { abortSignal: rerankOptions.signal }),
      ...(rerankOptions?.organizationId === undefined
        ? {}
        : {
            runtimeContext: { organizationId: rerankOptions.organizationId },
            telemetry: { includeRuntimeContext: { organizationId: true } },
          }),
    });

    return ranking.flatMap((entry) => {
      const hit = hits[entry.originalIndex];

      return hit === undefined ? [] : [{ ...hit, score: entry.score }];
    });
  };
}

/**
 * Keeps the items of a search the caller may read. A tool applies it before
 * anything else sees the items: the reranker, `onHits` and the model. A throw
 * fails the tool call, so no items reach the model.
 */
export type ResultsFilter<T, C = { readonly query: string }> = (
  items: readonly T[],
  context: C,
) => readonly T[] | PromiseLike<readonly T[]>;

export interface SearchToolOptions extends Omit<
  KnowledgeSearchOptions,
  "signal"
> {
  readonly description?: string;
  /** Drops the hits the caller may not read, such as by a permission. */
  readonly results?: ResultsFilter<KnowledgeHit>;
  /** Reranks the hits before the model sees them. */
  readonly rerank?: Reranker;
  /** Called with the hits, to stream them as source parts. */
  readonly onHits?: (hits: readonly KnowledgeHit[]) => void;
  /**
   * Sends the model only each result's `id` and its content cut to
   * `maxCharacters`; the tool's output (and `onHits`) still has the full
   * results. Default: the model gets the whole output.
   */
  readonly modelOutput?: { readonly maxCharacters: number };
}

export interface SearchToolResult {
  readonly results: readonly {
    readonly id: string;
    readonly title: string;
    readonly content: string;
  }[];
}

/**
 * A tool that searches the knowledge base as the caller. Each result id is
 * `documentId#index`, the `sourceId` that `toSourceParts` gives it.
 */
export function searchTool(
  knowledge: Knowledge,
  organizationId: string,
  options: SearchToolOptions = {},
): Tool<{ query: string }, SearchToolResult> {
  const {
    description,
    results,
    rerank: reorder,
    onHits,
    modelOutput,
    ...search
  } = options;

  return tool({
    strict: true,
    description:
      description ??
      "Search the knowledge base for passages relevant to a query. Cite results by their id.",
    inputSchema: jsonSchema<{ query: string }>({
      type: "object",
      properties: {
        query: { type: "string", description: "What to look for" },
      },
      required: ["query"],
      additionalProperties: false,
    }),
    ...(modelOutput === undefined
      ? {}
      : {
          toModelOutput: ({ output }) => ({
            type: "json",
            value: {
              results: output.results.map((entry) => ({
                id: entry.id,
                content: entry.content.slice(0, modelOutput.maxCharacters),
              })),
            },
          }),
        }),
    execute: async ({ query }, { abortSignal }): Promise<SearchToolResult> => {
      const found = await knowledge.search({
        organizationId,
        query,
        ...search,
        ...(abortSignal === undefined ? {} : { signal: abortSignal }),
      });

      if (!found.ok) {
        throw new DbException(found.error);
      }

      const readable = results
        ? await results(found.data, { query })
        : found.data;

      const hits = reorder
        ? await reorder(query, readable, {
            organizationId,
            ...(abortSignal === undefined ? {} : { signal: abortSignal }),
          })
        : readable;

      onHits?.(hits);

      return {
        results: hits.map((hit) => ({
          id: sourceId(hit),
          title: hit.title,
          content: hit.content,
        })),
      };
    },
  });
}

const sourceId = (hit: KnowledgeHit): string =>
  `${hit.documentId}#${String(hit.index)}`;

/** One `source-document` part per document among the hits, in hit order. */
export function toSourceParts(
  hits: readonly KnowledgeHit[],
): SourceDocumentUIPart[] {
  const seen = new Set<string>();
  const parts: SourceDocumentUIPart[] = [];

  for (const hit of hits) {
    if (seen.has(hit.documentId)) {
      continue;
    }

    seen.add(hit.documentId);
    parts.push({
      type: "source-document",
      sourceId: sourceId(hit),
      mediaType: "text/plain",
      title: hit.title,
    });
  }

  return parts;
}

/** `Supabase.ai.Session` in Supabase Edge Functions, typed structurally. */
export interface SupabaseAiSession {
  run(
    input: string,
    options: { readonly mean_pool: boolean; readonly normalize: boolean },
  ): Promise<unknown>;
}

export interface SupabaseEmbedOptions {
  /** The built-in model. Default `gte-small` (384 dimensions). */
  readonly model?: string;
  /** A session to use instead of `new Supabase.ai.Session(model)`. */
  readonly session?: SupabaseAiSession;
}

interface SupabaseGlobal {
  readonly ai?: { readonly Session?: new (model: string) => SupabaseAiSession };
}

function supabaseSession(model: string): SupabaseAiSession {
  // SAFETY: every member is optional and `Session` is checked before use.
  const Session = (globalThis as { Supabase?: SupabaseGlobal }).Supabase?.ai
    ?.Session;

  if (typeof Session !== "function") {
    throw new TypeError(
      "supabaseEmbed runs in Supabase Edge Functions, where Supabase.ai.Session exists; pass session elsewhere",
    );
  }

  return new Session(model);
}

/**
 * An `Embedder` over the model built into Supabase Edge Functions. Set the
 * module's `dimensions` option to the model's size (384 for `gte-small`).
 */
export function supabaseEmbed(options: SupabaseEmbedOptions = {}): Embedder {
  const name = options.model ?? "gte-small";
  let session = options.session;

  return {
    apiVersion: 1,
    model: `supabase/${name}`,
    embed: async (values) => {
      session ??= supabaseSession(name);
      const vectors: number[][] = [];

      for (const value of values) {
        const output = await session.run(value, {
          mean_pool: true,
          normalize: true,
        });

        if (
          !Array.isArray(output) ||
          !output.every((x) => typeof x === "number")
        ) {
          throw new TypeError(
            `Supabase.ai.Session returned no vector for ${name}`,
          );
        }

        vectors.push(output);
      }

      return vectors;
    },
  };
}
