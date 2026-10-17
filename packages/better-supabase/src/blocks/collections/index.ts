export {
  type Collection,
  type CollectionEntry,
  type CollectionEntryCursor,
  type CollectionEntryPage,
  type CollectionListOptions,
  COLLECTION_SCOPES,
  type Collections,
  type CollectionScope,
  type CollectionsOptions,
  type CollectionSubject,
  createCollections,
  type CreateCollectionInput,
  MAX_COLLECTION_IDS,
  type RenameCollectionInput,
  type Star,
} from "./collections.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
  type BlockHooks,
  type BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
  type BlockTransport,
  type RpcClient,
} from "../../core/block-transport.ts";

export { collectionsBlock } from "./manifest.ts";

export { collectionsEvents } from "./events.ts";

export type { CollectionsEvents } from "./events.ts";
