import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { amountText, moneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export type LeaseStatus = "draft" | "active" | "ended" | "terminated";

export type RentFrequency = "weekly" | "monthly" | "quarterly" | "yearly";

export interface LeasesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
>
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the lease's extra columns
   * (`blocks.leases.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `create`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Leases<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** A unit (an asset) let to a party. `F` types the extra columns. */
export interface Lease<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  /** The asset let. */
  readonly unitId: string;
  /** The party renting the unit, such as a contact. */
  readonly party: RecordRef;
  readonly title: string;
  readonly status: LeaseStatus;
  readonly startsOn: Temporal.PlainDate;
  /** Absent: the lease runs until it is terminated. */
  readonly endsOn?: Temporal.PlainDate;
  /** Per period of `frequency`. */
  readonly rent: Money;
  readonly frequency: RentFrequency;
  readonly deposit: Money;
  /** What the ledger hold keeps aside now: the deposit while the lease runs. */
  readonly depositHeld: Money;
  readonly depositHoldId?: string;
  /** Rent posted less payments, from the lease's ledger account. */
  readonly balanceDue: Money;
  readonly renewedAt?: Temporal.Instant;
  readonly terminatedOn?: Temporal.PlainDate;
  readonly terminationReason?: string;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface LeaseInput<F extends object = Record<never, never>> {
  readonly unitId: string;
  readonly party: RecordRef;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  /** Per period, in minor units. */
  readonly rent: Money;
  /** Default `monthly`. */
  readonly frequency?: RentFrequency;
  /** In the rent's currency. Held on the ledger once the lease starts. */
  readonly deposit?: Money;
  /** Default: the unit's name and "lease". */
  readonly title?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface LeaseListOptions {
  readonly status?: LeaseStatus;
  readonly unitId?: string;
  readonly party?: RecordRef;
  readonly pageSize?: number;
}

export interface LeaseRenewal {
  readonly endsOn: Temporal.PlainDate;
  /** The rent from the next posted period. Default: unchanged. */
  readonly rent?: Money;
}

export interface LeaseTermination {
  /** Default: today. No rent posts for periods from this day. */
  readonly on?: Temporal.PlainDate;
  readonly reason?: string;
  /** Kept from the deposit as rent income; the rest is refunded. */
  readonly depositDeduction?: Money;
}

/** One rent period posted on the ledger. */
export interface LeaseCharge {
  readonly id: string;
  readonly organizationId: string;
  readonly leaseId: string;
  readonly periodStart: Temporal.PlainDate;
  readonly periodEnd: Temporal.PlainDate;
  readonly amount: Money;
  readonly transactionId: string;
  readonly createdAt: Temporal.Instant;
}

export interface RentPaymentInput {
  readonly amount: Money;
  readonly paidAt?: Temporal.Instant;
  /** The payment's reference; a second call with it returns the first. */
  readonly reference?: string;
}

export interface RentPayment {
  readonly transactionId: string;
  readonly leaseId: string;
  readonly amount: Money;
  readonly balanceDue: Money;
}

export interface PostDueRentOptions {
  /** Default: today. Periods that start on or before it post. */
  readonly through?: Temporal.PlainDate;
  /** Default 500. */
  readonly maxRows?: number;
}

export interface Leases<F extends object = Record<never, never>> {
  /** Creates a draft lease. Needs `leases.manage`. */
  create(input: LeaseInput<F>): AsyncResult<Lease<F>>;
  /**
   * Starts a draft lease and holds its deposit on the ledger. Fails with
   * `LEASE_OVERLAP` while another active lease of the unit overlaps it.
   */
  activate(leaseId: string): AsyncResult<Lease<F>>;
  /** Extends an active lease with an end, optionally at a new rent. */
  renew(input: {
    leaseId: string;
    renewal: LeaseRenewal;
  }): AsyncResult<Lease<F>>;
  /** Ends a lease, captures any deduction from the deposit and refunds the rest. */
  terminate(input: {
    leaseId: string;
    termination?: LeaseTermination | undefined;
  }): AsyncResult<Lease<F>>;
  /** Needs `leases.read`. */
  get(leaseId: string): AsyncResult<Lease<F>>;
  list(options?: LeaseListOptions): AsyncResult<readonly Lease<F>[]>;
  /**
   * Posts the rent of every due period of the organization's active leases on
   * the ledger, once per period, and returns how many posted.
   */
  postDueRent(options?: PostDueRentOptions): AsyncResult<number>;
  /** Moves a payment from the lease's balance due to rent received. */
  recordPayment(input: {
    leaseId: string;
    payment: RentPaymentInput;
  }): AsyncResult<RentPayment>;
  /** The rent periods posted, newest first. */
  charges(
    input: { leaseId: string } & { readonly pageSize?: number },
  ): AsyncResult<readonly LeaseCharge[]>;
}

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

function metadataOf(value: unknown): Readonly<Record<string, unknown>> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  // SAFETY: a non-null, non-array object is a record of its keys.
  return value as Readonly<Record<string, unknown>>;
}

function leaseOf(value: unknown, fn: string): Lease {
  const row = recordOf(value, fn);
  const currency = row["currency"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    unitId: textOf(row["unitId"]),
    party: { type: textOf(row["partyType"]), id: textOf(row["partyId"]) },
    title: textOf(row["title"]),
    // SAFETY: the SQL check constraint limits status to these values.
    status: textOf(row["status"]) as LeaseStatus,
    startsOn: dateOf(row["startsOn"]),
    rent: moneyOf(row["rent"], currency, "rent"),
    // SAFETY: the SQL check constraint limits frequency to these values.
    frequency: textOf(row["frequency"]) as RentFrequency,
    deposit: moneyOf(row["deposit"], currency, "deposit"),
    depositHeld: moneyOf(row["depositHeld"], currency, "depositHeld"),
    balanceDue: moneyOf(row["balanceDue"], currency, "balanceDue"),
    metadata: metadataOf(row["metadata"]),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("endsOn", optionalDate(row["endsOn"])),
    ...optional("depositHoldId", optionalText(row["depositHoldId"])),
    ...optional("renewedAt", optionalInstant(row["renewedAt"], "renewedAt")),
    ...optional("terminatedOn", optionalDate(row["terminatedOn"])),
    ...optional("terminationReason", optionalText(row["terminationReason"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function chargeOf(value: unknown): LeaseCharge {
  const row = recordOf(value, "list_lease_charges");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    leaseId: textOf(row["leaseId"]),
    periodStart: dateOf(row["periodStart"]),
    periodEnd: dateOf(row["periodEnd"]),
    amount: moneyOf(row["amount"], row["currency"], "amount"),
    transactionId: textOf(row["transactionId"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

/** The `leases` SQL module as typed calls. */
export function createLeases<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: LeasesOptions<S>): Leases<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const lease =
    (fn: string) =>
    (value: unknown): Lease =>
      leaseOf(value, fn);

  const fields: BlockFields<F> = blockFields(options.fields, "lease fields");

  const client: Leases<F> = {
    create: (input) => {
      if (
        input.deposit !== undefined &&
        input.deposit.currency !== input.rent.currency
      ) {
        return AsyncResult.err(
          dbError("invalid_input", "the deposit is in the rent's currency", {
            hint: "LEASE_TERMS_INVALID",
          }),
        );
      }

      return fields
        .args(input.fields)
        .andThen((checked) =>
          tenant().andThen((organizationId) =>
            call(
              "create_lease",
              {
                tenant: organizationId,
                unit_id: input.unitId,
                party_type: input.party.type,
                party_id: input.party.id,
                starts_on: input.startsOn.toString(),
                rent: amountText(input.rent),
                currency: input.rent.currency,
                frequency: input.frequency ?? "monthly",
                ends_on: input.endsOn?.toString() ?? null,
                deposit: input.deposit ? amountText(input.deposit) : "0",
                title: input.title ?? null,
                metadata: input.metadata ?? null,
                ...(checked === undefined ? {} : { fields: checked }),
              },
              lease("create_lease"),
            ).andThen(fields.row),
          ),
        );
    },
    activate: (leaseId) =>
      call(
        "activate_lease",
        { lease_id: leaseId },
        lease("activate_lease"),
      ).andThen(fields.row),
    renew: ({ leaseId, renewal }) =>
      call(
        "renew_lease",
        {
          lease_id: leaseId,
          ends_on: renewal.endsOn.toString(),
          rent: renewal.rent ? amountText(renewal.rent) : null,
        },
        lease("renew_lease"),
      ).andThen(fields.row),
    terminate: ({ leaseId, termination = {} }) =>
      call(
        "terminate_lease",
        {
          lease_id: leaseId,
          terminates_on: termination.on?.toString() ?? null,
          reason: termination.reason ?? null,
          deposit_deduction: termination.depositDeduction
            ? amountText(termination.depositDeduction)
            : "0",
        },
        lease("terminate_lease"),
      ).andThen(fields.row),
    get: (leaseId) =>
      call("get_lease", { lease_id: leaseId }, lease("get_lease")).andThen(
        fields.row,
      ),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_leases",
          {
            tenant: organizationId,
            status: list.status ?? null,
            unit_id: list.unitId ?? null,
            party_type: list.party?.type ?? null,
            party_id: list.party?.id ?? null,
            page_size: list.pageSize ?? null,
          },
          (value) => recordsOf(value, "list_leases").map(lease("list_leases")),
        ).andThen(fields.rows),
      ),
    postDueRent: (post = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "post_due_rent",
          {
            tenant: organizationId,
            through: post.through?.toString() ?? null,
            max_rows: post.maxRows ?? null,
          },
          (value) => {
            const count = Number(value);

            if (!Number.isInteger(count)) {
              throw new TypeError("post_due_rent did not return a count");
            }

            return count;
          },
        ),
      ),
    recordPayment: ({ leaseId, payment }) =>
      call(
        "record_rent_payment",
        {
          lease_id: leaseId,
          amount: amountText(payment.amount),
          paid_at: instantArg(payment.paidAt) ?? null,
          reference: payment.reference ?? null,
        },
        (value) => {
          const row = recordOf(value, "record_rent_payment");

          return {
            transactionId: textOf(row["transactionId"]),
            leaseId: textOf(row["leaseId"]),
            amount: moneyOf(row["amount"], row["currency"], "amount"),
            balanceDue: moneyOf(
              row["balanceDue"],
              row["currency"],
              "balanceDue",
            ),
          };
        },
      ),
    charges: ({ leaseId, ...list }) =>
      call(
        "list_lease_charges",
        { lease_id: leaseId, page_size: list.pageSize ?? null },
        (value) => recordsOf(value, "list_lease_charges").map(chargeOf),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "leases",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
