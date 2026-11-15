import type { CatalogEvents } from "../../blocks/catalog/events.ts";
import type { BlockSqlEvents } from "../context.ts";

/** The catalog events the SQL module records, with their subject and payload. */
export const CATALOG_EVENTS: BlockSqlEvents<CatalogEvents> = {
  "product.created": {
    subject: "products",
    payload: ["organizationId", "id", "slug", "kind"],
  },
  "product.updated": {
    subject: "products",
    payload: ["organizationId", "id", "slug"],
  },
  "product.status_changed": {
    subject: "products",
    payload: ["organizationId", "id", "from", "to"],
  },
  "product.archived": {
    subject: "products",
    payload: ["organizationId", "id"],
  },
  "product.restored": {
    subject: "products",
    payload: ["organizationId", "id"],
  },
  "product.purged": { subject: "products", payload: ["organizationId", "id"] },
  "product_variant.created": {
    subject: "variants",
    payload: ["organizationId", "id", "productId", "sku"],
  },
  "product_variant.updated": {
    subject: "variants",
    payload: ["organizationId", "id", "productId", "sku"],
  },
  "product_variant.archived": {
    subject: "variants",
    payload: ["organizationId", "id", "productId"],
  },
  "product_variant.restored": {
    subject: "variants",
    payload: ["organizationId", "id", "productId"],
  },
  "product_variant.purged": {
    subject: "variants",
    payload: ["organizationId", "id", "productId"],
  },
  "catalog.price_changed": {
    subject: "prices",
    payload: [
      "organizationId",
      "id",
      "variantId",
      "priceListId",
      "currency",
      "amount",
      "previousAmount",
    ],
  },
  "storefront.published": {
    subject: "storefronts",
    payload: ["organizationId"],
  },
  "storefront.unpublished": {
    subject: "storefronts",
    payload: ["organizationId"],
  },
};
