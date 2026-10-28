export {
  createCatalog,
  PRODUCT_KINDS,
  PRODUCT_STATUSES,
  type Catalog,
  type CatalogOptions,
  type CategoryInput,
  type ChannelInput,
  type ChannelProduct,
  type ChannelProductsOptions,
  type CollectionInput,
  type LocaleOptions,
  type LocalizedProduct,
  type LocalizedVariant,
  type MatrixVariant,
  type OptionInput,
  type OptionMatrix,
  type OptionMatrixInput,
  type OptionMatrixOptions,
  type OptionValue,
  type Price,
  type PriceInput,
  type PriceListInput,
  type ProductInput,
  type ProductPatch,
  type ProductKind,
  type ProductMedia,
  type ProductMediaInput,
  type ProductStatus,
  type ProductTranslation,
  type SavedCategory,
  type SavedChannel,
  type SavedCollection,
  type SavedOption,
  type SavedPrice,
  type SavedProduct,
  type SavedProductMedia,
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

export { productInputSchema } from "./schemas.ts";
