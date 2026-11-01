import type { AsyncResult } from "../../core/result.ts";
import type { blockCall } from "../shared.ts";

import { isRecord, recordOf, recordsOf, textOf } from "../shared.ts";

export const IDENTIFIER_TYPES = [
  "ean",
  "supplier",
  "manufacturer",
  "other",
] as const;

export const RELATION_KINDS = [
  "alternative",
  "superseded_by",
  "accessory",
] as const;

export type IdentifierType = (typeof IDENTIFIER_TYPES)[number];

export type RelationKind = (typeof RELATION_KINDS)[number];

export interface IdentifierInput {
  readonly variantId: string;
  readonly type: IdentifierType;
  readonly value: string;
  /** The supplier or manufacturer the code belongs to. */
  readonly partyId?: string;
}

export interface SavedIdentifier {
  readonly id: string;
  /** False when the variant already had this identifier. */
  readonly created: boolean;
}

export interface IdentifierMatch {
  readonly identifierId: string;
  readonly variantId: string;
  readonly productId: string;
  readonly sku: string;
  readonly type: IdentifierType;
  readonly value: string;
  readonly partyId: string | null;
}

export interface VariantIdentifier {
  readonly id: string;
  readonly type: IdentifierType;
  readonly value: string;
  readonly partyId: string | null;
}

export interface FindByIdentifierOptions {
  readonly type?: IdentifierType;
  readonly partyId?: string;
}

export interface RelationInput {
  /** The variant that has the alternative or accessory, or is superseded. */
  readonly fromVariantId: string;
  readonly toVariantId: string;
  readonly kind: RelationKind;
}

export interface VariantRelation {
  readonly kind: RelationKind;
  /** Outgoing when the variant is the "from" side, incoming when it is "to". */
  readonly direction: "outgoing" | "incoming";
  readonly variantId: string;
  readonly sku: string;
}

export interface SupplierItemInput {
  /** Updates this item when set; creates one otherwise. */
  readonly id?: string;
  readonly supplierId: string;
  readonly code: string;
  readonly description?: string;
  /** In minor units of `currency`. */
  readonly price?: bigint;
  readonly currency?: string;
  readonly unit?: string;
  readonly keywords?: string;
}

export interface SavedSupplierItem {
  readonly id: string;
  readonly code: string;
}

export interface SupplierItem {
  readonly id: string;
  readonly supplierId: string;
  readonly code: string;
  readonly description: string | null;
  readonly price: bigint | null;
  readonly currency: string | null;
  readonly unit: string | null;
  /** The variant the item was promoted to. */
  readonly variantId: string | null;
}

export interface SupplierItemSearchOptions {
  readonly supplierId?: string;
  /** 25 by default, 200 at most. */
  readonly limit?: number;
}

export interface PromotedSupplierItem {
  readonly productId: string;
  readonly variantId: string;
  /** False when the item already had a variant. */
  readonly created: boolean;
}

export type MappingField =
  | "code"
  | "description"
  | "price"
  | "currency"
  | "unit"
  | "keywords";

export interface SupplierItemMappingInput {
  /** Field to source column name; `keywords` may list several columns. */
  readonly columns: Readonly<
    Partial<Record<MappingField, string | readonly string[]>>
  >;
  /** The currency and unit for rows that carry none. */
  readonly defaults?: { readonly currency?: string; readonly unit?: string };
}

export interface SupplierItemMapping extends SupplierItemMappingInput {
  readonly supplierId: string;
}

/** The fields of a supplier price list row, as the mapping reads them. */
export interface MappedSupplierItem {
  readonly code: string | null;
  readonly description: string | null;
  readonly price: bigint | null;
  readonly currency: string | null;
  readonly unit: string | null;
  readonly keywords: string | null;
}

export interface CatalogSupply {
  /** Adds an EAN, a supplier code or another identifier to a variant. */
  saveProductIdentifier(input: {
    organizationId: string;
    input: IdentifierInput;
  }): AsyncResult<SavedIdentifier>;
  deleteProductIdentifier(identifierId: string): AsyncResult<boolean>;
  /** The variants that carry a code. */
  findVariantsByIdentifier(
    input: { organizationId: string; value: string } & FindByIdentifierOptions,
  ): AsyncResult<readonly IdentifierMatch[]>;
  variantIdentifiers(
    variantId: string,
  ): AsyncResult<readonly VariantIdentifier[]>;
  /**
   * Links one variant to another. A `superseded_by` link can't point back along
   * its own chain.
   */
  saveProductRelation(input: {
    organizationId: string;
    input: RelationInput;
  }): AsyncResult<{ readonly created: boolean }>;
  deleteProductRelation(input: RelationInput): AsyncResult<boolean>;
  variantRelations(input: {
    variantId: string;
    kind?: RelationKind | undefined;
  }): AsyncResult<readonly VariantRelation[]>;
  /**
   * The end of the variant's `superseded_by` chain; the variant itself when
   * none.
   */
  replacementVariant(variantId: string): AsyncResult<string>;
  saveSupplierItem(input: {
    organizationId: string;
    input: SupplierItemInput;
  }): AsyncResult<SavedSupplierItem>;
  deleteSupplierItem(itemId: string): AsyncResult<boolean>;
  /** Words in the code, description and keywords, and the start of a code. */
  searchSupplierItems(
    input: {
      organizationId: string;
      query: string;
    } & SupplierItemSearchOptions,
  ): AsyncResult<readonly SupplierItem[]>;
  /** Makes a supplier item a product and variant on first use. */
  promoteSupplierItem(
    input: { itemId: string } & { readonly sku?: string },
  ): AsyncResult<PromotedSupplierItem>;
  setSupplierItemMapping(input: {
    organizationId: string;
    supplierId: string;
    input: SupplierItemMappingInput;
  }): AsyncResult<SupplierItemMapping>;
  supplierItemMapping(input: {
    organizationId: string;
    supplierId: string;
  }): AsyncResult<SupplierItemMapping | null>;
  deleteSupplierItemMapping(input: {
    organizationId: string;
    supplierId: string;
  }): AsyncResult<boolean>;
  /** One price list row through the supplier's mapping, price in minor units. */
  mapSupplierRow(input: {
    organizationId: string;
    supplierId: string;
    row: Readonly<Record<string, unknown>>;
  }): AsyncResult<MappedSupplierItem>;
  /** Sets the variant's Combined Nomenclature code, or clears it with null. */
  setVariantTradeCode(input: {
    variantId: string;
    tradeCode: string | null;
  }): AsyncResult<boolean>;
}

const nullable = (value: unknown): string | null =>
  value === null || value === undefined ? null : textOf(value);

const bigintOrNull = (value: unknown): bigint | null =>
  value === null || value === undefined ? null : BigInt(textOf(value));

const identifierTypeOf = (value: unknown): IdentifierType => {
  const text = textOf(value);
  const found = IDENTIFIER_TYPES.find((type) => type === text);

  if (found === undefined) {
    throw new TypeError(`unknown identifier type "${text}"`);
  }

  return found;
};

const relationKindOf = (value: unknown): RelationKind => {
  const text = textOf(value);
  const found = RELATION_KINDS.find((kind) => kind === text);

  if (found === undefined) {
    throw new TypeError(`unknown relation kind "${text}"`);
  }

  return found;
};

const mappingOf = (value: unknown, fn: string): SupplierItemMapping => {
  const row = recordOf(value, fn);
  const columns = row["columns"];
  const defaults = row["defaults"];

  return {
    supplierId: textOf(row["supplierId"]),
    // SAFETY: set_supplier_item_mapping stores only string and string[] values.
    columns: isRecord(columns) ? columns : {},
    // SAFETY: the SQL function keeps only currency and unit, both text.
    defaults: isRecord(defaults) ? defaults : {},
  };
};

/** The identifier, relation, supplier item and trade code calls of the catalog. */
export function catalogSupply(
  call: ReturnType<typeof blockCall>,
): CatalogSupply {
  return {
    saveProductIdentifier: ({ organizationId, input }) =>
      call(
        "save_product_identifier",
        {
          tenant: organizationId,
          variant: input.variantId,
          type: input.type,
          value: input.value,
          party: input.partyId ?? null,
        },
        (value) => {
          const row = recordOf(value, "save_product_identifier");

          return { id: textOf(row["id"]), created: row["created"] === true };
        },
      ),
    deleteProductIdentifier: (identifierId) =>
      call(
        "delete_product_identifier",
        { identifier: identifierId },
        (value) => value === true,
      ),
    findVariantsByIdentifier: ({ organizationId, value, ...options }) =>
      call(
        "find_variants_by_identifier",
        {
          tenant: organizationId,
          value,
          type: options.type ?? null,
          party: options.partyId ?? null,
        },
        (rows) =>
          recordsOf(rows, "find_variants_by_identifier").map((row) => ({
            identifierId: textOf(row["identifierId"]),
            variantId: textOf(row["variantId"]),
            productId: textOf(row["productId"]),
            sku: textOf(row["sku"]),
            type: identifierTypeOf(row["type"]),
            value: textOf(row["value"]),
            partyId: nullable(row["partyId"]),
          })),
      ),
    variantIdentifiers: (variantId) =>
      call("variant_identifiers", { variant: variantId }, (rows) =>
        recordsOf(rows, "variant_identifiers").map((row) => ({
          id: textOf(row["id"]),
          type: identifierTypeOf(row["type"]),
          value: textOf(row["value"]),
          partyId: nullable(row["partyId"]),
        })),
      ),
    saveProductRelation: ({ organizationId, input }) =>
      call(
        "save_product_relation",
        {
          tenant: organizationId,
          from_variant: input.fromVariantId,
          to_variant: input.toVariantId,
          kind: input.kind,
        },
        (value) => ({
          created: recordOf(value, "save_product_relation")["created"] === true,
        }),
      ),
    deleteProductRelation: (input) =>
      call(
        "delete_product_relation",
        {
          from_variant: input.fromVariantId,
          to_variant: input.toVariantId,
          kind: input.kind,
        },
        (value) => value === true,
      ),
    variantRelations: ({ variantId, kind }) =>
      call(
        "variant_relations",
        { variant: variantId, kind: kind ?? null },
        (rows) =>
          recordsOf(rows, "variant_relations").map((row) => ({
            kind: relationKindOf(row["kind"]),
            direction:
              row["direction"] === "incoming" ? "incoming" : "outgoing",
            variantId: textOf(row["variantId"]),
            sku: textOf(row["sku"]),
          })),
      ),
    replacementVariant: (variantId) =>
      call("replacement_variant", { variant: variantId }, textOf),
    saveSupplierItem: ({ organizationId, input }) =>
      call(
        "save_supplier_item",
        {
          tenant: organizationId,
          item: input.id ?? null,
          supplier: input.supplierId,
          code: input.code,
          description: input.description ?? null,
          price: input.price === undefined ? null : input.price.toString(),
          currency: input.currency ?? null,
          unit: input.unit ?? null,
          keywords: input.keywords ?? null,
        },
        (value) => {
          const row = recordOf(value, "save_supplier_item");

          return { id: textOf(row["id"]), code: textOf(row["code"]) };
        },
      ),
    deleteSupplierItem: (itemId) =>
      call("delete_supplier_item", { item: itemId }, (value) => value === true),
    searchSupplierItems: ({ organizationId, query, ...options }) =>
      call(
        "search_supplier_items",
        {
          tenant: organizationId,
          query,
          supplier: options.supplierId ?? null,
          row_limit: options.limit ?? null,
        },
        (rows) =>
          recordsOf(rows, "search_supplier_items").map((row) => ({
            id: textOf(row["id"]),
            supplierId: textOf(row["supplierId"]),
            code: textOf(row["code"]),
            description: nullable(row["description"]),
            price: bigintOrNull(row["price"]),
            currency: nullable(row["currency"]),
            unit: nullable(row["unit"]),
            variantId: nullable(row["variantId"]),
          })),
      ),
    promoteSupplierItem: ({ itemId, ...options }) =>
      call(
        "promote_supplier_item",
        { item: itemId, sku: options.sku ?? null },
        (value) => {
          const row = recordOf(value, "promote_supplier_item");

          return {
            productId: textOf(row["productId"]),
            variantId: textOf(row["variantId"]),
            created: row["created"] === true,
          };
        },
      ),
    setSupplierItemMapping: ({ organizationId, supplierId, input }) =>
      call(
        "set_supplier_item_mapping",
        {
          tenant: organizationId,
          supplier: supplierId,
          columns: input.columns,
          defaults: input.defaults ?? {},
        },
        (value) => mappingOf(value, "set_supplier_item_mapping"),
      ),
    supplierItemMapping: ({ organizationId, supplierId }) =>
      call(
        "supplier_item_mapping",
        { tenant: organizationId, supplier: supplierId },
        (value) =>
          value === null ? null : mappingOf(value, "supplier_item_mapping"),
      ),
    deleteSupplierItemMapping: ({ organizationId, supplierId }) =>
      call(
        "delete_supplier_item_mapping",
        { tenant: organizationId, supplier: supplierId },
        (value) => value === true,
      ),
    mapSupplierRow: ({ organizationId, supplierId, row }) =>
      call(
        "supplier_item_from_row",
        { tenant: organizationId, supplier: supplierId, source: row },
        (value) => {
          const mapped = recordOf(value, "supplier_item_from_row");

          return {
            code: nullable(mapped["code"]),
            description: nullable(mapped["description"]),
            price: bigintOrNull(mapped["price"]),
            currency: nullable(mapped["currency"]),
            unit: nullable(mapped["unit"]),
            keywords: nullable(mapped["keywords"]),
          };
        },
      ),
    setVariantTradeCode: ({ variantId, tradeCode }) =>
      call(
        "set_variant_trade_code",
        { variant: variantId, trade_code: tradeCode },
        (value) => value === true,
      ),
  };
}
