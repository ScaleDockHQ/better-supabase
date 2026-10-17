export {
  createSearch,
  type Embedder,
  type PendingEmbedding,
  type Search,
  type SearchHit,
  type SearchListOptions,
  type SearchOptions,
  type SearchQuery,
  type SearchUserItem,
} from "./search.ts";

export {
  SEARCH_SINK_DEFAULTS,
  searchSink,
  type SearchSinkAction,
  type SearchSinkOptions,
} from "./sink.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export { createCommandSearchController } from "./client.ts";

export type {
  CommandSearchActions,
  CommandSearchController,
  CommandSearchOptions,
  CommandSearchSnapshot,
} from "./client.ts";

export { searchBlock } from "./manifest.ts";
