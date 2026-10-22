import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
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

export type MaintenancePriority = "low" | "normal" | "high" | "urgent";

export type MaintenanceStatus =
  | "open"
  | "in_progress"
  | "resolved"
  | "cancelled";

export interface LeasesOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Leases>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** A unit (an asset) let to a party. */
export interface Lease {
  readonly id: string;
  readonly organizationId: string;
  /** The asset let. */
  readonly unitId: string;
  /** The party renting the unit, such as a contact. */
  readonly party: SubjectRef;
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
}

export interface LeaseInput {
  readonly unitId: string;
  readonly party: SubjectRef;
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
}

export interface LeaseListOptions {
  readonly status?: LeaseStatus;
  readonly unitId?: string;
  readonly party?: SubjectRef;
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

export interface MaintenanceRequest {
  readonly id: string;
  readonly organizationId: string;
  readonly unitId: string;
  readonly leaseId?: string;
  readonly title: string;
  readonly description?: string;
  readonly priority: MaintenancePriority;
  readonly status: MaintenanceStatus;
  readonly reportedBy?: string;
  readonly assigneeId?: string;
  readonly resolvedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface MaintenanceRequestInput {
  readonly unitId: string;
  readonly title: string;
  readonly description?: string;
  /** Default `normal`. */
  readonly priority?: MaintenancePriority;
  readonly leaseId?: string;
}

export interface MaintenanceUpdate {
  readonly status?: MaintenanceStatus;
  readonly priority?: MaintenancePriority;
  readonly assigneeId?: string;
}

export interface MaintenanceListOptions {
  readonly unitId?: string;
  readonly leaseId?: string;
  readonly status?: MaintenanceStatus;
  readonly pageSize?: number;
}

export interface Leases {
  /** Creates a draft lease. Needs `leases.manage`. */
  create(input: LeaseInput): AsyncResult<Lease>;
  /**
   * Starts a draft lease and holds its deposit on the ledger. Fails with
   * `LEASE_OVERLAP` while another active lease of the unit overlaps it.
   */
  activate(leaseId: string): AsyncResult<Lease>;
  /** Extends an active lease with an end, optionally at a new rent. */
  renew(leaseId: string, renewal: LeaseRenewal): AsyncResult<Lease>;
  /** Ends a lease, captures any deduction from the deposit and refunds the rest. */
  terminate(
    leaseId: string,
    termination?: LeaseTermination,
  ): AsyncResult<Lease>;
  /** Needs `leases.read`. */
  get(leaseId: string): AsyncResult<Lease>;
  list(options?: LeaseListOptions): AsyncResult<readonly Lease[]>;
  /**
   * Posts the rent of every due period of the organization's active leases on
   * the ledger, once per period, and returns how many posted.
   */
  postDueRent(options?: PostDueRentOptions): AsyncResult<number>;
  /** Moves a payment from the lease's balance due to rent received. */
  recordPayment(
    leaseId: string,
    payment: RentPaymentInput,
  ): AsyncResult<RentPayment>;
  /** The rent periods posted, newest first. */
  charges(
    leaseId: string,
    options?: { readonly pageSize?: number },
  ): AsyncResult<readonly LeaseCharge[]>;
  /** Needs `leases.maintain` or `leases.manage`. */
  fileMaintenance(
    input: MaintenanceRequestInput,
  ): AsyncResult<MaintenanceRequest>;
  /** Needs `leases.manage`. */
  updateMaintenance(
    requestId: string,
    update: MaintenanceUpdate,
  ): AsyncResult<MaintenanceRequest>;
  /** Every request with `leases.read`, else the ones the caller filed. */
  listMaintenance(
    options?: MaintenanceListOptions,
  ): AsyncResult<readonly MaintenanceRequest[]>;
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

function maintenanceOf(value: unknown, fn: string): MaintenanceRequest {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    unitId: textOf(row["unitId"]),
    title: textOf(row["title"]),
    // SAFETY: the SQL check constraint limits priority to these values.
    priority: textOf(row["priority"]) as MaintenancePriority,
    // SAFETY: the SQL check constraint limits status to these values.
    status: textOf(row["status"]) as MaintenanceStatus,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("leaseId", optionalText(row["leaseId"])),
    ...optional("description", optionalText(row["description"])),
    ...optional("reportedBy", optionalText(row["reportedBy"])),
    ...optional("assigneeId", optionalText(row["assigneeId"])),
    ...optional("resolvedAt", optionalInstant(row["resolvedAt"], "resolvedAt")),
  };
}

/** The `leases` SQL module as typed calls. */
export function createLeases(options: LeasesOptions): Leases {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const lease =
    (fn: string) =>
    (value: unknown): Lease =>
      leaseOf(value, fn);

  const client: Leases = {
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

      return tenant().andThen((organizationId) =>
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
          },
          lease("create_lease"),
        ),
      );
    },
    activate: (leaseId) =>
      call("activate_lease", { lease_id: leaseId }, lease("activate_lease")),
    renew: (leaseId, renewal) =>
      call(
        "renew_lease",
        {
          lease_id: leaseId,
          ends_on: renewal.endsOn.toString(),
          rent: renewal.rent ? amountText(renewal.rent) : null,
        },
        lease("renew_lease"),
      ),
    terminate: (leaseId, termination = {}) =>
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
      ),
    get: (leaseId) =>
      call("get_lease", { lease_id: leaseId }, lease("get_lease")),
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
        ),
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
    recordPayment: (leaseId, payment) =>
      call(
        "record_rent_payment",
        {
          lease_id: leaseId,
          amount: amountText(payment.amount),
          paid_at: instantArg(payment.paidAt),
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
    charges: (leaseId, list = {}) =>
      call(
        "list_lease_charges",
        { lease_id: leaseId, page_size: list.pageSize ?? null },
        (value) => recordsOf(value, "list_lease_charges").map(chargeOf),
      ),
    fileMaintenance: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "file_maintenance_request",
          {
            tenant: organizationId,
            unit_id: input.unitId,
            title: input.title,
            description: input.description ?? null,
            priority: input.priority ?? "normal",
            lease_id: input.leaseId ?? null,
          },
          (value) => maintenanceOf(value, "file_maintenance_request"),
        ),
      ),
    updateMaintenance: (requestId, update) =>
      call(
        "update_maintenance_request",
        {
          request_id: requestId,
          status: update.status ?? null,
          priority: update.priority ?? null,
          assignee_id: update.assigneeId ?? null,
        },
        (value) => maintenanceOf(value, "update_maintenance_request"),
      ),
    listMaintenance: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_maintenance_requests",
          {
            tenant: organizationId,
            unit_id: list.unitId ?? null,
            lease_id: list.leaseId ?? null,
            status: list.status ?? null,
            page_size: list.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_maintenance_requests").map((row) =>
              maintenanceOf(row, "list_maintenance_requests"),
            ),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "leases",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
