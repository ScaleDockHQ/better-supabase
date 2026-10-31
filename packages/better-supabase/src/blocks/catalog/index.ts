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
  catalogDiscounts,
  DISCOUNT_GROUP_KINDS,
  type CatalogDiscounts,
  type DiscountGroupInput,
  type DiscountGroupKind,
  type DiscountRuleInput,
  type ResolveDiscountOptions,
  type ResolvedDiscount,
} from "./discounts.ts";

export {
  catalogSupply,
  IDENTIFIER_TYPES,
  RELATION_KINDS,
  type CatalogSupply,
  type FindByIdentifierOptions,
  type IdentifierInput,
  type IdentifierMatch,
  type IdentifierType,
  type MappedSupplierItem,
  type MappingField,
  type PromotedSupplierItem,
  type RelationInput,
  type RelationKind,
  type SavedIdentifier,
  type SavedSupplierItem,
  type SupplierItem,
  type SupplierItemInput,
  type SupplierItemMapping,
  type SupplierItemMappingInput,
  type SupplierItemSearchOptions,
  type VariantIdentifier,
  type VariantRelation,
} from "./supply.ts";

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

export type { CatalogRank, RankPosition } from "./rank.ts";
