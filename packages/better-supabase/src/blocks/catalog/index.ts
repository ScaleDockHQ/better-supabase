export {
  catalogSubjects,
  createCatalog,
  PRODUCT_KINDS,
  PRODUCT_STATUSES,
  type Catalog,
  type CatalogOptions,
  type CatalogSubjectsOptions,
  type CategoryInput,
  type CollectionInput,
  type OptionInput,
  type OptionValue,
  type Price,
  type PriceInput,
  type PriceListInput,
  type ProductInput,
  type ProductKind,
  type ProductStatus,
  type SavedCategory,
  type SavedCollection,
  type SavedOption,
  type SavedPrice,
  type SavedProduct,
  type SavedVariant,
  type StatusChange,
  type VariantInput,
  type VariantPriceOptions,
} from "./catalog.ts";

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

export { catalogBlock } from "./manifest.ts";

export { catalogEvents } from "./events.ts";

export type { CatalogEvents } from "./events.ts";
