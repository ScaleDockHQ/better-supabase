import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { isCurrency, money } from "../../commerce/money.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  applyTemporal,
  bigintOf,
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

export interface LedgerOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Ledger>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/**
 * An account. Amounts are integers in the account's unit: minor units for an
 * ISO 4217 currency, or a custom unit (`item`, `days`, `points`) at `scale`
 * decimal places.
 */
export interface LedgerAccount {
  readonly id: string;
  readonly organizationId: string;
  /** What the account is for: `credit`, `stock`, `receivable`, `points`. */
  readonly kind: string;
  /** Unique in the organization. */
  readonly code: string;
  readonly name: string;
  readonly unit: string;
  readonly scale: number;
  /** The record the account belongs to, such as a party or a variant. */
  readonly holderType?: string;
  readonly holderId?: string;
  /** The member who can read the account without a permission. */
  readonly ownerId?: string;
  readonly allowNegative: boolean;
  /** A permission key that also grants reading the account. */
  readonly readPermission?: string;
  /** The module that posts to the account; apps can't post to it directly. */
  readonly managedBy?: string;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly balance: bigint;
  /** Held by active holds. */
  readonly held: bigint;
  /** The balance less what is held. */
  readonly available: bigint;
  readonly closedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export interface LedgerAccountInput {
  readonly kind: string;
  readonly code: string;
  readonly name: string;
  /** An ISO 4217 code, or a lowercase custom unit. */
  readonly unit: string;
  /** Decimal places of a custom unit. Default 0. */
  readonly scale?: number;
  readonly holder?: { readonly type: string; readonly id: string };
  readonly ownerId?: string;
  /** Default `false`: postings can't take the available balance below zero. */
  readonly allowNegative?: boolean;
  readonly readPermission?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** One side of a transaction. A `Money` must be in the account's currency. */
export interface LedgerLine {
  readonly accountId: string;
  /** Signed: positive adds to the account, negative takes from it. */
  readonly amount: bigint | Money;
}

export interface LedgerEntry {
  readonly id: string;
  readonly accountId: string;
  readonly amount: bigint;
  readonly unit: string;
}

export interface LedgerTransaction {
  readonly id: string;
  readonly organizationId: string;
  readonly kind: string;
  readonly referenceType?: string;
  readonly referenceId?: string;
  readonly memo?: string;
  readonly idempotencyKey?: string;
  /** The transaction this one reverses. */
  readonly reverses?: string;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly effectiveAt: Temporal.Instant;
  readonly actorId?: string;
  readonly createdAt: Temporal.Instant;
  /** Balanced per unit. */
  readonly entries: readonly LedgerEntry[];
}

export interface LedgerTransactionInput {
  /** Lowercase with dots, such as `credit.grant`. */
  readonly kind: string;
  /** At least two lines that sum to zero per unit. */
  readonly lines: readonly LedgerLine[];
  readonly reference?: { readonly type: string; readonly id: string };
  readonly memo?: string;
  /** A second post with the same key returns the first transaction. */
  readonly idempotencyKey?: string;
  /** Default: now. */
  readonly effectiveAt?: Temporal.Instant;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** An entry on one account, with its transaction. */
export interface LedgerAccountEntry extends LedgerEntry {
  readonly transactionId: string;
  readonly kind: string;
  readonly referenceType?: string;
  readonly referenceId?: string;
  readonly memo?: string;
  readonly reverses?: string;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly effectiveAt: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export type LedgerHoldStatus = "active" | "captured" | "released" | "expired";

export interface LedgerHold {
  readonly id: string;
  readonly organizationId: string;
  readonly accountId: string;
  readonly amount: bigint;
  readonly status: LedgerHoldStatus;
  readonly referenceType?: string;
  readonly referenceId?: string;
  readonly expiresAt?: Temporal.Instant;
  /** The capture's transaction. */
  readonly transactionId?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface LedgerHoldInput {
  readonly amount: bigint | Money;
  readonly reference?: { readonly type: string; readonly id: string };
  readonly expiresAt?: Temporal.Instant;
}

export interface LedgerCaptureInput {
  /** The account that receives the captured amount. */
  readonly toAccountId: string;
  /** Default: the whole hold. A partial capture releases the rest. */
  readonly amount?: bigint | Money;
  /** Default `ledger.capture`. */
  readonly kind?: string;
  readonly memo?: string;
}

export interface LedgerAccountListOptions {
  readonly kind?: string;
  readonly holder?: { readonly type: string; readonly id: string };
  readonly pageSize?: number;
}

export interface Ledger {
  /** Opens an account in the block's tenant. Needs `ledger.manage`. */
  openAccount(input: LedgerAccountInput): AsyncResult<LedgerAccount>;
  /** Needs `ledger.manage`; the balance must be zero with no active holds. */
  closeAccount(accountId: string): AsyncResult<LedgerAccount>;
  /** The tenant's accounts the caller can read, by kind or holder. */
  accounts(
    options?: LedgerAccountListOptions,
  ): AsyncResult<readonly LedgerAccount[]>;
  /**
   * A record's accounts the caller can read, such as a party's credits. The
   * record decides the tenant.
   */
  holderAccounts(
    holder: SubjectRef,
    options?: { readonly kind?: string },
  ): AsyncResult<readonly LedgerAccount[]>;
  /** Newest first; `before` pages back. */
  entries(
    accountId: string,
    options?: {
      readonly before?: Temporal.Instant;
      readonly pageSize?: number;
    },
  ): AsyncResult<readonly LedgerAccountEntry[]>;
  transaction(transactionId: string): AsyncResult<LedgerTransaction>;
  /**
   * Posts a balanced transaction in the block's tenant. Needs `ledger.post`;
   * accounts another module manages refuse it.
   */
  post(input: LedgerTransactionInput): AsyncResult<LedgerTransaction>;
  /** Posts the opposite entries. A transaction reverses once. */
  reverse(
    transactionId: string,
    options?: { readonly memo?: string },
  ): AsyncResult<LedgerTransaction>;
  /** Reserves part of the available balance. Needs `ledger.post`. */
  hold(accountId: string, input: LedgerHoldInput): AsyncResult<LedgerHold>;
  /** Moves held funds to another account. */
  capture(holdId: string, input: LedgerCaptureInput): AsyncResult<LedgerHold>;
  release(holdId: string): AsyncResult<LedgerHold>;
}

const HOLD_STATUSES: readonly LedgerHoldStatus[] = [
  "active",
  "captured",
  "released",
  "expired",
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

const metadataOf = (value: unknown): Readonly<Record<string, unknown>> =>
  isRecord(value) ? value : {};

/** A signed amount as a function argument: an integer as text. */
const amountArg = (value: bigint | Money): string =>
  (typeof value === "bigint" ? value : value.amount).toString();

/** An account's balance as `Money`, or `undefined` for a custom unit. */
export function ledgerMoney(
  account: Pick<LedgerAccount, "unit" | "balance">,
  amount: bigint = account.balance,
): Money | undefined {
  return isCurrency(account.unit) ? money(amount, account.unit) : undefined;
}

function accountOf(value: unknown, fn: string): LedgerAccount {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kind: textOf(row["kind"]),
    code: textOf(row["code"]),
    name: textOf(row["name"]),
    unit: textOf(row["unit"]),
    scale: Number(row["scale"] ?? 0),
    allowNegative: row["allowNegative"] === true,
    metadata: metadataOf(row["metadata"]),
    balance: bigintOf(row["balance"], "balance"),
    held: bigintOf(row["held"], "held"),
    available: bigintOf(row["available"], "available"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("holderType", optionalText(row["holderType"])),
    ...optional("holderId", optionalText(row["holderId"])),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional("readPermission", optionalText(row["readPermission"])),
    ...optional("managedBy", optionalText(row["managedBy"])),
    ...optional("closedAt", optionalInstant(row["closedAt"])),
  };
}

function entryOf(value: unknown, fn: string): LedgerEntry {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    accountId: textOf(row["accountId"]),
    amount: bigintOf(row["amount"], "amount"),
    unit: textOf(row["unit"]),
  };
}

function transactionOf(value: unknown, fn: string): LedgerTransaction {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kind: textOf(row["kind"]),
    metadata: metadataOf(row["metadata"]),
    effectiveAt: requiredInstant(row["effectiveAt"], "effectiveAt"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    entries: recordsOf(row["entries"], fn).map((entry) => entryOf(entry, fn)),
    ...optional("referenceType", optionalText(row["referenceType"])),
    ...optional("referenceId", optionalText(row["referenceId"])),
    ...optional("memo", optionalText(row["memo"])),
    ...optional("idempotencyKey", optionalText(row["idempotencyKey"])),
    ...optional("reverses", optionalText(row["reverses"])),
    ...optional("actorId", optionalText(row["actorId"])),
  };
}

function accountEntryOf(value: unknown, fn: string): LedgerAccountEntry {
  const row = recordOf(value, fn);

  return {
    ...entryOf(row, fn),
    transactionId: textOf(row["transactionId"]),
    kind: textOf(row["kind"]),
    metadata: metadataOf(row["metadata"]),
    effectiveAt: requiredInstant(row["effectiveAt"], "effectiveAt"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("referenceType", optionalText(row["referenceType"])),
    ...optional("referenceId", optionalText(row["referenceId"])),
    ...optional("memo", optionalText(row["memo"])),
    ...optional("reverses", optionalText(row["reverses"])),
  };
}

function holdOf(value: unknown, fn: string): LedgerHold {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    accountId: textOf(row["accountId"]),
    amount: bigintOf(row["amount"], "amount"),
    status: enumOrThrow(row["status"], HOLD_STATUSES, "ledger hold status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("referenceType", optionalText(row["referenceType"])),
    ...optional("referenceId", optionalText(row["referenceId"])),
    ...optional("expiresAt", optionalInstant(row["expiresAt"])),
    ...optional("transactionId", optionalText(row["transactionId"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

/** The `ledger` SQL module as typed calls. */
export function createLedger(options: LedgerOptions): Ledger {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Ledger = {
    openAccount: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "open_ledger_account",
          {
            tenant: organizationId,
            kind: input.kind,
            code: input.code,
            name: input.name,
            unit: input.unit,
            scale: input.scale ?? 0,
            holder_type: input.holder?.type ?? null,
            holder_id: input.holder?.id ?? null,
            owner_id: input.ownerId ?? null,
            allow_negative: input.allowNegative ?? false,
            read_permission: input.readPermission ?? null,
            metadata: input.metadata ?? null,
          },
          (value) => accountOf(value, "open_ledger_account"),
        ),
      ),
    closeAccount: (accountId) =>
      call("close_ledger_account", { account_id: accountId }, (value) =>
        accountOf(value, "close_ledger_account"),
      ),
    accounts: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_ledger_accounts",
          {
            tenant: organizationId,
            kind: list.kind ?? null,
            holder_type: list.holder?.type ?? null,
            holder_id: list.holder?.id ?? null,
            page_size: list.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_ledger_accounts").map((row) =>
              accountOf(row, "list_ledger_accounts"),
            ),
        ),
      ),
    holderAccounts: (holder, list = {}) =>
      call(
        "list_ledger_accounts",
        {
          tenant: null,
          kind: list.kind ?? null,
          holder_type: holder.type,
          holder_id: holder.id,
          page_size: null,
        },
        (value) =>
          recordsOf(value, "list_ledger_accounts").map((row) =>
            accountOf(row, "list_ledger_accounts"),
          ),
      ),
    entries: (accountId, list = {}) =>
      call(
        "ledger_account_entries",
        {
          account_id: accountId,
          before: instantArg(list.before),
          page_size: list.pageSize ?? null,
        },
        (value) =>
          recordsOf(value, "ledger_account_entries").map((row) =>
            accountEntryOf(row, "ledger_account_entries"),
          ),
      ),
    transaction: (transactionId) =>
      call(
        "get_ledger_transaction",
        { transaction_id: transactionId },
        (value) => transactionOf(value, "get_ledger_transaction"),
      ),
    post: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "post_ledger_transaction",
          {
            tenant: organizationId,
            kind: input.kind,
            lines: input.lines.map((line) => ({
              account: line.accountId,
              amount: amountArg(line.amount),
            })),
            reference_type: input.reference?.type ?? null,
            reference_id: input.reference?.id ?? null,
            memo: input.memo ?? null,
            idempotency_key: input.idempotencyKey ?? null,
            effective_at: instantArg(input.effectiveAt),
            metadata: input.metadata ?? null,
          },
          (value) => transactionOf(value, "post_ledger_transaction"),
        ),
      ),
    reverse: (transactionId, reverse = {}) =>
      call(
        "reverse_ledger_transaction",
        { transaction_id: transactionId, memo: reverse.memo ?? null },
        (value) => transactionOf(value, "reverse_ledger_transaction"),
      ),
    hold: (accountId, input) =>
      call(
        "place_ledger_hold",
        {
          account_id: accountId,
          amount: amountArg(input.amount),
          reference_type: input.reference?.type ?? null,
          reference_id: input.reference?.id ?? null,
          expires_at: instantArg(input.expiresAt),
        },
        (value) => holdOf(value, "place_ledger_hold"),
      ),
    capture: (holdId, input) =>
      call(
        "capture_ledger_hold",
        {
          hold_id: holdId,
          to_account: input.toAccountId,
          amount: input.amount === undefined ? null : amountArg(input.amount),
          kind: input.kind ?? "ledger.capture",
          memo: input.memo ?? null,
        },
        (value) => holdOf(value, "capture_ledger_hold"),
      ),
    release: (holdId) =>
      call("release_ledger_hold", { hold_id: holdId }, (value) =>
        holdOf(value, "release_ledger_hold"),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "ledger",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
