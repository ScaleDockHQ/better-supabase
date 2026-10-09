export {
  chunk,
  createKnowledge,
  // oxlint-disable-next-line typescript/no-deprecated -- the 0.6 export stays until 0.8.
  vectorLiteral,
  type ChunkOptions,
  type Embedder,
  type Knowledge,
  type KnowledgeChunk,
  type KnowledgeDocument,
  type KnowledgeHit,
  type KnowledgeOptions,
  type KnowledgeQuery,
  type KnowledgeScope,
  type KnowledgeSearchOptions,
  type KnowledgeStatus,
  type NewKnowledgeDocument,
} from "./knowledge.ts";
export { rpcTransport, sqlTransport } from "../../core/block-transport.ts";
export type { BlockTransport } from "../../core/block-transport.ts";
