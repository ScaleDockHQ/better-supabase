import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import {
  type BlockFields,
  blockFields,
  type FieldsOf,
  readFields,
  type RowFields,
  rowFields,
  writeFields,
} from "../../core/block-fields.ts";
import { type Money } from "../../commerce/money.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import { PROMOTION_KINDS } from "../orders/codecs.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  isRecord,
  recordOf,
  textOf,
} from "../shared.ts";

export { PROMOTION_KINDS };
export type PromotionKind = (typeof PROMOTION_KINDS)[number];

export const PROMOTION_SCOPES = [
  "order",
  "products",
  "categories",
  "collections",
] as const;
export type PromotionScope = (typeof PROMOTION_SCOPES)[number];

/** What a promotion takes off. */
export type PromotionDiscount =
  | {
      readonly kind: "percentage";
      /** Above 0 and at most 100, with up to two decimals, such as `"12.5"`. */
      readonly percent: string;
    }
  | { readonly kind: "fixed"; readonly amount: Money }
  | { readonly kind: "free_shipping" };

export interface PromotionsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the extra columns of the promotions table
   * (`blocks.promotions.options.extraColumns`): writes are validated, reads
   * parsed.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around any promotions method. */
  readonly hooks?: NoInfer<BlockHooks<Promotions<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export interface PromotionInput<F extends object = Record<never, never>> {
  /** Updates this promotion; creates one when left out. */
  readonly id?: string;
  readonly name: string;
  readonly description?: string;
  readonly discount: PromotionDiscount;
  /** The cart subtotal before discounts that the promotion needs. */
  readonly minSubtotal?: Money;
  /** Default `order`, the whole cart. */
  readonly scope?: PromotionScope;
  /** Product, category or collection ids for the other scopes. A category includes its children. */
  readonly targets?: readonly string[];
  readonly startsAt?: Temporal.Instant;
  readonly endsAt?: Temporal.Instant;
  /** Redemptions across every customer. */
  readonly usageLimit?: number;
  /** Redemptions per customer, counted by user id and by email. */
  readonly perCustomerLimit?: number;
  /** Combines with other stackable promotions. Default `false`. */
  readonly stackable?: boolean;
  /** Higher applies first. Default `0`. */
  readonly priority?: number;
  /** Applies to every cart it fits without a code. Default `false`. */
  readonly automatic?: boolean;
  /** Default `true`. */
  readonly active?: boolean;
  /** Values for the app's extra columns (`options.extraColumns`); left out keeps the stored ones. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

/** A saved promotion: its id and the app's extra columns. */
export interface SavedPromotion<F extends object = Record<never, never>> {
  readonly id: string;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

interface CodeLimit {
  /** Redemptions of each code. */
  readonly usageLimit?: number;
}

/** Explicit codes, or `count` generated ones. */
export type CodesInput =
  | (CodeLimit & { readonly codes: readonly string[] })
  | (CodeLimit & {
      readonly count: number;
      /** Put before 8 random characters, such as `BF-`. */
      readonly prefix?: string;
    });

export interface PromotionCode {
  readonly id: string;
  readonly code: string;
}

export interface AppliedCode {
  readonly codeId: string;
  readonly code: string;
  readonly promotionId: string;
}

export interface Promotions<F extends object = Record<never, never>> {
  /** Refused with `PROMOTIONS_INVALID` when the discount, limits or targets don't fit. */
  savePromotion(
    organizationId: string,
    input: PromotionInput<F>,
  ): AsyncResult<SavedPromotion<F>>;
  setPromotionActive(
    promotionId: string,
    active: boolean,
  ): AsyncResult<boolean>;
  /** Refused with `PROMOTIONS_IN_USE` once an order redeemed it; deactivate it instead. */
  deletePromotion(promotionId: string): AsyncResult<boolean>;
  /** Codes are stored upper case. Refused with `PROMOTIONS_CODE_TAKEN` for a code the organization has. */
  createCodes(
    promotionId: string,
    input: CodesInput,
  ): AsyncResult<readonly PromotionCode[]>;
  deleteCode(codeId: string): AsyncResult<boolean>;
  /** Adds a code to the shopper's cart; `priceCart` then shows the discount. */
  applyCode(cartId: string, code: string): AsyncResult<AppliedCode>;
  /** Resolves to `false` when the cart didn't hold the code. */
  removeCode(cartId: string, code: string): AsyncResult<boolean>;
}

const isTrue = (value: unknown): boolean => value === true;

function promotionData(
  input: PromotionInput,
): Record<string, unknown> | string {
  const { discount, minSubtotal } = input;
  const currency =
    discount.kind === "fixed"
      ? discount.amount.currency
      : minSubtotal?.currency;
  if (
    discount.kind === "fixed" &&
    minSubtotal !== undefined &&
    minSubtotal.currency !== discount.amount.currency
  ) {
    return `the minimum subtotal is in ${minSubtotal.currency}, the discount in ${discount.amount.currency}`;
  }
  return {
    name: input.name,
    description: input.description ?? null,
    kind: discount.kind,
    percent: discount.kind === "percentage" ? discount.percent : null,
    amount:
      discount.kind === "fixed" ? discount.amount.amount.toString() : null,
    currency: currency ?? null,
    minSubtotal: minSubtotal?.amount.toString() ?? null,
    scope: input.scope ?? "order",
    targets: input.targets ?? [],
    startsAt: instantArg(input.startsAt) ?? null,
    endsAt: instantArg(input.endsAt) ?? null,
    usageLimit: input.usageLimit ?? null,
    perCustomerLimit: input.perCustomerLimit ?? null,
    stackable: input.stackable ?? false,
    priority: input.priority ?? 0,
    automatic: input.automatic ?? false,
    active: input.active ?? true,
  };
}

function codesOf(value: unknown): readonly PromotionCode[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isRecord).map((entry) => ({
    id: textOf(entry["id"]),
    code: textOf(entry["code"]),
  }));
}

/** Coupons, codes, usage limits and stacking rules over the `promotions` SQL module; `orders` prices them into carts. */
export function createPromotions<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: PromotionsOptions<S>): Promotions<FieldsOf<S>> {
  type F = FieldsOf<S>;
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(
    options.fields,
    "promotion fields",
  );
  const promotions: Promotions<F> = {
    savePromotion: (organizationId, input) => {
      const data = promotionData(input);
      if (typeof data === "string") {
        return AsyncResult.err(
          dbError("invalid_request", data, { hint: "PROMOTIONS_INVALID" }),
        );
      }
      return writeFields(fields, input.fields, (checked) =>
        call(
          "save_promotion",
          {
            tenant: organizationId,
            promotion: input.id ?? null,
            data,
            fields: checked,
          },
          (value) => {
            const row = recordOf(value, "save_promotion");
            return { id: textOf(row["id"]), fields: rowFields(row["fields"]) };
          },
        ),
      ).andThen((saved) => readFields(fields, saved));
    },
    setPromotionActive: (promotionId, active) =>
      call("set_promotion_active", { promotion: promotionId, active }, isTrue),
    deletePromotion: (promotionId) =>
      call("delete_promotion", { promotion: promotionId }, isTrue),
    createCodes: (promotionId, input) =>
      call(
        "create_promotion_codes",
        {
          promotion: promotionId,
          codes: "codes" in input ? input.codes : null,
          count: "count" in input ? input.count : null,
          prefix: "count" in input ? (input.prefix ?? null) : null,
          usage_limit: input.usageLimit ?? null,
        },
        codesOf,
      ),
    deleteCode: (codeId) =>
      call("delete_promotion_code", { code: codeId }, isTrue),
    applyCode: (cartId, code) =>
      call("apply_promotion_code", { cart: cartId, code }, (value) => {
        const row = recordOf(value, "apply_promotion_code");
        return {
          codeId: textOf(row["codeId"]),
          code: textOf(row["code"]),
          promotionId: textOf(row["promotionId"]),
        };
      }),
    removeCode: (cartId, code) =>
      call("remove_promotion_code", { cart: cartId, code }, isTrue),
  };
  return withBlockHooks(promotions, options.hooks, {
    block: "promotions",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
