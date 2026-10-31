import type { AsyncResult } from "../core/result.ts";
import type { BlockCall } from "./shared.ts";

import { optionalText, recordOf, recordsOf, textOf } from "./shared.ts";

/** One member of a group of quote or order variants. */
export interface DocumentVariant {
  readonly id: string;
  readonly number?: string;
  /** The first document of the group; absent on the first document itself. */
  readonly variantOf?: string;
  readonly variantLabel?: string;
  /** The variant that goes forward; one per group. */
  readonly isSelected: boolean;
  readonly currency?: string;
  /** The total in minor units, as text. */
  readonly total?: string;
}

/** What `selectVariant` of a quote did. */
export interface QuoteVariantSelection {
  readonly selectedId: string;
  readonly variants: readonly DocumentVariant[];
  /** The order or invoice made from the variant when `forward` was set. */
  readonly orderId?: string;
  readonly invoiceId?: string;
}

/** Variants of a quote: alternative scopes or prices of one offer. */
export interface QuoteVariants {
  /**
   * Copies the quote into a new draft variant with its own label. No variant is
   * selected until `selectVariant`, and an unselected variant can't become an
   * order or an invoice.
   */
  createVariant(
    quoteId: string,
    label: string,
  ): AsyncResult<{ readonly id: string }>;
  listVariants(quoteId: string): AsyncResult<readonly DocumentVariant[]>;
  /**
   * Marks the variant selected and its siblings not selected. With `forward` it
   * also makes the order or the invoice from the selected variant.
   */
  selectVariant(
    quoteId: string,
    options?: { readonly forward?: "order" | "invoice" },
  ): AsyncResult<QuoteVariantSelection>;
}

/** Variants of an order: alternatives of which one is invoiced. */
export interface OrderVariants {
  /**
   * Puts an order into the group of another order (`variantOf`, the group's
   * first order), or takes it out of its group with `null`. Only the selected
   * order of a group can be invoiced.
   */
  setVariant(
    orderId: string,
    variantOf: string | null,
    label?: string,
  ): AsyncResult<DocumentVariant>;
  listVariants(orderId: string): AsyncResult<readonly DocumentVariant[]>;
  /** Marks the order selected and the rest of its group not selected. */
  selectVariant(orderId: string): AsyncResult<readonly DocumentVariant[]>;
}

/** A variant row; keys are camel case, or snake case on a raw row. */
function variantOf(value: unknown): DocumentVariant {
  const row = recordOf(value, "variant");

  const pick = (camel: string, snake: string): unknown =>
    row[camel] ?? row[snake];

  const selected = pick("isSelected", "is_selected");
  const number = optionalText(row["number"]);
  const parent = optionalText(pick("variantOf", "variant_of"));
  const label = optionalText(pick("variantLabel", "variant_label"));
  const currency = optionalText(row["currency"]);
  const total = optionalText(row["total"]);

  return {
    id: textOf(row["id"]),
    ...(number === undefined ? {} : { number }),
    ...(parent === undefined ? {} : { variantOf: parent }),
    ...(label === undefined ? {} : { variantLabel: label }),
    isSelected: selected === true,
    ...(currency === undefined ? {} : { currency }),
    ...(total === undefined ? {} : { total }),
  };
}

const variantsOf = (value: unknown): readonly DocumentVariant[] =>
  recordsOf(value, "variants").map(variantOf);

export function quoteVariants(call: BlockCall): QuoteVariants {
  return {
    createVariant: (quoteId, label) =>
      call("create_quote_variant", { quote: quoteId, label }, (value) => ({
        id: textOf(recordOf(value, "create_quote_variant")["id"]),
      })),
    listVariants: (quoteId) =>
      call("list_quote_variants", { quote: quoteId }, variantsOf),
    selectVariant: (quoteId, options = {}) =>
      call(
        "select_quote_variant",
        {
          quote: quoteId,
          options:
            options.forward === undefined ? null : { forward: options.forward },
        },
        (value) => {
          const row = recordOf(value, "select_quote_variant");
          const order = row["order"];
          const invoice = row["invoice"];

          const orderId =
            order === null || order === undefined
              ? undefined
              : optionalText(recordOf(order, "order")["id"]);

          const invoiceId =
            invoice === null || invoice === undefined
              ? undefined
              : optionalText(recordOf(invoice, "invoice")["id"]);

          return {
            selectedId: textOf(recordOf(row["quote"], "quote")["id"]),
            variants: variantsOf(row["variants"]),
            ...(orderId === undefined ? {} : { orderId }),
            ...(invoiceId === undefined ? {} : { invoiceId }),
          };
        },
      ),
  };
}

export function orderVariants(call: BlockCall): OrderVariants {
  return {
    setVariant: (orderId, parent, label) =>
      call(
        "set_order_variant",
        { id: orderId, variant_of: parent, label: label ?? null },
        variantOf,
      ),
    listVariants: (orderId) =>
      call("list_order_variants", { id: orderId }, variantsOf),
    selectVariant: (orderId) =>
      call("select_order_variant", { id: orderId }, (value) =>
        variantsOf(recordOf(value, "select_order_variant")["variants"]),
      ),
  };
}
