import {
  embedMany,
  type EmbeddingModel,
  jsonSchema,
  rerank,
  type RerankingModel,
  type SourceDocumentUIPart,
  type Tool,
  tool,
} from "ai";

import type {
  Embedder,
  Knowledge,
  KnowledgeHit,
  KnowledgeSearchOptions,
} from "../../blocks/knowledge/knowledge.ts";

import { DbException } from "../../core/db-exception.ts";

type ProviderOptions = Parameters<typeof embedMany>[0]["providerOptions"];

export interface EmbedWithOptions {
  /** Concurrent calls when the values need more than one. Default 4. */
  readonly maxParallelCalls?: number;
  readonly providerOptions?: ProviderOptions;
  /** The name stored with each embedding; the provider and model id by default. */
  readonly name?: string;
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
): Embedder {
  return {
    model: options.name ?? modelName(model),
    embed: async (values, embedOptions) => {
      if (values.length === 0) return [];
      const { embeddings } = await embedMany({
        model,
        values: [...values],
        maxParallelCalls: options.maxParallelCalls ?? 4,
        ...(options.providerOptions === undefined
          ? {}
          : { providerOptions: options.providerOptions }),
        ...(embedOptions?.signal === undefined
          ? {}
          : { abortSignal: embedOptions.signal }),
      });
      return embeddings;
    },
  };
}

export type Reranker = (
  query: string,
  hits: readonly KnowledgeHit[],
  options?: { readonly signal?: AbortSignal },
) => Promise<readonly KnowledgeHit[]>;

/** Reorders search hits with a reranking model, keeping the best `topN`. */
export function rerankWith(
  model: RerankingModel,
  options: { readonly topN?: number } = {},
): Reranker {
  return async (query, hits, rerankOptions) => {
    if (hits.length <= 1) return hits;
    const { ranking } = await rerank({
      model,
      query,
      documents: hits.map((hit) => hit.content),
      ...(options.topN === undefined ? {} : { topN: options.topN }),
      ...(rerankOptions?.signal === undefined
        ? {}
        : { abortSignal: rerankOptions.signal }),
    });
    return ranking.flatMap((entry) => {
      const hit = hits[entry.originalIndex];
      return hit === undefined ? [] : [{ ...hit, score: entry.score }];
    });
  };
}

export interface SearchToolOptions extends Omit<
  KnowledgeSearchOptions,
  "signal"
> {
  readonly description?: string;
  /** Reranks the hits before the model sees them. */
  readonly rerank?: Reranker;
  /** Called with the hits, to stream them as source parts. */
  readonly onHits?: (hits: readonly KnowledgeHit[]) => void;
}

export interface SearchToolResult {
  readonly results: readonly {
    readonly id: string;
    readonly title: string;
    readonly content: string;
  }[];
}

/**
 * A tool that searches the knowledge base as the caller. Each result id
 * is `documentId#index`, the `sourceId` that `toSourceParts` gives it.
 */
export function searchTool(
  knowledge: Knowledge,
  organizationId: string,
  options: SearchToolOptions = {},
): Tool<{ query: string }, SearchToolResult> {
  const { description, rerank: reorder, onHits, ...search } = options;
  return tool({
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
    execute: async ({ query }, { abortSignal }): Promise<SearchToolResult> => {
      const found = await knowledge.search(organizationId, query, {
        ...search,
        ...(abortSignal === undefined ? {} : { signal: abortSignal }),
      });
      if (!found.ok) throw new DbException(found.error);
      const hits = reorder
        ? await reorder(
            query,
            found.data,
            abortSignal === undefined ? undefined : { signal: abortSignal },
          )
        : found.data;
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
    if (seen.has(hit.documentId)) continue;
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
  readonly ai?: {
    readonly Session?: new (model: string) => SupabaseAiSession;
  };
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
