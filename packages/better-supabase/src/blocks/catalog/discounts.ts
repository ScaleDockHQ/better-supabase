import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";

import { optionalText, recordOf, textOf } from "../shared.ts";

export const DISCOUNT_GROUP_KINDS = ["customer", "product"] as const;

export type DiscountGroupKind = (typeof DISCOUNT_GROUP_KINDS)[number];

export interface DiscountGroupInput {
  /** Updates this group when set; creates one otherwise. */
  readonly id?: string;
  readonly kind: DiscountGroupKind;
  readonly code: string;
  readonly name: string;
}

export interface DiscountRuleInput {
  /** Updates this rule when set; creates one otherwise. */
  readonly id?: string;
  /** Omit for a rule that applies to every customer. */
  readonly customerGroupId?: string;
  /** Omit for a rule that applies to every product. */
  readonly productGroupId?: string;
  /** ISO dates, inclusive. */
  readonly validFrom?: string;
  readonly validTo?: string;
  /** The smallest quantity the rule applies to. Defaults to 0. */
  readonly minQuantity?: number | string;
  /** 0 to 10000. */
  readonly discountBps?: number;
  /** A fixed unit price in minor units, with its currency. */
  readonly fixedPrice?: bigint | string;
  readonly currency?: string;
}

export interface ResolveDiscountOptions {
  /** ISO date to price on. Defaults to today. */
  readonly on?: string;
  /** Skips fixed prices in other currencies. */
  readonly currency?: string;
}

export interface ResolvedDiscount {
  readonly discountBps: number;
  /** Minor units of `currency`, or null when the rule has no fixed price. */
  readonly fixedPrice: string | null;
  readonly currency: string | null;
  /** Null when no rule matched. */
  readonly ruleId: string | null;
}

export interface CatalogDiscounts {
  saveDiscountGroup(input: {
    organizationId: string;
    input: DiscountGroupInput;
  }): AsyncResult<{ readonly id: string }>;
  /** Refused with `CATALOG_DISCOUNT_GROUP_IN_USE` while a rule uses it. */
  deleteDiscountGroup(groupId: string): AsyncResult<boolean>;
  /** Puts a customer in a customer group; null removes it from its group. */
  setPartyDiscountGroup(input: {
    organizationId: string;
    partyId: string;
    groupId: string | null;
  }): AsyncResult<boolean>;
  /** Puts a variant in a product group; null removes it from its group. */
  setVariantDiscountGroup(input: {
    variantId: string;
    groupId: string | null;
  }): AsyncResult<boolean>;
  saveDiscountRule(input: {
    organizationId: string;
    input: DiscountRuleInput;
  }): AsyncResult<{ readonly id: string }>;
  deleteDiscountRule(ruleId: string): AsyncResult<boolean>;
  /**
   * The rule that prices a customer's quantity of a variant: the most specific
   * one wins, then the highest quantity break, then the latest start date.
   */
  resolveLineDiscount(
    input: {
      organizationId: string;
      partyId: string | null;
      variantId: string;
      quantity: number | string;
    } & ResolveDiscountOptions,
  ): AsyncResult<ResolvedDiscount>;
}

const idOf = (value: unknown, fn: string): { readonly id: string } => ({
  id: textOf(recordOf(value, fn)["id"]),
});

/** The discount group, rule and matrix calls of the catalog. */
export function catalogDiscounts(call: BlockCall): CatalogDiscounts {
  return {
    saveDiscountGroup: ({ organizationId, input }) =>
      call(
        "save_discount_group",
        {
          tenant: organizationId,
          group: input.id ?? null,
          kind: input.kind,
          code: input.code,
          name: input.name,
        },
        (value) => idOf(value, "save_discount_group"),
      ),
    deleteDiscountGroup: (groupId) =>
      call("delete_discount_group", { group: groupId }, (v) => v === true),
    setPartyDiscountGroup: ({ organizationId, partyId, groupId }) =>
      call(
        "set_party_discount_group",
        { tenant: organizationId, party: partyId, group: groupId },
        (v) => v === true,
      ),
    setVariantDiscountGroup: ({ variantId, groupId }) =>
      call(
        "set_variant_discount_group",
        { variant: variantId, group: groupId },
        (v) => v === true,
      ),
    saveDiscountRule: ({ organizationId, input }) =>
      call(
        "save_discount_rule",
        {
          tenant: organizationId,
          rule: input.id ?? null,
          attrs: {
            customerGroupId: input.customerGroupId,
            productGroupId: input.productGroupId,
            validFrom: input.validFrom,
            validTo: input.validTo,
            minQuantity:
              input.minQuantity === undefined
                ? undefined
                : String(input.minQuantity),
            discountBps: input.discountBps,
            fixedPrice:
              input.fixedPrice === undefined
                ? undefined
                : String(input.fixedPrice),
            currency: input.currency,
          },
        },
        (value) => idOf(value, "save_discount_rule"),
      ),
    deleteDiscountRule: (ruleId) =>
      call("delete_discount_rule", { rule: ruleId }, (v) => v === true),
    resolveLineDiscount: ({
      organizationId,
      partyId,
      variantId,
      quantity,
      ...options
    }) =>
      call(
        "resolve_line_discount",
        {
          tenant: organizationId,
          party: partyId,
          product: variantId,
          quantity: String(quantity),
          on: options.on ?? new Date().toISOString().slice(0, 10),
          currency: options.currency ?? null,
        },
        (value) => {
          const row = recordOf(value, "resolve_line_discount");

          return {
            discountBps: Number(row["discountBps"]),
            fixedPrice: optionalText(row["fixedPrice"]) ?? null,
            currency: optionalText(row["currency"]) ?? null,
            ruleId: optionalText(row["ruleId"]) ?? null,
          };
        },
      ),
  };
}
