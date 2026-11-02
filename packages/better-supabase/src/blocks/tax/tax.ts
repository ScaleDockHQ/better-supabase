import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { TAX_CODE_TYPES } from "../../sql/modules/tax-sql.ts";
import { amountText, amountsError, moneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

/** What a tax code does: a rate, or a reason that none applies. */
export type TaxCodeType = (typeof TAX_CODE_TYPES)[number];

/** A date as `Temporal.PlainDate` or `YYYY-MM-DD`. */
export type TaxDate = Temporal.PlainDate | string;

/** One rate of a tax code, valid from a date until the next rate starts. */
export interface TaxRate {
  readonly id: string;
  readonly organizationId: string;
  readonly taxCodeId: string;
  readonly rateBps: number;
  readonly validFrom: Temporal.PlainDate;
  readonly validTo?: Temporal.PlainDate;
  readonly createdAt: Temporal.Instant;
}

/** A tax code with the history of its rates. */
export interface TaxCode {
  readonly id: string;
  readonly organizationId: string;
  /** The legal entity the code belongs to, or none for the whole organization. */
  readonly legalEntityId?: string;
  readonly code: string;
  readonly name: string;
  readonly type: TaxCodeType;
  readonly salesAccountId?: string;
  readonly purchaseAccountId?: string;
  /** The boxes of the tax return the code's base and tax appear in. */
  readonly returnBoxes: readonly string[];
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** Oldest first. */
  readonly rates: readonly TaxRate[];
}

export interface TaxCodeInput {
  readonly code?: string;
  readonly name?: string;
  readonly type?: TaxCodeType;
  readonly legalEntityId?: string | null;
  readonly salesAccountId?: string | null;
  readonly purchaseAccountId?: string | null;
  readonly returnBoxes?: readonly string[];
  readonly archived?: boolean;
  /** Starts a rate when creating the code, or adds one when updating it. */
  readonly rateBps?: number;
  /**
   * When `rateBps` starts. Default: the beginning of time on create, today on
   * update.
   */
  readonly validFrom?: TaxDate;
}

/** A line of a document to compute the tax of. */
export interface TaxLineInput {
  readonly quantity: number;
  readonly unitAmount: Money;
  readonly discountBps?: number;
  /** A tax code of the organization; its rate on the document date applies. */
  readonly taxCodeId?: string;
  /** The rate to use when the line names no code. */
  readonly taxRateBps?: number;
  /** What the goods cost, for a line with a `margin` tax code. */
  readonly unitCost?: Money;
}

export interface TaxComputeInput {
  readonly currency: string;
  readonly lines: readonly TaxLineInput[];
  /** The rate valid on this date applies. */
  readonly onDate: TaxDate;
  /** Whether unit amounts already contain the tax. Default `false`. */
  readonly pricesIncludeTax?: boolean;
  /** Tax on only this share of the base, for a credit note. Default `0`. */
  readonly creditRestrictionBps?: number;
}

/** The totals of one tax code and rate. */
export interface TaxGroup {
  readonly taxCodeId?: string;
  readonly code?: string;
  readonly type?: TaxCodeType;
  readonly rateBps: number;
  readonly net: Money;
  readonly tax: Money;
  readonly gross: Money;
  /** False for the margin scheme, where the document shows no tax amount. */
  readonly showTax: boolean;
}

export interface TaxComputation {
  readonly groups: readonly TaxGroup[];
  readonly subtotal: Money;
  readonly taxTotal: Money;
  readonly total: Money;
  /** False when a margin line is present: the document shows no tax amount. */
  readonly showTaxAmount: boolean;
}

export interface TaxReturnBox {
  readonly box: string;
  readonly base: bigint;
  readonly tax: bigint;
}

export interface TaxReturnIssue {
  readonly code: string;
  readonly invoiceId?: string;
  readonly message: string;
}

/** One customer's intra-EU sales of a period (ICP, EC sales list). */
export interface EuSalesListLine {
  readonly customerVatNumber: string;
  readonly country: string;
  readonly kind: "goods" | "services";
  readonly amount: Money;
  readonly invoiceCount: number;
}

export interface TaxReturn {
  readonly id: string;
  readonly organizationId: string;
  readonly legalEntityId?: string;
  readonly period: string;
  readonly periodStart: Temporal.PlainDate;
  readonly periodEnd: Temporal.PlainDate;
  readonly status: "prepared" | "filed";
  readonly currency?: string;
  /** Base and tax per box, in minor units. */
  readonly boxes: readonly TaxReturnBox[];
  readonly salesTax: bigint;
  readonly purchaseTax: bigint;
  /** Sales tax less purchase tax: positive is owed. */
  readonly netTax: bigint;
  /** Lines the return could not place, such as a missing customer VAT number. */
  readonly issues: readonly TaxReturnIssue[];
  readonly euSalesList: readonly EuSalesListLine[];
  readonly preparedBy?: string;
  readonly preparedAt?: Temporal.Instant;
  readonly filedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface PrepareTaxReturnInput {
  readonly since: TaxDate;
  readonly until: TaxDate;
  readonly legalEntityId?: string;
  /** A label such as `2026-Q1`. Default: the two dates. */
  readonly period?: string;
  /** Required when the period has invoices in more than one currency. */
  readonly currency?: string;
}

export interface Tax {
  saveCode(input: {
    input: TaxCodeInput;
    codeId?: string | undefined;
  }): AsyncResult<TaxCode>;
  codes(options?: {
    readonly includeArchived?: boolean;
    readonly legalEntityId?: string;
  }): AsyncResult<readonly TaxCode[]>;
  /**
   * The rate of a code on a date, in basis points. `undefined` when none covers
   * it.
   */
  rateOn(input: {
    codeId: string;
    onDate: TaxDate;
  }): AsyncResult<number | undefined>;
  /** Totals per tax code and rate: the arithmetic invoices use when they issue. */
  computeDocumentTax(input: TaxComputeInput): AsyncResult<TaxComputation>;
  /** Adds a rate to a code. A rate that starts after the current one ends it. */
  saveRate(input: {
    codeId: string;
    rate: {
      readonly rateBps: number;
      readonly validFrom?: TaxDate;
      readonly validTo?: TaxDate;
    };
  }): AsyncResult<TaxRate>;
  /** Builds, or rebuilds until it is filed, the return of a period. */
  prepareReturn(input: PrepareTaxReturnInput): AsyncResult<TaxReturn>;
  fileReturn(returnId: string): AsyncResult<TaxReturn>;
  returns(): AsyncResult<readonly TaxReturn[]>;
}

export interface TaxOptions extends BlockOptions {
  readonly hooks?: NoInfer<BlockHooks<Tax>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const dateText = (value: TaxDate | undefined): string | undefined =>
  value === undefined ? undefined : value.toString();

const plainDate = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value).slice(0, 10));

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value.slice(0, 10))
    : undefined;

const defined = (value: Record<string, unknown>): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  );

function rateOf(value: unknown, fn: string): TaxRate {
  const row = recordOf(value, fn);
  const validTo = optionalDate(row["validTo"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    taxCodeId: textOf(row["taxCodeId"]),
    rateBps: Number(row["rateBps"]),
    validFrom: plainDate(row["validFrom"]),
    ...(validTo ? { validTo } : {}),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

function codeOf(value: unknown, fn: string): TaxCode {
  const row = recordOf(value, fn);
  const legalEntityId = optionalText(row["legalEntityId"]);
  const salesAccountId = optionalText(row["salesAccountId"]);
  const purchaseAccountId = optionalText(row["purchaseAccountId"]);
  const archivedAt = optionalInstant(row["archivedAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    ...(legalEntityId ? { legalEntityId } : {}),
    code: textOf(row["code"]),
    name: textOf(row["name"]),
    type: enumOrThrow(row["type"], TAX_CODE_TYPES, "tax code type"),
    ...(salesAccountId ? { salesAccountId } : {}),
    ...(purchaseAccountId ? { purchaseAccountId } : {}),
    returnBoxes: stringsOf(row["returnBoxes"]),
    ...(archivedAt ? { archivedAt } : {}),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    rates: recordsOf(row["rates"], fn).map((item) => rateOf(item, fn)),
  };
}

function computationOf(
  value: unknown,
  currency: string,
  fn: string,
): TaxComputation {
  const row = recordOf(value, fn);

  const amount = (item: unknown, field: string): Money =>
    moneyOf(item, currency, field);

  return {
    groups: recordsOf(row["groups"], fn).map((group) => {
      const taxCodeId = optionalText(group["taxCodeId"]);
      const code = optionalText(group["code"]);
      const type = optionalText(group["type"]);

      return {
        ...(taxCodeId ? { taxCodeId } : {}),
        ...(code ? { code } : {}),
        ...(type
          ? { type: enumOrThrow(type, TAX_CODE_TYPES, "tax code type") }
          : {}),
        rateBps: Number(group["rateBps"]),
        net: amount(group["net"], "net"),
        tax: amount(group["tax"], "tax"),
        gross: amount(group["gross"], "gross"),
        showTax: group["showTax"] !== false,
      };
    }),
    subtotal: amount(row["subtotal"], "subtotal"),
    taxTotal: amount(row["taxTotal"], "taxTotal"),
    total: amount(row["total"], "total"),
    showTaxAmount: row["showTaxAmount"] !== false,
  };
}

function returnOf(value: unknown, fn: string): TaxReturn {
  const row = recordOf(value, fn);
  const boxes = isRecord(row["boxes"]) ? row["boxes"] : {};
  const legalEntityId = optionalText(row["legalEntityId"]);
  const currency = optionalText(row["currency"]);
  const preparedBy = optionalText(row["preparedBy"]);
  const preparedAt = optionalInstant(row["preparedAt"]);
  const filedAt = optionalInstant(row["filedAt"]);
  const listCurrency = currency ?? "EUR";

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    ...(legalEntityId ? { legalEntityId } : {}),
    period: textOf(row["period"]),
    periodStart: plainDate(row["periodStart"]),
    periodEnd: plainDate(row["periodEnd"]),
    status: row["status"] === "filed" ? "filed" : "prepared",
    ...(currency ? { currency } : {}),
    boxes: recordsOf(boxes["boxes"] ?? [], fn).map((box) => ({
      box: textOf(box["box"]),
      base: BigInt(textOf(box["base"])),
      tax: BigInt(textOf(box["tax"])),
    })),
    salesTax: BigInt(textOf(boxes["salesTax"] ?? "0")),
    purchaseTax: BigInt(textOf(boxes["purchaseTax"] ?? "0")),
    netTax: BigInt(textOf(boxes["netTax"] ?? "0")),
    issues: recordsOf(boxes["issues"] ?? [], fn).map((issue) => {
      const invoiceId = optionalText(issue["invoiceId"]);

      return {
        code: textOf(issue["code"]),
        ...(invoiceId ? { invoiceId } : {}),
        message: textOf(issue["message"]),
      };
    }),
    euSalesList: recordsOf(row["euSalesList"] ?? [], fn).map((line) => ({
      customerVatNumber: textOf(line["customerVatNumber"]),
      country: textOf(line["country"]),
      kind: line["kind"] === "services" ? "services" : "goods",
      amount: moneyOf(
        line["amount"],
        optionalText(line["currency"]) ?? listCurrency,
        "amount",
      ),
      invoiceCount: Number(line["invoiceCount"]),
    })),
    ...(preparedBy ? { preparedBy } : {}),
    ...(preparedAt ? { preparedAt } : {}),
    ...(filedAt ? { filedAt } : {}),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

const lineArg = (line: TaxLineInput): Record<string, unknown> =>
  defined({
    quantity: line.quantity,
    unitAmount: amountText(line.unitAmount),
    discountBps: line.discountBps,
    taxCodeId: line.taxCodeId,
    taxRateBps: line.taxRateBps,
    unitCost:
      line.unitCost === undefined ? undefined : amountText(line.unitCost),
  });

/**
 * Tax codes with dated rates, the tax of a document per code, tax returns with
 * their boxes and the intra-EU sales list. Reads through the tax block's
 * functions.
 */
export function createTax(options: TaxOptions): Tax {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Tax = {
    saveCode: ({ input, codeId }) =>
      tenant().andThen((organizationId) =>
        call(
          "save_tax_code",
          {
            tenant: organizationId,
            input: defined({ ...input, validFrom: dateText(input.validFrom) }),
            code_id: codeId ?? null,
          },
          (value) => codeOf(value, "save_tax_code"),
        ),
      ),
    codes: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_tax_codes",
          {
            tenant: organizationId,
            include_archived: list.includeArchived ?? false,
            legal_entity: list.legalEntityId ?? null,
          },
          (value) =>
            recordsOf(value, "list_tax_codes").map((row) =>
              codeOf(row, "list_tax_codes"),
            ),
        ),
      ),
    rateOn: ({ codeId, onDate }) =>
      call(
        "tax_rate_on",
        { code_id: codeId, on_date: dateText(onDate) },
        (value) => (value === null ? undefined : Number(value)),
      ),
    computeDocumentTax: (input) => {
      const mismatch = amountsError(input.currency, [
        ...input.lines.map((line) => line.unitAmount),
        ...input.lines.map((line) => line.unitCost),
      ]);

      if (mismatch) {
        return AsyncResult.err(mismatch);
      }

      return call(
        "compute_document_tax",
        {
          lines: input.lines.map(lineArg),
          on_date: dateText(input.onDate),
          prices_include_tax: input.pricesIncludeTax ?? false,
          credit_restriction_bps: input.creditRestrictionBps ?? 0,
        },
        (value) => computationOf(value, input.currency, "compute_document_tax"),
      );
    },
    saveRate: ({ codeId, rate }) =>
      tenant().andThen((organizationId) =>
        call(
          "save_tax_rate",
          {
            tenant: organizationId,
            tax_code: codeId,
            rate_bps: rate.rateBps,
            valid_from: dateText(rate.validFrom) ?? null,
            valid_to: dateText(rate.validTo) ?? null,
          },
          (value) => rateOf(value, "save_tax_rate"),
        ),
      ),
    prepareReturn: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "prepare_tax_return",
          {
            tenant: organizationId,
            since: dateText(input.since),
            until: dateText(input.until),
            legal_entity_id: input.legalEntityId ?? null,
            period: input.period ?? null,
            currency: input.currency ?? null,
          },
          (value) => returnOf(value, "prepare_tax_return"),
        ),
      ),
    fileReturn: (returnId) =>
      call("file_tax_return", { return_id: returnId }, (value) =>
        returnOf(value, "file_tax_return"),
      ),
    returns: () =>
      tenant().andThen((organizationId) =>
        call("list_tax_returns", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_tax_returns").map((row) =>
            returnOf(row, "list_tax_returns"),
          ),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "tax",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
