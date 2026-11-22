export {
  chunk,
  type ChunkPosition,
  createKnowledge,
  type ChunkOptions,
  type EmbedResult,
  type Embedder,
  type EmbedderV1,
  type EmbedderV2,
  embedVectors,
  type Knowledge,
  type KnowledgeChunk,
  type KnowledgeDocument,
  type KnowledgeHit,
  type KnowledgeHooks,
  type KnowledgeOptions,
  type KnowledgeQuery,
  type KnowledgeScope,
  type KnowledgeSearchOptions,
  type KnowledgeStatus,
  type KnowledgeSubject,
  type NewKnowledgeDocument,
  textExtract,
} from "./knowledge.ts";

export {
  DOCX_TYPE,
  PDF_TYPE,
  docxExtractor,
  extractors,
  pdfExtractor,
  type DocxModule,
  type ExtractorFile,
  type KnowledgeExtractor,
  type PdfModule,
} from "./extractors.ts";

export {
  createUrlSource,
  htmlToText,
  type UrlIngestInput,
  type UrlResyncResult,
  type UrlSource,
  type UrlSourceOptions,
} from "./url-source.ts";

export type {
  KnowledgeCollection,
  KnowledgeCollectionGrant,
  KnowledgeCollections,
  KnowledgeGrantee,
  KnowledgeVisibility,
  NewKnowledgeCollection,
} from "./collections.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export { knowledgeBlock } from "./manifest.ts";
