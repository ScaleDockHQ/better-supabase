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
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions, RecordRef } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { optionalRecordRefOf } from "../../core/block-subjects.ts";
import { temporal } from "../../core/temporal-required.ts";
import { amountText, optionalMoneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface ContractsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the contract's extra columns
   * (`blocks.contracts.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `create` and `update`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Contracts<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export type ContractStatus =
  | "draft"
  | "in_review"
  | "out_for_signature"
  | "active"
  | "expired"
  | "terminated";

/**
 * A step in the contract lifecycle. `submit` and `return` need
 * `contracts.write`; the others need `contracts.manage`.
 */
export type ContractAction =
  | "submit"
  | "return"
  | "activate"
  | "recall"
  | "terminate";

/** A contract. `F` types the extra columns the `fields` schema describes. */
export interface Contract<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly title: string;
  readonly description?: string;
  /** The other party: a registered subject, such as a party. */
  readonly counterparty?: RecordRef;
  readonly ownerId?: string;
  readonly status: ContractStatus;
  readonly value?: Money;
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  readonly autoRenew: boolean;
  /** How far an auto-renewal moves `endsOn`. */
  readonly renewalMonths: number;
  /** How many days before `endsOn` notice to cancel is due. */
  readonly noticeDays: number;
  /** `endsOn` less `noticeDays`: when the renewal reminder fires. */
  readonly noticeDeadline?: Temporal.PlainDate;
  readonly renewedCount: number;
  /** The signatures block request while it is out for signature. */
  readonly signatureRequestId?: string;
  readonly signedAt?: Temporal.Instant;
  readonly terminatedAt?: Temporal.Instant;
  readonly terminationReason?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface ContractInput<F extends object = Record<never, never>> {
  readonly title: string;
  readonly description?: string;
  readonly counterparty?: RecordRef;
  /** Default: the caller. */
  readonly ownerId?: string;
  readonly value?: Money;
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  /** Default `false`. */
  readonly autoRenew?: boolean;
  /** Default 12. */
  readonly renewalMonths?: number;
  /** Default 30. */
  readonly noticeDays?: number;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/**
 * What `update` changes; a key left out keeps its value. An active contract
 * takes `description`, `ownerId` and the renewal terms only.
 */
export type ContractChanges<F extends object = Record<never, never>> = Partial<
  ContractInput<F>
>;

export interface ContractListOptions {
  readonly status?: ContractStatus;
  readonly counterparty?: RecordRef;
  readonly ownerId?: string;
  /** Active contracts whose notice deadline is on or before this date. */
  readonly renewingBefore?: Temporal.PlainDate;
  /** The `createdAt` of the last contract of the previous page. */
  readonly before?: Temporal.Instant;
  readonly pageSize?: number;
}

export interface ContractSignatureInput {
  /** Members who sign. */
  readonly signers: readonly string[];
  /** Default `parallel`. */
  readonly signOrder?: "parallel" | "sequential";
  readonly message?: string;
}

export type ObligationStatus = "open" | "done" | "waived";

/** Something a party owes under a contract, with a due date and an owner. */
export interface ContractObligation {
  readonly id: string;
  readonly organizationId: string;
  readonly contractId: string;
  readonly title: string;
  readonly description?: string;
  readonly dueOn?: Temporal.PlainDate;
  readonly ownerId?: string;
  readonly status: ObligationStatus;
  /** Open and past its due date. */
  readonly overdue: boolean;
  readonly completedAt?: Temporal.Instant;
  readonly completedBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface ObligationInput {
  readonly title: string;
  readonly description?: string;
  readonly dueOn?: Temporal.PlainDate;
  readonly ownerId?: string;
  /** Changes this obligation instead of adding one. */
  readonly obligationId?: string;
}

export interface ObligationListOptions {
  readonly contractId?: string;
  readonly ownerId?: string;
  readonly openOnly?: boolean;
  readonly dueBefore?: Temporal.PlainDate;
  readonly pageSize?: number;
}

export interface ContractRenewals {
  readonly renewed: number;
  readonly expired: number;
}

export interface Contracts<F extends object = Record<never, never>> {
  /** Creates a draft. Needs `contracts.write`. */
  create(
    organizationId: string,
    input: ContractInput<F>,
  ): AsyncResult<Contract<F>>;
  /** Needs `contracts.write`; fails with `CONTRACT_LOCKED` past review. */
  update(
    contractId: string,
    changes: ContractChanges<F>,
  ): AsyncResult<Contract<F>>;
  /** Moves the contract one step through its lifecycle. */
  transition(
    contractId: string,
    action: ContractAction,
    reason?: string,
  ): AsyncResult<Contract<F>>;
  /**
   * Freezes the contract as a version and opens a signature request on it.
   * Signing completes it to `active`; a decline returns it to review.
   */
  sendForSignature(
    contractId: string,
    input: ContractSignatureInput,
  ): AsyncResult<Contract<F>>;
  get(contractId: string): AsyncResult<Contract<F>>;
  /** Newest first. */
  list(
    organizationId: string,
    options?: ContractListOptions,
  ): AsyncResult<readonly Contract<F>[]>;
  /** The contracts with a counterparty, in every organization the caller reads. */
  forCounterparty(
    counterparty: RecordRef,
    options?: Omit<ContractListOptions, "counterparty">,
  ): AsyncResult<readonly Contract<F>[]>;
  /**
   * Renews the auto-renewing active contracts past their end date and expires
   * the rest. Service role only; run it daily.
   */
  runRenewals(asOf?: Temporal.PlainDate): AsyncResult<ContractRenewals>;
  /** Needs `contracts.write`. */
  saveObligation(
    contractId: string,
    input: ObligationInput,
  ): AsyncResult<ContractObligation>;
  /** Needs `contracts.write`, or being the obligation's owner. */
  setObligationStatus(
    obligationId: string,
    status: ObligationStatus,
  ): AsyncResult<ContractObligation>;
  deleteObligation(obligationId: string): AsyncResult<ContractObligation>;
  /** The earliest due first. */
  obligations(
    organizationId: string,
    options?: ObligationListOptions,
  ): AsyncResult<readonly ContractObligation[]>;
}

const STATUSES: readonly ContractStatus[] = [
  "draft",
  "in_review",
  "out_for_signature",
  "active",
  "expired",
  "terminated",
];

const OBLIGATION_STATUSES: readonly ObligationStatus[] = [
  "open",
  "done",
  "waived",
];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value)
    : undefined;

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

function contractOf(value: unknown, fn: string): Contract {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    title: textOf(row["title"]),
    status: enumOrThrow(row["status"], STATUSES, "contract status"),
    autoRenew: row["autoRenew"] === true,
    renewalMonths: numberOf(row["renewalMonths"]),
    noticeDays: numberOf(row["noticeDays"]),
    renewedCount: numberOf(row["renewedCount"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("description", optionalText(row["description"])),
    ...optional(
      "counterparty",
      optionalRecordRefOf(row["counterpartyType"], row["counterpartyId"]),
    ),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional(
      "value",
      optionalMoneyOf(row["value"], row["currency"], "contract value"),
    ),
    ...optional("startsOn", optionalDate(row["startsOn"])),
    ...optional("endsOn", optionalDate(row["endsOn"])),
    ...optional("noticeDeadline", optionalDate(row["noticeDeadline"])),
    ...optional("signatureRequestId", optionalText(row["signatureRequestId"])),
    ...optional("signedAt", optionalInstant(row["signedAt"])),
    ...optional("terminatedAt", optionalInstant(row["terminatedAt"])),
    ...optional("terminationReason", optionalText(row["terminationReason"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function obligationOf(value: unknown, fn: string): ContractObligation {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    contractId: textOf(row["contractId"]),
    title: textOf(row["title"]),
    status: enumOrThrow(
      row["status"],
      OBLIGATION_STATUSES,
      "obligation status",
    ),
    overdue: row["overdue"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("description", optionalText(row["description"])),
    ...optional("dueOn", optionalDate(row["dueOn"])),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    ...optional("completedBy", optionalText(row["completedBy"])),
  };
}

/** The attrs object create_contract and update_contract read. */
function attrsOf(input: ContractChanges<object>): Record<string, unknown> {
  const attrs: Record<string, unknown> = {};

  const set = (key: string, value: unknown): void => {
    if (value !== undefined) {
      attrs[key] = value;
    }
  };

  set("title", input.title);
  set("description", input.description);
  set("counterpartyType", input.counterparty?.type);
  set("counterpartyId", input.counterparty?.id);
  set("ownerId", input.ownerId);
  set("value", input.value === undefined ? undefined : amountText(input.value));
  set("currency", input.value?.currency);
  set("startsOn", input.startsOn?.toString());
  set("endsOn", input.endsOn?.toString());
  set("autoRenew", input.autoRenew);
  set("renewalMonths", input.renewalMonths);
  set("noticeDays", input.noticeDays);

  return attrs;
}

/** The `contracts` SQL module as typed calls. */
export function createContracts<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ContractsOptions<S>): Contracts<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(options.fields, "contract fields");

  const one = (fn: string) => (value: unknown) => contractOf(value, fn);

  const obligation = (fn: string) => (value: unknown) =>
    obligationOf(value, fn);

  const listContracts = (
    tenant: string | null,
    list: ContractListOptions,
  ): AsyncResult<readonly Contract<F>[]> =>
    call(
      "list_contracts",
      {
        tenant,
        status: list.status ?? null,
        counterparty_type: list.counterparty?.type ?? null,
        counterparty_id: list.counterparty?.id ?? null,
        owner_id: list.ownerId ?? null,
        renewing_before: list.renewingBefore?.toString() ?? null,
        before: instantArg(list.before) ?? null,
        page_size: list.pageSize ?? null,
      },
      (value) =>
        recordsOf(value, "list_contracts").map((row) =>
          contractOf(row, "list_contracts"),
        ),
    ).andThen(fields.rows);

  const client: Contracts<F> = {
    create: (organizationId, input) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "create_contract",
            {
              tenant: organizationId,
              attrs: attrsOf(input),
              ...(checked === undefined ? {} : { fields: checked }),
            },
            one("create_contract"),
          ).andThen(fields.row),
        ),
    update: (contractId, changes) =>
      fields
        .args(changes.fields)
        .andThen((checked) =>
          call(
            "update_contract",
            {
              contract_id: contractId,
              attrs: attrsOf(changes),
              ...(checked === undefined ? {} : { fields: checked }),
            },
            one("update_contract"),
          ).andThen(fields.row),
        ),
    transition: (contractId, action, reason) =>
      call(
        "transition_contract",
        { contract_id: contractId, action, reason: reason ?? null },
        one("transition_contract"),
      ).andThen(fields.row),
    sendForSignature: (contractId, input) =>
      call(
        "send_contract_for_signature",
        {
          contract_id: contractId,
          signers: input.signers,
          sign_order: input.signOrder ?? "parallel",
          message: input.message ?? null,
        },
        one("send_contract_for_signature"),
      ).andThen(fields.row),
    get: (contractId) =>
      call(
        "get_contract",
        { contract_id: contractId },
        one("get_contract"),
      ).andThen(fields.row),
    list: (organizationId, list = {}) => listContracts(organizationId, list),
    forCounterparty: (counterparty, list = {}) =>
      listContracts(null, { ...list, counterparty }),
    runRenewals: (asOf) =>
      call(
        "run_contract_renewals",
        { as_of: asOf?.toString() ?? null },
        (value) => {
          const row = recordOf(value, "run_contract_renewals");

          return {
            renewed: numberOf(row["renewed"]),
            expired: numberOf(row["expired"]),
          };
        },
      ),
    saveObligation: (contractId, input) =>
      call(
        "save_obligation",
        {
          contract_id: contractId,
          title: input.title,
          due_on: input.dueOn?.toString() ?? null,
          owner_id: input.ownerId ?? null,
          description: input.description ?? null,
          obligation_id: input.obligationId ?? null,
        },
        obligation("save_obligation"),
      ),
    setObligationStatus: (obligationId, status) =>
      call(
        "set_obligation_status",
        { obligation_id: obligationId, status },
        obligation("set_obligation_status"),
      ),
    deleteObligation: (obligationId) =>
      call(
        "delete_obligation",
        { obligation_id: obligationId },
        obligation("delete_obligation"),
      ),
    obligations: (organizationId, list = {}) =>
      call(
        "list_obligations",
        {
          tenant: organizationId,
          contract_id: list.contractId ?? null,
          owner_id: list.ownerId ?? null,
          open_only: list.openOnly ?? false,
          due_before: list.dueBefore?.toString() ?? null,
          page_size: list.pageSize ?? null,
        },
        (value) =>
          recordsOf(value, "list_obligations").map((row) =>
            obligationOf(row, "list_obligations"),
          ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "contracts",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
