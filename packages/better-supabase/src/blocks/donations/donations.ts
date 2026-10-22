import type { Money } from "../../commerce/money.ts";
import type {
  Payment,
  PaymentEvent,
  PaymentProvider,
} from "../../commerce/payments.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { DbError } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { WebhookInput } from "../../core/signatures.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockOptions } from "../shared.ts";

import { paymentProviderOf } from "../../commerce/payments.ts";
import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { amountText, moneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export type GiftStatus = "pending" | "posted" | "failed" | "refunded";

export type PledgeFrequency = "weekly" | "monthly" | "quarterly" | "yearly";

export type PledgeStatus = "active" | "paused" | "ended";

export interface DonationsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /** Charges online gifts and pledge installments. */
  readonly payments?: PaymentProvider;
  /**
   * A Standard Schema for the gift's extra columns
   * (`blocks.donations.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `recordGift` and `give`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Donations<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** A fund or campaign gifts go to. */
export interface DonationFund {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly kind: "fund" | "campaign";
  readonly goal?: Money;
  /** Posted gifts in the goal's currency; absent without a goal currency. */
  readonly raised?: Money;
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface DonationFundInput {
  readonly key: string;
  readonly name: string;
  /** Default `fund`. */
  readonly kind?: "fund" | "campaign";
  readonly goal?: Money;
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
}

/** One gift. A posted gift is on the ledger. `F` types the extra columns. */
export interface Gift<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly donor: SubjectRef;
  readonly fundId?: string;
  readonly pledgeId?: string;
  /** The pledge period this gift pays. */
  readonly periodStart?: Temporal.PlainDate;
  readonly amount: Money;
  readonly receivedOn: Temporal.PlainDate;
  readonly method?: string;
  readonly status: GiftStatus;
  readonly provider?: string;
  readonly paymentReference?: string;
  readonly transactionId?: string;
  readonly refundTransactionId?: string;
  readonly receiptId?: string;
  readonly note?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** A gift received outside the payments provider: cash, a check, a transfer. */
export interface GiftInput<F extends object = Record<never, never>> {
  readonly donor: SubjectRef;
  readonly amount: Money;
  readonly fundId?: string;
  /** Default: today. */
  readonly receivedOn?: Temporal.PlainDate;
  readonly method?: string;
  readonly note?: string;
  /** The pledge installment this gift pays, with `periodStart`. */
  readonly pledgeId?: string;
  readonly periodStart?: Temporal.PlainDate;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/** A gift charged through the payments provider. */
export interface GiveInput<F extends object = Record<never, never>> {
  readonly donor: SubjectRef;
  readonly amount: Money;
  readonly fundId?: string;
  readonly note?: string;
  /** The provider's customer id. */
  readonly customer?: string;
  readonly description?: string;
  readonly returnUrl?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface GiveOutcome<F extends object = Record<never, never>> {
  readonly gift: Gift<F>;
  /** Hand `clientSecret` or `redirectUrl` to the donor when it needs action. */
  readonly payment: Payment;
}

export interface GiftListOptions {
  readonly donor?: SubjectRef;
  readonly fundId?: string;
  readonly pledgeId?: string;
  readonly status?: GiftStatus;
  readonly pageSize?: number;
}

/** A recurring gift. */
export interface Pledge {
  readonly id: string;
  readonly organizationId: string;
  readonly donor: SubjectRef;
  readonly fundId?: string;
  readonly amount: Money;
  readonly frequency: PledgeFrequency;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  readonly status: PledgeStatus;
  /** The payments provider that charges it; absent: recorded by hand. */
  readonly provider?: string;
  readonly providerCustomer?: string;
  readonly note?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface PledgeInput {
  readonly donor: SubjectRef;
  /** Per period. */
  readonly amount: Money;
  /** Default `monthly`. */
  readonly frequency?: PledgeFrequency;
  readonly fundId?: string;
  /** Default: today. */
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  /** The payments provider's `name`, for `chargeDuePledges`. */
  readonly provider?: string;
  readonly providerCustomer?: string;
  readonly note?: string;
}

export interface PledgeUpdate {
  readonly status?: PledgeStatus;
  readonly endsOn?: Temporal.PlainDate;
  /** For installments that have no gift yet. */
  readonly amount?: Money;
}

export interface PledgeListOptions {
  readonly donor?: SubjectRef;
  readonly status?: PledgeStatus;
  readonly pageSize?: number;
}

/** A pledge period that has no gift yet. */
export interface PledgeInstallment {
  readonly pledgeId: string;
  readonly periodStart: Temporal.PlainDate;
  readonly donor: SubjectRef;
  readonly fundId?: string;
  readonly amount: Money;
  readonly provider?: string;
  readonly providerCustomer?: string;
}

export interface DueInstallmentOptions {
  /** Default: today. Periods that start on or before it are due. */
  readonly through?: Temporal.PlainDate;
  /** Default 500. */
  readonly maxRows?: number;
}

/** What `chargeDuePledges` did with one installment. */
export type PledgeChargeOutcome<F extends object = Record<never, never>> =
  | {
      readonly kind: "charged";
      readonly installment: PledgeInstallment;
      readonly gift: Gift<F>;
    }
  | {
      readonly kind: "skipped";
      readonly installment: PledgeInstallment;
      readonly reason: string;
    }
  | {
      readonly kind: "failed";
      readonly installment: PledgeInstallment;
      readonly error: DbError;
    };

/** A numbered tax receipt. */
export interface DonationReceipt {
  readonly id: string;
  readonly organizationId: string;
  readonly donor: SubjectRef;
  readonly sequence: bigint;
  readonly number: string;
  readonly kind: "gift" | "yearly";
  readonly year: number;
  readonly amount: Money;
  readonly issuedAt: Temporal.Instant;
  readonly voidedAt?: Temporal.Instant;
  readonly voidReason?: string;
}

export interface ReceiptListOptions {
  readonly donor?: SubjectRef;
  readonly year?: number;
  readonly pageSize?: number;
}

/** A donor's posted giving in one year. */
export interface GivingSummary {
  readonly year: number;
  readonly donor: SubjectRef;
  readonly totals: readonly {
    readonly amount: Money;
    readonly gifts: number;
  }[];
  readonly funds: readonly {
    readonly fundId?: string;
    readonly name: string;
    readonly amount: Money;
  }[];
  readonly receipts: readonly DonationReceipt[];
}

/** What `webhook` and `handlePaymentEvent` did with an event. */
export type DonationPaymentOutcome<F extends object = Record<never, never>> =
  | { readonly event: string; readonly kind: "gift"; readonly gift: Gift<F> }
  | {
      readonly event: string;
      readonly kind: "ignored";
      readonly reason: string;
    };

export interface Donations<F extends object = Record<never, never>> {
  /** Creates or updates the fund with this key. Needs `donations.manage`. */
  saveFund(input: DonationFundInput): AsyncResult<DonationFund>;
  archiveFund(fundId: string): AsyncResult<DonationFund>;
  funds(options?: {
    readonly includeArchived?: boolean;
  }): AsyncResult<readonly DonationFund[]>;
  /** Records a gift received outside the provider and posts it at once. */
  recordGift(input: GiftInput<F>): AsyncResult<Gift<F>>;
  /**
   * Opens a pending gift and charges it through the payments provider. The gift
   * posts when the payment succeeds, here or from the webhook.
   */
  give(input: GiveInput<F>): AsyncResult<GiveOutcome<F>>;
  getGift(giftId: string): AsyncResult<Gift<F>>;
  gifts(options?: GiftListOptions): AsyncResult<readonly Gift<F>[]>;
  createPledge(input: PledgeInput): AsyncResult<Pledge>;
  updatePledge(pledgeId: string, update: PledgeUpdate): AsyncResult<Pledge>;
  pledges(options?: PledgeListOptions): AsyncResult<readonly Pledge[]>;
  dueInstallments(
    options?: DueInstallmentOptions,
  ): AsyncResult<readonly PledgeInstallment[]>;
  /**
   * Charges every due installment of pledges this provider charges, once per
   * period: a second run reuses the period's gift and idempotency key.
   */
  chargeDuePledges(
    options?: DueInstallmentOptions,
  ): AsyncResult<readonly PledgeChargeOutcome<F>[]>;
  /** Applies a provider event to its gift. */
  handlePaymentEvent(
    event: PaymentEvent,
  ): AsyncResult<DonationPaymentOutcome<F>>;
  /** Verifies a provider webhook and applies its events. */
  webhook(
    input: WebhookInput,
  ): AsyncResult<readonly DonationPaymentOutcome<F>[]>;
  /** A numbered receipt for one posted gift. */
  issueGiftReceipt(giftId: string): AsyncResult<DonationReceipt>;
  /** A donor's receipt for their posted gifts in a year and currency. */
  issueYearlyReceipt(
    donor: SubjectRef,
    year: number,
    currency: string,
  ): AsyncResult<DonationReceipt>;
  voidReceipt(receiptId: string, reason?: string): AsyncResult<DonationReceipt>;
  receipts(
    options?: ReceiptListOptions,
  ): AsyncResult<readonly DonationReceipt[]>;
  /** Default year: this one. */
  givingSummary(donor: SubjectRef, year?: number): AsyncResult<GivingSummary>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const failure = (hint: string, message: string): DbError =>
  dbError("invalid_request", message, { hint });

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

function dateOf(value: unknown): Temporal.PlainDate {
  return temporal().PlainDate.from(textOf(value));
}

function optionalDate(value: unknown): Temporal.PlainDate | undefined {
  const text = optionalText(value);

  return text === undefined ? undefined : temporal().PlainDate.from(text);
}

function optionalInstant(
  value: unknown,
  field: string,
): Temporal.Instant | undefined {
  return value === null || value === undefined
    ? undefined
    : requiredInstant(value, field);
}

function optionalMoney(
  value: unknown,
  currency: unknown,
  field: string,
): Money | undefined {
  return value === null || value === undefined
    ? undefined
    : moneyOf(value, currency, field);
}

function fundOf(value: unknown, fn: string): DonationFund {
  const row = recordOf(value, fn);
  const currency = row["currency"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    // SAFETY: the SQL check constraint limits kind to these values.
    kind: textOf(row["kind"]) as DonationFund["kind"],
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("goal", optionalMoney(row["goal"], currency, "goal")),
    ...optional("raised", optionalMoney(row["raised"], currency, "raised")),
    ...optional("startsOn", optionalDate(row["startsOn"])),
    ...optional("endsOn", optionalDate(row["endsOn"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"], "archivedAt")),
  };
}

function giftOf(value: unknown, fn: string): Gift {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    donor: { type: textOf(row["donorType"]), id: textOf(row["donorId"]) },
    amount: moneyOf(row["amount"], row["currency"], "amount"),
    receivedOn: dateOf(row["receivedOn"]),
    // SAFETY: the SQL check constraint limits status to these values.
    status: textOf(row["status"]) as GiftStatus,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("fundId", optionalText(row["fundId"])),
    ...optional("pledgeId", optionalText(row["pledgeId"])),
    ...optional("periodStart", optionalDate(row["periodStart"])),
    ...optional("method", optionalText(row["method"])),
    ...optional("provider", optionalText(row["provider"])),
    ...optional("paymentReference", optionalText(row["paymentReference"])),
    ...optional("transactionId", optionalText(row["transactionId"])),
    ...optional(
      "refundTransactionId",
      optionalText(row["refundTransactionId"]),
    ),
    ...optional("receiptId", optionalText(row["receiptId"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function pledgeOf(value: unknown, fn: string): Pledge {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    donor: { type: textOf(row["donorType"]), id: textOf(row["donorId"]) },
    amount: moneyOf(row["amount"], row["currency"], "amount"),
    // SAFETY: the SQL check constraint limits frequency to these values.
    frequency: textOf(row["frequency"]) as PledgeFrequency,
    startsOn: dateOf(row["startsOn"]),
    // SAFETY: the SQL check constraint limits status to these values.
    status: textOf(row["status"]) as PledgeStatus,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("fundId", optionalText(row["fundId"])),
    ...optional("endsOn", optionalDate(row["endsOn"])),
    ...optional("provider", optionalText(row["provider"])),
    ...optional("providerCustomer", optionalText(row["providerCustomer"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function installmentOf(value: unknown): PledgeInstallment {
  const row = recordOf(value, "due_pledge_installments");

  return {
    pledgeId: textOf(row["pledgeId"]),
    periodStart: dateOf(row["periodStart"]),
    donor: { type: textOf(row["donorType"]), id: textOf(row["donorId"]) },
    amount: moneyOf(row["amount"], row["currency"], "amount"),
    ...optional("fundId", optionalText(row["fundId"])),
    ...optional("provider", optionalText(row["provider"])),
    ...optional("providerCustomer", optionalText(row["providerCustomer"])),
  };
}

function receiptOf(value: unknown, fn: string): DonationReceipt {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    donor: { type: textOf(row["donorType"]), id: textOf(row["donorId"]) },
    sequence: BigInt(textOf(row["sequence"])),
    number: textOf(row["number"]),
    // SAFETY: the SQL check constraint limits kind to these values.
    kind: textOf(row["kind"]) as DonationReceipt["kind"],
    year: Number(row["year"]),
    amount: moneyOf(row["amount"], row["currency"], "amount"),
    issuedAt: requiredInstant(row["issuedAt"], "issuedAt"),
    ...optional("voidedAt", optionalInstant(row["voidedAt"], "voidedAt")),
    ...optional("voidReason", optionalText(row["voidReason"])),
  };
}

function summaryOf(value: unknown): GivingSummary {
  const fn = "yearly_giving_summary";
  const row = recordOf(value, fn);

  return {
    year: Number(row["year"]),
    donor: { type: textOf(row["donorType"]), id: textOf(row["donorId"]) },
    totals: recordsOf(row["totals"] ?? [], fn).map((total) => ({
      amount: moneyOf(total["amount"], total["currency"], "amount"),
      gifts: Number(total["gifts"]),
    })),
    funds: recordsOf(row["funds"] ?? [], fn).map((fund) => ({
      name: textOf(fund["name"]),
      amount: moneyOf(fund["amount"], fund["currency"], "amount"),
      ...optional("fundId", optionalText(fund["fundId"])),
    })),
    receipts: recordsOf(row["receipts"] ?? [], fn).map((receipt) =>
      receiptOf(receipt, fn),
    ),
  };
}

/** How a provider payment status moves a gift. */
function giftPaymentStatus(
  status: Payment["status"],
): "pending" | "succeeded" | "failed" {
  switch (status) {
    case "succeeded": {
      return "succeeded";
    }

    case "failed":
    case "canceled": {
      return "failed";
    }

    case "requires_action":
    case "processing":
    case "authorized": {
      return "pending";
    }

    default: {
      const unknown: never = status;

      throw new TypeError(`unknown payment status ${String(unknown)}`);
    }
  }
}

/** The `donations` SQL module as typed calls. */
export function createDonations<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: DonationsOptions<S>): Donations<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);

  const payments = options.payments
    ? paymentProviderOf(options.payments)
    : undefined;

  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const fields: BlockFields<F> = blockFields(options.fields, "gift fields");

  const gift =
    (fn: string) =>
    (value: unknown): Gift =>
      giftOf(value, fn);

  const fund =
    (fn: string) =>
    (value: unknown): DonationFund =>
      fundOf(value, fn);

  const pledge =
    (fn: string) =>
    (value: unknown): Pledge =>
      pledgeOf(value, fn);

  const receipt =
    (fn: string) =>
    (value: unknown): DonationReceipt =>
      receiptOf(value, fn);

  const recordGiftPayment = (
    giftId: string | null,
    provider: string,
    paymentId: string | null,
    status: "pending" | "succeeded" | "failed" | "refunded",
  ): AsyncResult<Gift<F>> =>
    service(
      "record_gift_payment",
      { gift_id: giftId, provider, payment_id: paymentId, status },
      gift("record_gift_payment"),
    ).andThen(fields.row);

  const dueInstallments = (
    organizationId: string,
    due: DueInstallmentOptions,
  ): AsyncResult<readonly PledgeInstallment[]> =>
    service(
      "due_pledge_installments",
      {
        tenant: organizationId,
        through: due.through?.toString() ?? null,
        max_rows: due.maxRows ?? null,
      },
      (value) => recordsOf(value, "due_pledge_installments").map(installmentOf),
    );

  const chargeInstallment = async (
    provider: PaymentProvider,
    organizationId: string,
    installment: PledgeInstallment,
  ): Promise<PledgeChargeOutcome<F>> => {
    const opened = await service(
      "open_gift",
      {
        tenant: organizationId,
        donor_type: installment.donor.type,
        donor_id: installment.donor.id,
        amount: amountText(installment.amount),
        currency: installment.amount.currency,
        fund_id: installment.fundId ?? null,
        pledge_id: installment.pledgeId,
        period_start: installment.periodStart.toString(),
        provider: provider.name,
        note: null,
      },
      gift("open_gift"),
    );

    if (!opened.ok) {
      return { kind: "failed", installment, error: opened.error };
    }

    const charged = await provider.createPayment(
      {
        amount: installment.amount,
        reference: opened.data.id,
        ...(installment.providerCustomer === undefined
          ? {}
          : { customer: installment.providerCustomer }),
        description: `Pledge installment from ${installment.periodStart.toString()}`,
        metadata: {
          giftId: opened.data.id,
          pledgeId: installment.pledgeId,
          periodStart: installment.periodStart.toString(),
        },
      },
      {
        idempotencyKey: `pledge:${installment.pledgeId}:${installment.periodStart.toString()}`,
      },
    );

    if (!charged.ok) {
      if (charged.error.hint !== "PAYMENT_DECLINED") {
        return { kind: "failed", installment, error: charged.error };
      }

      const declined = await recordGiftPayment(
        opened.data.id,
        provider.name,
        null,
        "failed",
      );

      return {
        kind: "failed",
        installment,
        error: declined.ok ? charged.error : declined.error,
      };
    }

    const stored = await recordGiftPayment(
      opened.data.id,
      provider.name,
      charged.data.id,
      giftPaymentStatus(charged.data.status),
    );

    return stored.ok
      ? { kind: "charged", installment, gift: stored.data }
      : { kind: "failed", installment, error: stored.error };
  };

  const handlePaymentEvent: Donations<F>["handlePaymentEvent"] = (event) =>
    AsyncResult.from(async (): Promise<Result<DonationPaymentOutcome<F>>> => {
      if (event.type === "refund.failed") {
        return ok({
          event: event.id,
          kind: "ignored",
          reason: "refund failed",
        });
      }

      const status =
        event.type === "refund.succeeded"
          ? "refunded"
          : event.type === "payment.succeeded"
            ? "succeeded"
            : event.type === "payment.failed" ||
                event.type === "payment.canceled"
              ? "failed"
              : "pending";

      const giftId =
        status !== "refunded" &&
        event.reference !== undefined &&
        UUID.test(event.reference)
          ? event.reference
          : null;

      const stored = await recordGiftPayment(
        giftId,
        payments?.name ?? "unknown",
        event.paymentId,
        status,
      );

      if (!stored.ok) {
        return stored.error.hint === "DONATION_NOT_FOUND"
          ? ok({ event: event.id, kind: "ignored", reason: "unknown gift" })
          : stored;
      }

      return ok({ event: event.id, kind: "gift", gift: stored.data });
    });

  const client: Donations<F> = {
    saveFund: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_donation_fund",
          {
            tenant: organizationId,
            key: input.key,
            name: input.name,
            kind: input.kind ?? "fund",
            goal: input.goal ? amountText(input.goal) : null,
            currency: input.goal?.currency ?? null,
            starts_on: input.startsOn?.toString() ?? null,
            ends_on: input.endsOn?.toString() ?? null,
          },
          fund("save_donation_fund"),
        ),
      ),
    archiveFund: (fundId) =>
      call(
        "archive_donation_fund",
        { fund_id: fundId },
        fund("archive_donation_fund"),
      ),
    funds: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_donation_funds",
          {
            tenant: organizationId,
            include_archived: list.includeArchived ?? false,
          },
          (value) =>
            recordsOf(value, "list_donation_funds").map(
              fund("list_donation_funds"),
            ),
        ),
      ),
    recordGift: (input) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          tenant().andThen((organizationId) =>
            call(
              "record_gift",
              {
                tenant: organizationId,
                donor_type: input.donor.type,
                donor_id: input.donor.id,
                amount: amountText(input.amount),
                currency: input.amount.currency,
                fund_id: input.fundId ?? null,
                received_on: input.receivedOn?.toString() ?? null,
                method: input.method ?? null,
                note: input.note ?? null,
                pledge_id: input.pledgeId ?? null,
                period_start: input.periodStart?.toString() ?? null,
                ...(checked === undefined ? {} : { fields: checked }),
              },
              gift("record_gift"),
            ).andThen(fields.row),
          ),
        ),
    give: (input) =>
      AsyncResult.from(async (): Promise<Result<GiveOutcome<F>>> => {
        if (!payments) {
          return err(
            failure("DONATIONS_NO_PAYMENTS", "give needs a payments provider"),
          );
        }

        const checked = await fields.args(input.fields);

        if (!checked.ok) {
          return checked;
        }

        const organizationId = await tenant();

        if (!organizationId.ok) {
          return organizationId;
        }

        const opened = await call(
          "open_gift",
          {
            tenant: organizationId.data,
            donor_type: input.donor.type,
            donor_id: input.donor.id,
            amount: amountText(input.amount),
            currency: input.amount.currency,
            fund_id: input.fundId ?? null,
            pledge_id: null,
            period_start: null,
            provider: payments.name,
            note: input.note ?? null,
            ...(checked.data === undefined ? {} : { fields: checked.data }),
          },
          gift("open_gift"),
        );

        if (!opened.ok) {
          return opened;
        }

        const created = await payments.createPayment(
          {
            amount: input.amount,
            reference: opened.data.id,
            ...(input.customer === undefined
              ? {}
              : { customer: input.customer }),
            description: input.description ?? "Donation",
            ...(input.returnUrl === undefined
              ? {}
              : { returnUrl: input.returnUrl }),
            metadata: { giftId: opened.data.id },
          },
          { idempotencyKey: `gift:${opened.data.id}:payment` },
        );

        if (!created.ok) {
          return created;
        }

        const stored = await recordGiftPayment(
          opened.data.id,
          payments.name,
          created.data.id,
          giftPaymentStatus(created.data.status),
        );

        return stored.ok
          ? ok({ gift: stored.data, payment: created.data })
          : stored;
      }),
    getGift: (giftId) =>
      call("get_gift", { gift_id: giftId }, gift("get_gift")).andThen(
        fields.row,
      ),
    gifts: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_gifts",
          {
            tenant: organizationId,
            donor_type: list.donor?.type ?? null,
            donor_id: list.donor?.id ?? null,
            fund_id: list.fundId ?? null,
            pledge_id: list.pledgeId ?? null,
            status: list.status ?? null,
            page_size: list.pageSize ?? null,
          },
          (value) => recordsOf(value, "list_gifts").map(gift("list_gifts")),
        ).andThen(fields.rows),
      ),
    createPledge: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_pledge",
          {
            tenant: organizationId,
            donor_type: input.donor.type,
            donor_id: input.donor.id,
            amount: amountText(input.amount),
            currency: input.amount.currency,
            frequency: input.frequency ?? "monthly",
            fund_id: input.fundId ?? null,
            starts_on: input.startsOn?.toString() ?? null,
            ends_on: input.endsOn?.toString() ?? null,
            provider: input.provider ?? null,
            provider_customer: input.providerCustomer ?? null,
            note: input.note ?? null,
          },
          pledge("create_pledge"),
        ),
      ),
    updatePledge: (pledgeId, update) =>
      call(
        "update_pledge",
        {
          pledge_id: pledgeId,
          status: update.status ?? null,
          ends_on: update.endsOn?.toString() ?? null,
          amount: update.amount ? amountText(update.amount) : null,
        },
        pledge("update_pledge"),
      ),
    pledges: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_pledges",
          {
            tenant: organizationId,
            donor_type: list.donor?.type ?? null,
            donor_id: list.donor?.id ?? null,
            status: list.status ?? null,
            page_size: list.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_pledges").map(pledge("list_pledges")),
        ),
      ),
    dueInstallments: (due = {}) =>
      tenant().andThen((organizationId) =>
        dueInstallments(organizationId, due),
      ),
    chargeDuePledges: (due = {}) =>
      AsyncResult.from(
        async (): Promise<Result<readonly PledgeChargeOutcome<F>[]>> => {
          if (!payments) {
            return err(
              failure(
                "DONATIONS_NO_PAYMENTS",
                "charging pledges needs a payments provider",
              ),
            );
          }

          const organizationId = await tenant();

          if (!organizationId.ok) {
            return organizationId;
          }

          const installments = await dueInstallments(organizationId.data, due);

          if (!installments.ok) {
            return installments;
          }

          const outcomes: PledgeChargeOutcome<F>[] = [];

          for (const installment of installments.data) {
            if (installment.provider !== payments.name) {
              outcomes.push({
                kind: "skipped",
                installment,
                reason:
                  installment.provider === undefined
                    ? "the pledge is recorded by hand"
                    : `the pledge is charged by ${installment.provider}`,
              });
              continue;
            }

            outcomes.push(
              await chargeInstallment(
                payments,
                organizationId.data,
                installment,
              ),
            );
          }

          return ok(outcomes);
        },
      ),
    handlePaymentEvent,
    webhook: (input) =>
      AsyncResult.from(
        async (): Promise<Result<readonly DonationPaymentOutcome<F>[]>> => {
          if (!payments) {
            return err(
              failure(
                "DONATIONS_NO_PAYMENTS",
                "webhooks need a payments provider",
              ),
            );
          }

          const parsed = await payments.parseWebhook(input);

          if (!parsed.ok) {
            return parsed;
          }

          const outcomes: DonationPaymentOutcome<F>[] = [];

          for (const event of parsed.data) {
            const outcome = await handlePaymentEvent(event);

            if (!outcome.ok) {
              return outcome;
            }

            outcomes.push(outcome.data);
          }

          return ok(outcomes);
        },
      ),
    issueGiftReceipt: (giftId) =>
      call(
        "issue_gift_receipt",
        { gift_id: giftId },
        receipt("issue_gift_receipt"),
      ),
    issueYearlyReceipt: (donor, year, currency) =>
      tenant().andThen((organizationId) =>
        call(
          "issue_yearly_receipt",
          {
            tenant: organizationId,
            donor_type: donor.type,
            donor_id: donor.id,
            year,
            currency,
          },
          receipt("issue_yearly_receipt"),
        ),
      ),
    voidReceipt: (receiptId, reason) =>
      call(
        "void_donation_receipt",
        { receipt_id: receiptId, reason: reason ?? null },
        receipt("void_donation_receipt"),
      ),
    receipts: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_donation_receipts",
          {
            tenant: organizationId,
            donor_type: list.donor?.type ?? null,
            donor_id: list.donor?.id ?? null,
            year: list.year ?? null,
            page_size: list.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_donation_receipts").map(
              receipt("list_donation_receipts"),
            ),
        ),
      ),
    givingSummary: (donor, year) =>
      tenant().andThen((organizationId) =>
        call(
          "yearly_giving_summary",
          {
            tenant: organizationId,
            donor_type: donor.type,
            donor_id: donor.id,
            year: year ?? null,
          },
          summaryOf,
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "donations",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
