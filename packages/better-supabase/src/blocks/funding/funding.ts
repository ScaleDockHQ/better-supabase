import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions, RecordRef } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { amountText, moneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  errorText,
  injectableOf,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  sha256Hex,
  textOf,
} from "../shared.ts";

/** The unit a funding product counts care in. */
export type FundingUnit =
  | "minute"
  | "hour"
  | "day_part"
  | "day"
  | "visit"
  | "piece";

/** What an award's units cover: each week, each month or the whole award. */
export type FundingPeriod = "week" | "month" | "total";

/** `requested` waits for the funder; only `active` awards take deliveries. */
export type FundingAwardStatus = "requested" | "active" | "ended" | "canceled";

/** Where a delivery came from. */
export type FundingDeliverySource = "time_entry" | "booking" | "manual";

/**
 * `registered` waits for approval; `approved` can be claimed; `claimed` is on a
 * claim; `rejected` was turned down by an approver.
 */
export type FundingDeliveryStatus =
  | "registered"
  | "approved"
  | "claimed"
  | "rejected";

/** A claim is a `draft` until it is sent, then the funder's answer. */
export type FundingClaimStatus =
  | "draft"
  | "sent"
  | "accepted"
  | "partially_accepted"
  | "rejected";

/** A claim line is `pending` until the funder answers. */
export type FundingClaimLineStatus = "pending" | "accepted" | "rejected";

/** A product a funder pays for, such as an iWlz or Wmo product code. */
export interface FundingProduct {
  readonly id: string;
  readonly organizationId: string;
  readonly code: string;
  readonly title: string;
  readonly unit: FundingUnit;
  /** The price of one unit. */
  readonly rate: Money;
  readonly validFrom?: Temporal.PlainDate;
  readonly validUntil?: Temporal.PlainDate;
}

/** What `saveProduct` takes. */
export interface FundingProductInput {
  readonly code: string;
  readonly title: string;
  readonly unit: FundingUnit;
  readonly rate: Money;
  readonly validFrom?: Temporal.PlainDate;
  readonly validUntil?: Temporal.PlainDate;
  /** Updates this product instead of adding one. */
  readonly productId?: string;
}

/** Units of a product a funder awarded to a record. */
export interface FundingAward<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: RecordRef;
  /** The contacts party with the `funder` role. */
  readonly funderId: string;
  readonly productId: string;
  readonly units: number;
  readonly period: FundingPeriod;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  /** The funder's reference, such as an indication or authorization number. */
  readonly reference?: string;
  readonly status: FundingAwardStatus;
  readonly createdBy?: string;
  /** The award's extra columns (`blocks.funding.options.extraColumns`). */
  readonly fields: F;
}

/** An award with its product, as `awards` returns it. */
export interface FundingAwardWithProduct<
  F extends object = Record<never, never>,
> extends FundingAward<F> {
  readonly product: FundingProduct;
}

/** What `createAward` takes. */
export interface FundingAwardInput<F extends object = Record<never, never>> {
  readonly funderId: string;
  readonly productId: string;
  readonly units: number;
  readonly period: FundingPeriod;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  readonly reference?: string;
  /** Default `active`. */
  readonly status?: "requested" | "active";
  readonly fields?: ExtraFields<F>;
}

/** What `updateAward` changes; the keys it leaves out stay. */
export interface FundingAwardPatch<F extends object = Record<never, never>> {
  readonly funderId?: string;
  readonly productId?: string;
  readonly units?: number;
  readonly period?: FundingPeriod;
  readonly startsOn?: Temporal.PlainDate;
  /** `null` clears the end date. */
  readonly endsOn?: Temporal.PlainDate | null;
  readonly reference?: string | null;
  readonly status?: "requested" | "active";
  readonly fields?: ExtraFields<F>;
}

/** The units used in one period of an award. */
export interface FundingUsagePeriod {
  readonly start: Temporal.PlainDate;
  /** The last day of the period; absent for a `total` award without an end. */
  readonly end?: Temporal.PlainDate;
  readonly awarded: number;
  readonly used: number;
  /** Units used above the award. */
  readonly over: number;
  /** Units awarded and not used. */
  readonly under: number;
}

/** What `usage` returns. */
export interface FundingAwardUsage {
  readonly awardId: string;
  readonly units: number;
  readonly period: FundingPeriod;
  readonly periods: readonly FundingUsagePeriod[];
}

/** Care delivered on an award. */
export interface FundingDelivery {
  readonly id: string;
  readonly organizationId: string;
  readonly awardId: string;
  readonly sourceType: FundingDeliverySource;
  /** The time entry or booking id; absent for a manual delivery. */
  readonly sourceId?: string;
  readonly deliveredOn: Temporal.PlainDate;
  readonly units: number;
  readonly performerId?: string;
  readonly status: FundingDeliveryStatus;
  readonly claimLineId?: string;
  readonly note?: string;
}

/** What `registerDelivery` takes. */
export interface FundingDeliveryInput {
  readonly deliveredOn: Temporal.PlainDate;
  readonly units: number;
  /** Default `manual`. A source registers once; a repeat returns the first. */
  readonly sourceType?: FundingDeliverySource;
  readonly sourceId?: string;
  readonly performerId?: string;
  readonly note?: string;
}

/** What `deliveries` filters on. */
export interface FundingDeliveryFilter {
  readonly awardId?: string;
  readonly status?: FundingDeliveryStatus;
  readonly since?: Temporal.PlainDate;
  readonly until?: Temporal.PlainDate;
  /** 1 to 1000. Default 500. */
  readonly limit?: number;
}

/** A time entry `registerFromTime` couldn't match to one award. */
export interface FundingUnmatchedEntry {
  readonly entryId: string;
  readonly subject: RecordRef;
  readonly deliveredOn: Temporal.PlainDate;
  readonly reason: "no_award" | "several_awards" | "no_duration";
}

/** What `registerFromTime` returns. */
export interface FundingTimeRegistration {
  /** The deliveries this run registered. */
  readonly registered: readonly FundingDelivery[];
  readonly unmatched: readonly FundingUnmatchedEntry[];
}

/** A claim to one funder for one period. */
export interface FundingClaim {
  readonly id: string;
  readonly organizationId: string;
  readonly funderId: string;
  readonly number: string;
  readonly periodStart: Temporal.PlainDate;
  readonly periodEnd: Temporal.PlainDate;
  /** The `FundingClaimFormat` key the claim is rendered with. */
  readonly format: string;
  readonly status: FundingClaimStatus;
  readonly externalRef?: string;
  readonly sentAt?: Temporal.Instant;
  /** The SHA-256 of the body that was sent, as hex. */
  readonly payloadSha256?: string;
  /** The funder's response as `recordResponse` stored it. */
  readonly response?: Readonly<Record<string, unknown>>;
  readonly total: Money;
  readonly invoiceId?: string;
  readonly createdBy?: string;
}

/** A delivery on a claim line. */
export interface FundingClaimDelivery {
  readonly id: string;
  readonly deliveredOn: Temporal.PlainDate;
  readonly units: number;
  readonly sourceType: FundingDeliverySource;
  readonly sourceId?: string;
  readonly performerId?: string;
}

/** One award and product on a claim, with the deliveries it sums. */
export interface FundingClaimLine {
  readonly id: string;
  readonly claimId: string;
  readonly awardId: string;
  readonly productId: string;
  readonly units: number;
  readonly amount: Money;
  readonly status: FundingClaimLineStatus;
  readonly rejectionCode?: string;
  readonly award: {
    readonly subject: RecordRef;
    readonly reference?: string;
    readonly period: FundingPeriod;
  };
  readonly product: {
    readonly code: string;
    readonly title: string;
    readonly unit: FundingUnit;
    readonly rate: Money;
  };
  readonly deliveries: readonly FundingClaimDelivery[];
}

/** A claim with its lines, as `claim` and `buildClaim` return it. */
export interface FundingClaimWithLines extends FundingClaim {
  readonly lines: readonly FundingClaimLine[];
}

/**
 * A funder's answer, per line. Lines it leaves out count as accepted; rejected
 * lines put their deliveries back to `approved` for correction.
 */
export interface FundingClaimResponse {
  readonly lines: readonly {
    readonly lineId: string;
    readonly status: "accepted" | "rejected";
    readonly rejectionCode?: string;
  }[];
  /** What the claim keeps of the response, such as the funder's message id. */
  readonly raw?: Readonly<Record<string, unknown>>;
}

/** A claim rendered in a funder's format. */
export interface FundingRenderedClaim {
  readonly body: string;
  readonly filename: string;
  readonly contentType: string;
}

/** What a format and a channel get next to the claim. */
export interface FundingClaimContext {
  readonly organizationId: string;
  readonly signal?: AbortSignal;
}

/**
 * A claim message standard: iWlz AW319, iJw JW323, iWmo WMO323 or US 837P.
 * Write it in the app; the block bundles none.
 */
export interface FundingClaimFormat {
  /** The format contract version. Omitted means 1. */
  readonly apiVersion?: 1;
  /** The key claims are built with, such as `iwlz-aw319`. */
  readonly key: string;
  render(
    claim: FundingClaim,
    lines: readonly FundingClaimLine[],
    context: FundingClaimContext,
  ): FundingRenderedClaim | Promise<FundingRenderedClaim>;
  /** Reads the funder's return message. */
  parseResponse(
    body: string,
  ): FundingClaimResponse | Promise<FundingClaimResponse>;
}

/**
 * How claims reach the funder, such as VECOZO or a clearinghouse. Write it in
 * the app; the block bundles none.
 */
export interface FundingClaimChannel {
  /** The channel contract version. Omitted means 1. */
  readonly apiVersion?: 1;
  readonly key: string;
  send(
    rendered: FundingRenderedClaim,
    context: FundingClaimContext & { readonly claim: FundingClaim },
  ): Promise<{ readonly externalRef: string }>;
  /**
   * The funder's return message for a sent claim, `undefined` until there is
   * one.
   */
  poll?(
    externalRef: string,
    context: FundingClaimContext & { readonly claim: FundingClaim },
  ): Promise<string | undefined>;
}

export interface FundingOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The transport for `registerFromTime`, which only the service role may call:
   * a service-role client on the server. Defaults to `transport`.
   */
  readonly service?: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** The claim formats `send` and `poll` render and read with, by key. */
  readonly formats?: readonly FundingClaimFormat[];
  /** The channel `send` and `poll` use. */
  readonly channel?: FundingClaimChannel;
  /**
   * A Standard Schema for the award's extra columns
   * (`blocks.funding.options.extraColumns`), keyed by database name.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Funding<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Funding<F extends object = Record<never, never>> {
  /** Adds a product, or updates `input.productId`. */
  saveProduct(input: {
    organizationId: string;
    input: FundingProductInput;
  }): AsyncResult<FundingProduct>;
  /** The organization's products by code; expired ones only when asked. */
  products(
    input: { organizationId: string } & { readonly includeExpired?: boolean },
  ): AsyncResult<readonly FundingProduct[]>;
  /** Records an award for a record registered in `config.subjects`. */
  createAward(input: {
    organizationId: string;
    subject: RecordRef;
    input: FundingAwardInput<F>;
  }): AsyncResult<FundingAward<F>>;
  /** Changes a running or requested award. */
  updateAward(input: {
    organizationId: string;
    subject: RecordRef;
    awardId: string;
    patch: FundingAwardPatch<F>;
  }): AsyncResult<FundingAward<F>>;
  /** Ends an award on `endsOn` (today by default), or cancels it. */
  endAward(
    input: { awardId: string } & {
      readonly endsOn?: Temporal.PlainDate;
      readonly canceled?: boolean;
    },
  ): AsyncResult<FundingAward<F>>;
  /** The organization's awards, or a record's; ended ones only when asked. */
  awards(
    input: { organizationId: string } & {
      readonly subject?: RecordRef;
      readonly includeEnded?: boolean;
    },
  ): AsyncResult<readonly FundingAwardWithProduct<F>[]>;
  /** The units used against the units awarded, per period. */
  usage(awardId: string): AsyncResult<FundingAwardUsage>;
  /** Registers care delivered on an active award. */
  registerDelivery(input: {
    awardId: string;
    input: FundingDeliveryInput;
  }): AsyncResult<FundingDelivery>;
  /**
   * Registers the approved time entries between `since` and `until` on the one
   * active award of their record, and returns the ones it couldn't match.
   * Service role only; needs the time-tracking block.
   */
  registerFromTime(input: {
    organizationId: string;
    since: Temporal.PlainDate;
    until: Temporal.PlainDate;
  }): AsyncResult<FundingTimeRegistration>;
  /** Approves registered deliveries, or rejects them. Returns how many changed. */
  approveDeliveries(
    input: { deliveryIds: readonly string[] } & { readonly approved?: boolean },
  ): AsyncResult<number>;
  deliveries(input: {
    organizationId: string;
    filter?: FundingDeliveryFilter | undefined;
  }): AsyncResult<readonly FundingDelivery[]>;
  /** Claims a funder's approved deliveries in a period as one draft claim. */
  buildClaim(input: {
    organizationId: string;
    input: {
      readonly funderId: string;
      readonly periodStart: Temporal.PlainDate;
      readonly periodEnd: Temporal.PlainDate;
      readonly format: string;
    };
  }): AsyncResult<FundingClaimWithLines>;
  claim(claimId: string): AsyncResult<FundingClaimWithLines>;
  claims(
    input: { organizationId: string } & {
      readonly status?: FundingClaimStatus;
      readonly funderId?: string;
    },
  ): AsyncResult<readonly FundingClaim[]>;
  /**
   * Renders a draft claim with its format, sends it through the channel and
   * marks it sent with the channel's reference and the body's SHA-256.
   */
  send(
    input: { claimId: string } & { readonly signal?: AbortSignal },
  ): AsyncResult<FundingClaim>;
  /** Marks a claim sent outside the client, such as by an upload. */
  markSent(input: {
    claimId: string;
    sent?:
      | { readonly externalRef?: string; readonly payloadSha256?: string }
      | undefined;
  }): AsyncResult<FundingClaim>;
  /** Records the funder's answer to a sent claim. */
  recordResponse(input: {
    claimId: string;
    response: FundingClaimResponse;
  }): AsyncResult<FundingClaimWithLines>;
  /**
   * Asks the channel for the funder's answer and records it. `undefined` while
   * the funder hasn't answered.
   */
  poll(
    input: { claimId: string } & { readonly signal?: AbortSignal },
  ): AsyncResult<FundingClaimWithLines | undefined>;
  /** Deletes a draft claim; its deliveries can be claimed again. */
  deleteClaim(claimId: string): AsyncResult<boolean>;
  /**
   * Creates an invoice to the funder for an accepted claim's accepted lines.
   * Needs the invoices block; `attrs` goes to `create_invoice`.
   */
  invoiceClaim(input: {
    claimId: string;
    attrs?: Readonly<Record<string, unknown>> | undefined;
  }): AsyncResult<{
    readonly claim: FundingClaim;
    readonly invoice: Readonly<Record<string, unknown>>;
  }>;
  /** The awards with their usage, read one award at a time. */
  awardsWithUsage(
    input: { organizationId: string } & {
      readonly subject?: RecordRef;
      readonly includeEnded?: boolean;
    },
  ): AsyncResult<
    readonly {
      readonly award: FundingAwardWithProduct<F>;
      readonly usage: FundingAwardUsage;
    }[]
  >;
}

const UNITS = ["minute", "hour", "day_part", "day", "visit", "piece"] as const;
const PERIODS = ["week", "month", "total"] as const;
const AWARD_STATUSES = ["requested", "active", "ended", "canceled"] as const;
const SOURCES = ["time_entry", "booking", "manual"] as const;

const DELIVERY_STATUSES = [
  "registered",
  "approved",
  "claimed",
  "rejected",
] as const;

const CLAIM_STATUSES = [
  "draft",
  "sent",
  "accepted",
  "partially_accepted",
  "rejected",
] as const;

const LINE_STATUSES = ["pending", "accepted", "rejected"] as const;
const UNMATCHED = ["no_award", "several_awards", "no_duration"] as const;

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

const dateOf = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  value === null || value === undefined ? undefined : dateOf(value);

const subjectOf = (row: Readonly<Record<string, unknown>>): RecordRef => ({
  type: textOf(row["subjectType"]),
  id: textOf(row["subjectId"]),
});

function productOf(value: unknown, fn: string): FundingProduct {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    code: textOf(row["code"]),
    title: textOf(row["title"]),
    unit: enumOrThrow(row["unit"], UNITS, "unit"),
    rate: moneyOf(row["rate"], row["currency"], "rate"),
    ...optional("validFrom", optionalDate(row["validFrom"])),
    ...optional("validUntil", optionalDate(row["validUntil"])),
  };
}

function awardOf(value: unknown, fn: string): FundingAward {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subject: subjectOf(row),
    funderId: textOf(row["funderId"]),
    productId: textOf(row["productId"]),
    units: numberOf(row["units"]),
    period: enumOrThrow(row["period"], PERIODS, "period"),
    startsOn: dateOf(row["startsOn"]),
    ...optional("endsOn", optionalDate(row["endsOn"])),
    ...optional("reference", optionalText(row["reference"])),
    status: enumOrThrow(row["status"], AWARD_STATUSES, "status"),
    ...optional("createdBy", optionalText(row["createdBy"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function awardWithProductOf(
  value: unknown,
  fn: string,
): FundingAwardWithProduct {
  const row = recordOf(value, fn);

  return { ...awardOf(row, fn), product: productOf(row["product"], fn) };
}

function usageOf(value: unknown, fn: string): FundingAwardUsage {
  const row = recordOf(value, fn);

  return {
    awardId: textOf(row["awardId"]),
    units: numberOf(row["units"]),
    period: enumOrThrow(row["period"], PERIODS, "period"),
    periods: recordsOf(row["periods"], fn).map((period) => ({
      start: dateOf(period["start"]),
      ...optional("end", optionalDate(period["end"])),
      awarded: numberOf(period["awarded"]),
      used: numberOf(period["used"]),
      over: numberOf(period["over"]),
      under: numberOf(period["under"]),
    })),
  };
}

function deliveryOf(value: unknown, fn: string): FundingDelivery {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    awardId: textOf(row["awardId"]),
    sourceType: enumOrThrow(row["sourceType"], SOURCES, "sourceType"),
    ...optional("sourceId", optionalText(row["sourceId"])),
    deliveredOn: dateOf(row["deliveredOn"]),
    units: numberOf(row["units"]),
    ...optional("performerId", optionalText(row["performerId"])),
    status: enumOrThrow(row["status"], DELIVERY_STATUSES, "status"),
    ...optional("claimLineId", optionalText(row["claimLineId"])),
    ...optional("note", optionalText(row["note"])),
  };
}

function claimOf(value: unknown, fn: string): FundingClaim {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    funderId: textOf(row["funderId"]),
    number: textOf(row["number"]),
    periodStart: dateOf(row["periodStart"]),
    periodEnd: dateOf(row["periodEnd"]),
    format: textOf(row["format"]),
    status: enumOrThrow(row["status"], CLAIM_STATUSES, "status"),
    ...optional("externalRef", optionalText(row["externalRef"])),
    ...optional("sentAt", optionalInstant(row["sentAt"])),
    ...optional("payloadSha256", optionalText(row["payloadSha256"])),
    ...optional(
      "response",
      isRecord(row["response"]) ? row["response"] : undefined,
    ),
    total: moneyOf(row["total"], row["currency"], "total"),
    ...optional("invoiceId", optionalText(row["invoiceId"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function lineOf(
  value: unknown,
  fn: string,
  currency: string,
): FundingClaimLine {
  const row = recordOf(value, fn);
  const award = recordOf(row["award"], fn);
  const product = recordOf(row["product"], fn);

  return {
    id: textOf(row["id"]),
    claimId: textOf(row["claimId"]),
    awardId: textOf(row["awardId"]),
    productId: textOf(row["productId"]),
    units: numberOf(row["units"]),
    amount: moneyOf(row["amount"], currency),
    status: enumOrThrow(row["status"], LINE_STATUSES, "status"),
    ...optional("rejectionCode", optionalText(row["rejectionCode"])),
    award: {
      subject: subjectOf(award),
      ...optional("reference", optionalText(award["reference"])),
      period: enumOrThrow(award["period"], PERIODS, "period"),
    },
    product: {
      code: textOf(product["code"]),
      title: textOf(product["title"]),
      unit: enumOrThrow(product["unit"], UNITS, "unit"),
      rate: moneyOf(product["rate"], currency, "rate"),
    },
    deliveries: recordsOf(row["deliveries"], fn).map((delivery) => ({
      id: textOf(delivery["id"]),
      deliveredOn: dateOf(delivery["deliveredOn"]),
      units: numberOf(delivery["units"]),
      sourceType: enumOrThrow(delivery["sourceType"], SOURCES, "sourceType"),
      ...optional("sourceId", optionalText(delivery["sourceId"])),
      ...optional("performerId", optionalText(delivery["performerId"])),
    })),
  };
}

function claimWithLinesOf(value: unknown, fn: string): FundingClaimWithLines {
  const claim = claimOf(value, fn);
  const row = recordOf(value, fn);

  return {
    ...claim,
    lines: recordsOf(row["lines"], fn).map((line) =>
      lineOf(line, fn, claim.total.currency),
    ),
  };
}

function registrationOf(value: unknown, fn: string): FundingTimeRegistration {
  const row = recordOf(value, fn);

  return {
    registered: recordsOf(row["registered"], fn).map((delivery) =>
      deliveryOf(delivery, fn),
    ),
    unmatched: recordsOf(row["unmatched"], fn).map((entry) => ({
      entryId: textOf(entry["entryId"]),
      subject: subjectOf(entry),
      deliveredOn: dateOf(entry["deliveredOn"]),
      reason: enumOrThrow(entry["reason"], UNMATCHED, "reason"),
    })),
  };
}

/** The attrs of an award write: dates as ISO text, extra columns checked. */
function awardAttrs(
  input: FundingAwardInput<object> | FundingAwardPatch<object>,
  checked: Readonly<Record<string, unknown>> | undefined,
): Record<string, unknown> {
  const { startsOn, endsOn, fields: _fields, ...rest } = input;

  return {
    ...rest,
    ...(checked === undefined ? {} : { fields: checked }),
    ...(startsOn === undefined ? {} : { startsOn: startsOn.toString() }),
    ...(endsOn === undefined ? {} : { endsOn: endsOn?.toString() ?? null }),
  };
}

const many =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): readonly T[] =>
    recordsOf(value, fn).map((row) => of(row, fn));

const one =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): T =>
    of(value, fn);

/** Runs a format or channel call, its throw as an `unexpected` error. */
const port = <T>(run: () => Promise<T>): AsyncResult<T> =>
  AsyncResult.from(async () => {
    try {
      return ok(await run());
    } catch (cause) {
      return err(
        dbError("unexpected", errorText(cause), {
          hint: "FUNDING_CHANNEL_FAILED",
        }),
      );
    }
  });

const signalOf = (options: {
  readonly signal?: AbortSignal;
}): { readonly signal?: AbortSignal } =>
  options.signal === undefined ? {} : { signal: options.signal };

/**
 * The funding block: products a funder pays for, awards of units on any record
 * registered in `config.subjects`, the care delivered against them, and claims
 * to the funder in its own format.
 */
export function createFunding<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: FundingOptions<S>): Funding<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const formats = new Map(
    (options.formats ?? []).map((format) => {
      const checked = injectableOf("funding claim format", format);

      return [checked.key, checked] as const;
    }),
  );

  const channel = injectableOf("funding claim channel", options.channel);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "funding award fields",
  );

  const formatOf = (key: string): AsyncResult<FundingClaimFormat> => {
    const format = formats.get(key);

    return format === undefined
      ? AsyncResult.err(
          dbError("invalid_request", `createFunding has no format ${key}`, {
            hint: "FUNDING_FORMAT_UNKNOWN",
          }),
        )
      : AsyncResult.ok(format);
  };

  const channelOf = (): AsyncResult<FundingClaimChannel> =>
    channel === undefined
      ? AsyncResult.err(
          dbError("invalid_request", "createFunding has no channel", {
            hint: "FUNDING_NO_CHANNEL",
          }),
        )
      : AsyncResult.ok(channel);

  const claim: Funding<F>["claim"] = (claimId) =>
    call(
      "get_funding_claim",
      { claim_id: claimId },
      one("get_funding_claim", claimWithLinesOf),
    );

  const markSent: Funding<F>["markSent"] = ({ claimId, sent = {} }) =>
    call(
      "mark_funding_claim_sent",
      {
        claim_id: claimId,
        external_ref: sent.externalRef ?? null,
        payload_sha256: sent.payloadSha256 ?? null,
      },
      one("mark_funding_claim_sent", claimOf),
    );

  const recordResponse: Funding<F>["recordResponse"] = ({
    claimId,
    response,
  }) =>
    call(
      "record_funding_claim_response",
      {
        claim_id: claimId,
        // sqlTransport sends an empty array as a Postgres array literal.
        lines:
          response.lines.length === 0
            ? null
            : response.lines.map((line) => ({
                lineId: line.lineId,
                status: line.status,
                rejectionCode: line.rejectionCode ?? null,
              })),
        response: response.raw ?? null,
      },
      one("record_funding_claim_response", claimWithLinesOf),
    );

  const saveAward = (
    organizationId: string,
    subject: RecordRef,
    input: FundingAwardInput<F> | FundingAwardPatch<F>,
    awardId: string | null,
  ): AsyncResult<FundingAward<F>> =>
    fields
      .args(input.fields)
      .andThen((checked) =>
        call(
          "save_funding_award",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            attrs: awardAttrs(input, checked),
            award_id: awardId,
          },
          one("save_funding_award", awardOf),
        ).andThen(fields.row),
      );

  const client: Funding<F> = {
    saveProduct: ({ organizationId, input }) =>
      call(
        "save_funding_product",
        {
          tenant: organizationId,
          code: input.code,
          title: input.title,
          unit: input.unit,
          rate: amountText(input.rate),
          currency: input.rate.currency,
          valid_from: input.validFrom?.toString() ?? null,
          valid_until: input.validUntil?.toString() ?? null,
          product_id: input.productId ?? null,
        },
        one("save_funding_product", productOf),
      ),
    products: ({ organizationId, ...list }) =>
      call(
        "list_funding_products",
        {
          tenant: organizationId,
          include_expired: list.includeExpired ?? false,
        },
        many("list_funding_products", productOf),
      ),
    createAward: ({ organizationId, subject, input }) =>
      saveAward(organizationId, subject, input, null),
    updateAward: ({ organizationId, subject, awardId, patch }) =>
      saveAward(organizationId, subject, patch, awardId),
    endAward: ({ awardId, ...end }) =>
      call(
        "end_funding_award",
        {
          award_id: awardId,
          ends_on: end.endsOn?.toString() ?? null,
          canceled: end.canceled ?? false,
        },
        one("end_funding_award", awardOf),
      ).andThen(fields.row),
    awards: ({ organizationId, ...list }) =>
      call(
        "list_funding_awards",
        {
          tenant: organizationId,
          subject_type: list.subject?.type ?? null,
          subject_id: list.subject?.id ?? null,
          include_ended: list.includeEnded ?? false,
        },
        many("list_funding_awards", awardWithProductOf),
      ).andThen(fields.rows),
    usage: (awardId) =>
      call(
        "funding_award_usage",
        { award_id: awardId },
        (value) => value ?? undefined,
      ).andThen((value) =>
        value === undefined
          ? AsyncResult.err(
              dbError("not_found", "the funding award doesn't exist", {
                hint: "FUNDING_AWARD_NOT_FOUND",
              }),
            )
          : AsyncResult.ok(usageOf(value, "funding_award_usage")),
      ),
    registerDelivery: ({ awardId, input }) =>
      call(
        "register_funding_delivery",
        {
          award_id: awardId,
          delivered_on: input.deliveredOn.toString(),
          units: input.units,
          source_type: input.sourceType ?? "manual",
          source_id: input.sourceId ?? null,
          performer_id: input.performerId ?? null,
          note: input.note ?? null,
        },
        one("register_funding_delivery", deliveryOf),
      ),
    registerFromTime: ({ organizationId, since, until }) =>
      service(
        "register_funding_deliveries_from_time",
        {
          tenant: organizationId,
          since: since.toString(),
          until: until.toString(),
        },
        one("register_funding_deliveries_from_time", registrationOf),
      ),
    approveDeliveries: ({ deliveryIds, ...approve }) =>
      call(
        "approve_funding_deliveries",
        { ids: [...deliveryIds], approved: approve.approved ?? true },
        numberOf,
      ),
    deliveries: ({ organizationId, filter = {} }) =>
      call(
        "list_funding_deliveries",
        {
          tenant: organizationId,
          filter: {
            ...optional("awardId", filter.awardId),
            ...optional("status", filter.status),
            ...optional("since", filter.since?.toString()),
            ...optional("until", filter.until?.toString()),
            ...optional("limit", filter.limit),
          },
        },
        many("list_funding_deliveries", deliveryOf),
      ),
    buildClaim: ({ organizationId, input }) =>
      call(
        "build_funding_claim",
        {
          tenant: organizationId,
          funder_id: input.funderId,
          period_start: input.periodStart.toString(),
          period_end: input.periodEnd.toString(),
          format: input.format,
        },
        one("build_funding_claim", claimWithLinesOf),
      ),
    claim,
    claims: ({ organizationId, ...list }) =>
      call(
        "list_funding_claims",
        {
          tenant: organizationId,
          status: list.status ?? null,
          funder_id: list.funderId ?? null,
        },
        many("list_funding_claims", claimOf),
      ),
    send: ({ claimId, ...sendOptions }) =>
      claim(claimId).andThen((found) =>
        formatOf(found.format).andThen((format) =>
          channelOf().andThen((target) => {
            const context = {
              organizationId: found.organizationId,
              ...signalOf(sendOptions),
            };

            return port(async () => {
              const { lines, ...head } = found;
              const rendered = await format.render(head, lines, context);

              const sent = await target.send(rendered, {
                ...context,
                claim: head,
              });

              return {
                externalRef: sent.externalRef,
                payloadSha256: await sha256Hex(rendered.body),
              };
            }).andThen((sent) => markSent({ claimId, sent }));
          }),
        ),
      ),
    markSent,
    recordResponse,
    poll: ({ claimId, ...pollOptions }) =>
      claim(claimId).andThen((found) =>
        formatOf(found.format).andThen((format) =>
          channelOf().andThen((target) => {
            if (target.poll === undefined || found.externalRef === undefined) {
              return AsyncResult.ok<FundingClaimWithLines | undefined>(
                undefined,
              );
            }

            const { lines: _lines, ...head } = found;
            const externalRef = found.externalRef;

            return port(async () => {
              const body = await target.poll?.(externalRef, {
                organizationId: found.organizationId,
                ...signalOf(pollOptions),
                claim: head,
              });

              return body === undefined
                ? undefined
                : format.parseResponse(body);
            }).andThen((response) =>
              response === undefined
                ? AsyncResult.ok<FundingClaimWithLines | undefined>(undefined)
                : recordResponse({ claimId, response }),
            );
          }),
        ),
      ),
    deleteClaim: (claimId) =>
      call(
        "delete_funding_claim",
        { claim_id: claimId },
        (value) => value === true,
      ),
    invoiceClaim: ({ claimId, attrs }) =>
      call(
        "invoice_funding_claim",
        { claim_id: claimId, attrs: attrs ?? null },
        (value) => {
          const row = recordOf(value, "invoice_funding_claim");

          return {
            claim: claimOf(row["claim"], "invoice_funding_claim"),
            invoice: recordOf(row["invoice"], "invoice_funding_claim"),
          };
        },
      ),
    awardsWithUsage: (input) =>
      hooked.awards(input).andThen(async (awards) => {
        const rows: {
          award: FundingAwardWithProduct<F>;
          usage: FundingAwardUsage;
        }[] = [];

        for (const award of awards) {
          const usage = await hooked.usage(award.id);

          if (!usage.ok) {
            return usage;
          }

          rows.push({ award, usage: usage.data });
        }

        return ok(rows);
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Funding<F> = withBlockHooks(client, options.hooks, {
    block: "funding",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
