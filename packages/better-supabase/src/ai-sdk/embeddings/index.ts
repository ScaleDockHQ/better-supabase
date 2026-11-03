export type {
  Embedder,
  KnowledgeHit,
} from "../../blocks/knowledge/knowledge.ts";

export {
  embeddingCacheMiddleware,
  type EmbeddingCacheMiddlewareOptions,
  embedWith,
  rerankHits,
  type EmbedWithOptions,
  modelName,
  type Reranker,
  rerankWith,
  type ResultsFilter,
  searchTool,
  type SearchToolOptions,
  type SearchToolResult,
  supabaseEmbed,
  type SupabaseAiSession,
  type SupabaseEmbedOptions,
  toSourceParts,
} from "./embeddings.ts";

export {
  drainEmbeddings,
  type EmbeddingBatch,
  type EmbeddingDrainResult,
  type EmbeddingJob,
  embeddingWorker,
  type EmbeddingWorkerOptions,
} from "./worker.ts";
