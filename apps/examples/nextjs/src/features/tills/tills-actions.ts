"use server";

import { err, invalidInput, ok } from "better-supabase";
import { parseMt940 } from "better-supabase/blocks/banking";
import { parseMoney } from "better-supabase/commerce";
import * as v from "valibot";

import { BANKING_TAG } from "@/features/banking/banking-cache";
import { Decimal, Id, Optional, given } from "@/lib/form-input";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { planCashAccount } from "./cash-account";
import { TILLS_CACHE_TAGS } from "./tills-cache";

/**
 * Adds a euro till whose cash sits in the accounting chart, so the closing
 * count books its variance. The till maps an unused asset account named for
 * cash when the chart has one and otherwise creates a new one (see
 * `planCashAccount`).
 */
export const createTill = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.minLength(1), v.maxLength(100)),
    }),
    requireTenant: true,
    permission: "tills.manage",
  },
  async ({ name }, { tenant: organizationId, db, auth }) => {
    const settings = await db.accounting.settings(organizationId);

    if (!settings.ok) {
      return settings;
    }

    if (settings.data === undefined) {
      const setup = await db.accounting.setup({ organizationId });

      if (!setup.ok) {
        return setup;
      }
    }

    const [accounts, tills] = await Promise.all([
      db.accounting.accounts({ organizationId }),
      db.tills.listTills({ includeArchived: true }),
    ]);

    if (!accounts.ok) {
      return accounts;
    }

    if (!tills.ok) {
      return tills;
    }

    const plan = planCashAccount(
      accounts.data,
      new Set(tills.data.flatMap((till) => till.accountId ?? [])),
      name,
    );

    let accountId: string;

    if (plan.kind === "map") {
      accountId = plan.accountId;
    } else {
      const created = await db.accounting.saveAccount({
        organizationId,
        input: {
          code: plan.code,
          name: plan.name,
          type: "asset",
          currency: "EUR",
        },
      });

      if (!created.ok) {
        return created;
      }

      accountId = created.data.id;
    }

    const till = await db.tills.createTill({
      name,
      currency: "EUR",
      accountId,
    });

    if (!till.ok) {
      return till;
    }

    await refreshCaller(auth, TILLS_CACHE_TAGS);

    return ok({ id: till.data.id, accountId });
  },
);

const Currency = v.picklist(["EUR", "USD", "GBP"]);

/** Starts a shift on a till with its opening float. */
export const openSession = bsb.action(
  {
    input: v.object({
      tillId: Id,
      currency: Currency,
      openingFloat: Optional,
      notes: Optional,
    }),
    requireTenant: true,
    permission: "tills.write",
  },
  async (input, { db, auth }) => {
    const float = input.openingFloat;

    const opened = await db.tills.openSession({
      tillId: input.tillId,
      ...given(
        "openingFloat",
        float !== undefined && v.is(Decimal, float)
          ? parseMoney(float, input.currency)
          : undefined,
      ),
      ...given("notes", input.notes),
    });

    if (!opened.ok) {
      return opened;
    }

    await refreshCaller(auth, TILLS_CACHE_TAGS);

    return ok({ id: opened.data.id });
  },
);

/** Records cash that came in or went out of the drawer. */
export const recordMovement = bsb.action(
  {
    input: v.object({
      sessionId: Id,
      currency: Currency,
      kind: v.picklist(["cash_sale", "cash_refund", "cash_in", "cash_out"]),
      amount: Decimal,
      reason: Optional,
    }),
    requireTenant: true,
    permission: "tills.write",
  },
  async (input, { db, auth }) => {
    const recorded = await db.tills.recordMovement({
      sessionId: input.sessionId,
      kind: input.kind,
      amount: parseMoney(input.amount, input.currency),
      ...given("reason", input.reason),
    });

    if (!recorded.ok) {
      return recorded;
    }

    await refreshCaller(auth, TILLS_CACHE_TAGS);

    return ok(true);
  },
);

/** Counts the drawer and closes the session; the variance goes to the books. */
export const closeSession = bsb.action(
  {
    input: v.object({
      sessionId: Id,
      currency: Currency,
      counted: Decimal,
      notes: Optional,
    }),
    requireTenant: true,
    permission: "tills.write",
  },
  async (input, { db, auth }) => {
    const closed = await db.tills.closeSession({
      sessionId: input.sessionId,
      input: {
        amount: parseMoney(input.counted, input.currency),
        ...given("notes", input.notes),
      },
    });

    if (!closed.ok) {
      return closed;
    }

    await refreshCaller(auth, TILLS_CACHE_TAGS);

    return ok(true);
  },
);

/** Takes cash from a closed session to the bank. */
export const depositCash = bsb.action(
  {
    input: v.object({
      sessionId: Id,
      currency: Currency,
      amount: Decimal,
      reference: Optional,
    }),
    requireTenant: true,
    permission: "tills.manage",
  },
  async (input, { db, auth }) => {
    const deposited = await db.tills.deposit({
      sessionId: input.sessionId,
      input: {
        amount: parseMoney(input.amount, input.currency),
        ...given("reference", input.reference),
      },
    });

    if (!deposited.ok) {
      return deposited;
    }

    await refreshCaller(auth, TILLS_CACHE_TAGS);

    return ok(true);
  },
);

/**
 * Imports an MT940 statement into a bank account so a deposit has a transaction
 * to match. Importing the same file twice adds nothing (EX-1113).
 */
export const importDepositStatement = bsb.action(
  {
    input: v.object({
      accountId: Id,
      statement: v.pipe(v.string(), v.trim(), v.minLength(1)),
    }),
    requireTenant: true,
    permission: "banking.import",
  },
  async ({ accountId, statement }, { db, auth }) => {
    let parsed: ReturnType<typeof parseMt940>;

    try {
      parsed = parseMt940(statement);
    } catch (error) {
      return err(
        invalidInput("The statement is not MT940.", [
          {
            path: ["statement"],
            code: "STATEMENT_INVALID",
            message:
              error instanceof Error
                ? error.message
                : "Paste an MT940 customer statement.",
          },
        ]),
      );
    }

    let added = 0;

    for (const part of parsed) {
      const imported = await db.banking.importStatement({
        accountId,
        statement: part,
      });

      if (!imported.ok) {
        return imported;
      }

      added += imported.data.imported;
    }

    await refreshCaller(auth, [...TILLS_CACHE_TAGS, BANKING_TAG]);

    return ok({ imported: added });
  },
);

/** Matches a pending deposit to the bank transaction that shows it. */
export const reconcileDeposit = bsb.action(
  {
    input: v.object({ depositId: Id, bankTransactionId: Id }),
    requireTenant: true,
    permission: "tills.manage",
  },
  async (input, { db, auth }) => {
    const reconciled = await db.tills.reconcileDeposit(input);

    if (!reconciled.ok) {
      return reconciled;
    }

    await refreshCaller(auth, [...TILLS_CACHE_TAGS, BANKING_TAG]);

    return ok(true);
  },
);
