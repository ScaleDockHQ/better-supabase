import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { money } from "../../commerce/money.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  TILL_DEPOSIT_STATUSES,
  TILL_MOVEMENT_KINDS,
  TILL_SESSION_STATUSES,
} from "../../sql/modules/tills-values.ts";
import {
  applyTemporal,
  bigintOf,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a till session stands. */
export type TillSessionStatus = (typeof TILL_SESSION_STATUSES)[number];

/**
 * What a cash movement is. `cash_sale` and `cash_in` add cash, the others
 * remove it.
 */
export type TillMovementKind = (typeof TILL_MOVEMENT_KINDS)[number];

/** Where a cash deposit stands. */
export type TillDepositStatus = (typeof TILL_DEPOSIT_STATUSES)[number];

/** A cash register or drawer. */
export interface Till {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  /** An ISO 4217 code; every amount of the till is in it. */
  readonly currency: string;
  /** The accounting account that holds its cash. */
  readonly accountId?: string;
  readonly location?: string;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface TillInput {
  readonly name: string;
  /** An ISO 4217 code such as EUR. It cannot change later. */
  readonly currency: string;
  /**
   * The accounting account that holds the till's cash. Without it the till
   * books nothing.
   */
  readonly accountId?: string | null;
  readonly location?: string | null;
}

export interface TillUpdate {
  readonly name?: string;
  readonly accountId?: string | null;
  readonly location?: string | null;
  /** `true` archives the till, `false` brings it back. */
  readonly archived?: boolean;
}

/** One shift at a till. */
export interface TillSession {
  readonly id: string;
  readonly tillId: string;
  readonly organizationId: string;
  readonly status: TillSessionStatus;
  readonly openingFloat: Money;
  /** The cash the drawer should hold now: the float plus the movements. */
  readonly expected: Money;
  readonly openedBy?: string;
  readonly openedAt: Temporal.Instant;
  readonly closedBy?: string;
  readonly closedAt?: Temporal.Instant;
  readonly notes?: string;
}

/** Cash that went into or out of the drawer. */
export interface TillMovement {
  readonly id: string;
  readonly sessionId: string;
  readonly kind: TillMovementKind;
  /** Above zero; the kind gives the direction. */
  readonly amount: Money;
  readonly reason?: string;
  readonly reference?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

/** The end-of-day count of a session. */
export interface TillCount {
  readonly id: string;
  readonly sessionId: string;
  /** Note and coin value in minor units to how many were counted. */
  readonly denominations?: Readonly<Record<string, number>>;
  readonly expected: Money;
  readonly counted: Money;
  /** Counted minus expected: above zero is an overage, below a shortage. */
  readonly variance: Money;
  readonly countedBy?: string;
  readonly countedAt: Temporal.Instant;
  /** The accounting entry that books a non-zero variance. */
  readonly entryId?: string;
  readonly notes?: string;
}

/** Counted cash taken to the bank. */
export interface TillDeposit {
  readonly id: string;
  readonly sessionId: string;
  readonly amount: Money;
  readonly depositedOn: Temporal.PlainDate;
  readonly reference?: string;
  readonly status: TillDepositStatus;
  /** The accounting entry of the deposit. */
  readonly entryId?: string;
  /** The banking transaction it was reconciled to. */
  readonly bankTransactionId?: string;
  readonly reconciledAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

/** A session with its movements, count and deposits. */
export interface TillSessionDetail extends TillSession {
  readonly movements: readonly TillMovement[];
  readonly count?: TillCount;
  readonly deposits: readonly TillDeposit[];
}

export interface TillSessionListOptions {
  readonly tillId?: string;
  readonly status?: TillSessionStatus;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

/** The end-of-day count: denominations or a total. */
export interface CloseTillSessionInput {
  /**
   * Note and coin value in minor units to how many there are, such as `{ "500":
   * 3 }`. The count is their sum.
   */
  readonly denominations?: Readonly<Record<string, number>>;
  /** The counted total, used when there are no denominations. */
  readonly amount?: Money;
  readonly notes?: string;
}

export interface DepositTillCashInput {
  readonly amount: Money;
  /** Default today. */
  readonly depositedOn?: Temporal.PlainDate;
  readonly reference?: string;
}

export interface Tills {
  /** Creates a till; needs `tills.manage`. */
  createTill(input: TillInput): AsyncResultType<Till>;
  /**
   * Renames, archives or changes the cash account of a till; needs
   * `tills.manage`.
   */
  updateTill(input: {
    tillId: string;
    input: TillUpdate;
  }): AsyncResultType<Till>;
  /** Tills by name; archived ones only with `includeArchived`. */
  listTills(options?: {
    readonly includeArchived?: boolean;
  }): AsyncResultType<readonly Till[]>;
  /**
   * Starts a shift with the cash in the drawer. A till has one open session;
   * needs `tills.write`.
   */
  openSession(
    input: { tillId: string } & {
      readonly openingFloat?: Money;
      readonly notes?: string;
    },
  ): AsyncResultType<TillSession>;
  getSession(sessionId: string): AsyncResultType<TillSessionDetail>;
  listSessions(
    options?: TillSessionListOptions,
  ): AsyncResultType<readonly TillSession[]>;
  /**
   * Records cash in or out of an open session; needs `tills.write`. A refund or
   * cash out cannot take more than the drawer holds.
   */
  recordMovement(
    input: { sessionId: string; kind: TillMovementKind; amount: Money } & {
      readonly reason?: string;
      readonly reference?: string;
    },
  ): AsyncResultType<TillMovement>;
  /**
   * Counts the drawer and ends the session; needs `tills.write`. The variance
   * is booked in accounting when the till has a cash account.
   */
  closeSession(input: {
    sessionId: string;
    input: CloseTillSessionInput;
  }): AsyncResultType<TillSessionDetail>;
  /**
   * Takes counted cash to the bank from a closed session, never more than the
   * count in total; needs `tills.manage`.
   */
  deposit(input: {
    sessionId: string;
    input: DepositTillCashInput;
  }): AsyncResultType<TillDeposit>;
  /**
   * Matches a pending deposit to its bank transaction through the banking
   * block; needs `tills.manage`.
   */
  reconcileDeposit(input: {
    depositId: string;
    bankTransactionId: string;
  }): AsyncResultType<TillDeposit>;
}

/** Options for {@link createTills}. */
export interface TillsOptions extends BlockOptions {
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Tills>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
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

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

const amountOf = (value: unknown, currency: string): Money =>
  money(bigintOf(value, "amount"), currency);

function plainDate(value: unknown, name: string): Temporal.PlainDate {
  if (typeof value !== "string") {
    throw new TypeError(`${name} is not a date`);
  }

  return temporal().PlainDate.from(value);
}

function denominationsOf(
  value: unknown,
): Readonly<Record<string, number>> | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }

  return Object.fromEntries(
    Object.entries(value).flatMap(([key, count]) =>
      typeof count === "number" ? [[key, count] as const] : [],
    ),
  );
}

function tillOf(value: unknown, fn: string): Till {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    currency: textOf(row["currency"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("accountId", optionalText(row["accountId"])),
    ...optional("location", optionalText(row["location"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
  };
}

function sessionOf(value: unknown, fn: string): TillSession {
  const row = recordOf(value, fn);
  const currency = textOf(row["currency"]);

  return {
    id: textOf(row["id"]),
    tillId: textOf(row["tillId"]),
    organizationId: textOf(row["organizationId"]),
    status: enumOrThrow(row["status"], TILL_SESSION_STATUSES, "session status"),
    openingFloat: amountOf(row["openingFloat"], currency),
    expected: amountOf(row["expected"], currency),
    openedAt: requiredInstant(row["openedAt"], "openedAt"),
    ...optional("openedBy", optionalText(row["openedBy"])),
    ...optional("closedBy", optionalText(row["closedBy"])),
    ...optional("closedAt", optionalInstant(row["closedAt"])),
    ...optional("notes", optionalText(row["notes"])),
  };
}

function movementOf(value: unknown, fn: string): TillMovement {
  const row = recordOf(value, fn);
  const currency = textOf(row["currency"]);

  return {
    id: textOf(row["id"]),
    sessionId: textOf(row["sessionId"]),
    kind: enumOrThrow(row["kind"], TILL_MOVEMENT_KINDS, "movement kind"),
    amount: amountOf(row["amount"], currency),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("reason", optionalText(row["reason"])),
    ...optional("reference", optionalText(row["reference"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function countOf(value: unknown, fn: string): TillCount {
  const row = recordOf(value, fn);
  const currency = textOf(row["currency"]);

  return {
    id: textOf(row["id"]),
    sessionId: textOf(row["sessionId"]),
    expected: amountOf(row["expected"], currency),
    counted: amountOf(row["counted"], currency),
    variance: amountOf(row["variance"], currency),
    countedAt: requiredInstant(row["countedAt"], "countedAt"),
    ...optional("denominations", denominationsOf(row["denominations"])),
    ...optional("countedBy", optionalText(row["countedBy"])),
    ...optional("entryId", optionalText(row["entryId"])),
    ...optional("notes", optionalText(row["notes"])),
  };
}

function depositOf(value: unknown, fn: string): TillDeposit {
  const row = recordOf(value, fn);
  const currency = textOf(row["currency"]);

  return {
    id: textOf(row["id"]),
    sessionId: textOf(row["sessionId"]),
    amount: amountOf(row["amount"], currency),
    depositedOn: plainDate(row["depositedOn"], "depositedOn"),
    status: enumOrThrow(row["status"], TILL_DEPOSIT_STATUSES, "deposit status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("reference", optionalText(row["reference"])),
    ...optional("entryId", optionalText(row["entryId"])),
    ...optional("bankTransactionId", optionalText(row["bankTransactionId"])),
    ...optional("reconciledAt", optionalInstant(row["reconciledAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function detailOf(value: unknown, fn: string): TillSessionDetail {
  const row = recordOf(value, fn);
  const session = sessionOf(row, fn);
  const count = row["count"];

  return {
    ...session,
    movements: recordsOf(row["movements"], fn).map((entry) =>
      movementOf(entry, fn),
    ),
    deposits: recordsOf(row["deposits"], fn).map((entry) =>
      depositOf(entry, fn),
    ),
    ...optional(
      "count",
      count === null || count === undefined ? undefined : countOf(count, fn),
    ),
  };
}

/**
 * Tills: shifts at a register with an opening float, cash in and out, an
 * end-of-day count that books its difference in accounting, and deposits that
 * reconcile to bank transactions.
 */
export function createTills(options: TillsOptions): Tills {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);

  const client: Tills = {
    createTill: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_till",
          { tenant: organizationId, input: definedOf(input) },
          (value) => tillOf(value, "create_till"),
        ),
      ),
    updateTill: ({ tillId, input }) =>
      call(
        "update_till",
        { till_id: tillId, input: definedOf(input) },
        (value) => tillOf(value, "update_till"),
      ),
    listTills: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_tills",
          {
            tenant: organizationId,
            filters: { archived: list.includeArchived === true },
          },
          (value) =>
            recordsOf(value, "list_tills").map((row) =>
              tillOf(row, "list_tills"),
            ),
        ),
      ),
    openSession: ({ tillId, ...open }) =>
      call(
        "open_till_session",
        {
          till_id: tillId,
          ...(open.openingFloat === undefined
            ? {}
            : { opening_float: open.openingFloat.amount.toString() }),
          ...(open.notes === undefined ? {} : { notes: open.notes }),
        },
        (value) => sessionOf(value, "open_till_session"),
      ),
    getSession: (sessionId) =>
      call("get_till_session", { session_id: sessionId }, (value) =>
        detailOf(value, "get_till_session"),
      ),
    listSessions: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_till_sessions",
          { tenant: organizationId, filters: definedOf(list) },
          (value) =>
            recordsOf(value, "list_till_sessions").map((row) =>
              sessionOf(row, "list_till_sessions"),
            ),
        ),
      ),
    recordMovement: ({ sessionId, kind, amount, ...extra }) =>
      call(
        "record_till_movement",
        {
          session_id: sessionId,
          kind,
          amount: amount.amount.toString(),
          ...(extra.reason === undefined ? {} : { reason: extra.reason }),
          ...(extra.reference === undefined
            ? {}
            : { reference: extra.reference }),
        },
        (value) => movementOf(value, "record_till_movement"),
      ),
    closeSession: ({ sessionId, input }) =>
      call(
        "close_till_session",
        {
          session_id: sessionId,
          input: definedOf({
            denominations: input.denominations,
            amount: input.amount?.amount.toString(),
            notes: input.notes,
          }),
        },
        (value) => detailOf(value, "close_till_session"),
      ),
    deposit: ({ sessionId, input }) =>
      call(
        "deposit_till_cash",
        {
          session_id: sessionId,
          input: definedOf({
            amount: input.amount.amount.toString(),
            depositedOn: input.depositedOn?.toString(),
            reference: input.reference,
          }),
        },
        (value) => depositOf(value, "deposit_till_cash"),
      ),
    reconcileDeposit: ({ depositId, bankTransactionId }) =>
      call(
        "reconcile_till_deposit",
        { deposit_id: depositId, bank_transaction_id: bankTransactionId },
        (value) => depositOf(value, "reconcile_till_deposit"),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "tills",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
