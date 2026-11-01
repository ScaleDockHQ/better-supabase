import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createAccounting } from "../../src/blocks/accounting/index.ts";
import { createBanking } from "../../src/blocks/banking/index.ts";
import { createTills } from "../../src/blocks/tills/index.ts";
import { money } from "../../src/commerce/money.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "subjects",
  "ledger",
  "tax",
  "accounting",
  "banking",
  "tills",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("tills", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("runs a shift from the float to a reconciled deposit", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("cashier");
      await s.install(MODULES, {});
      const org = await s.organization(owner);
      const transport = sqlTransport(s.sql);
      const books = createAccounting({ transport });
      const banking = createBanking({ transport, tenant: org });
      const tills = createTills({ transport, tenant: org });

      await s.as(owner);
      await books
        .setup({ organizationId: org, input: { functionalCurrency: "EUR" } })
        .orThrow();
      await books
        .openFiscalYear({ organizationId: org, fiscalYear: 2026 })
        .orThrow();

      const accounts = await books.accounts({ organizationId: org }).orThrow();
      const cash = accounts.find((row) => row.code === "1200")!;
      const bankAccount = accounts.find((row) => row.code !== "1200")!;
      await books
        .setAccountRole({
          organizationId: org,
          role: "bank",
          accountId: bankAccount.id,
        })
        .orThrow();

      const till = await tills
        .createTill({ name: "Front", currency: "EUR", accountId: cash.id })
        .orThrow();

      const session = await tills
        .openSession({ tillId: till.id, openingFloat: eur(10_000n) })
        .orThrow();

      expect(hint(await tills.openSession({ tillId: till.id }))).toBe(
        "TILL_STATUS",
      );

      await tills
        .recordMovement({
          sessionId: session.id,
          kind: "cash_sale",
          amount: eur(25_000n),
        })
        .orThrow();
      await tills
        .recordMovement({
          sessionId: session.id,
          kind: "cash_refund",
          amount: eur(2000n),
        })
        .orThrow();

      expect(
        hint(
          await tills.recordMovement({
            sessionId: session.id,
            kind: "cash_out",
            amount: eur(99_999_999n),
          }),
        ),
      ).toBe("TILL_INVALID");

      const closed = await tills
        .closeSession({
          sessionId: session.id,
          input: { denominations: { "5000": 6, "1000": 2 } },
        })
        .orThrow();

      expect(closed.count).toMatchObject({
        expected: eur(33_000n),
        counted: eur(32_000n),
        variance: eur(-1000n),
      });
      expect(closed.count?.entryId).toBeDefined();

      const deposit = await tills
        .deposit({
          sessionId: session.id,
          input: { amount: eur(32_000n), reference: "Bag 1" },
        })
        .orThrow();

      expect(deposit.status).toBe("pending");

      const bank = await banking
        .saveAccount({
          input: {
            name: "Till bank",
            iban: "NL91 ABNA 0417 1643 00",
            currency: "EUR",
          },
        })
        .orThrow();

      await banking
        .importStatement({
          accountId: bank.id,
          statement: {
            transactions: [
              {
                externalId: "DEP-1",
                bookedOn: "2026-10-31",
                amount: eur(32_000n),
                remittance: "Cash deposit",
              },
            ],
          },
        })
        .orThrow();

      const [tx] = await banking.transactions({ accountId: bank.id }).orThrow();

      const reconciled = await tills
        .reconcileDeposit({ depositId: deposit.id, bankTransactionId: tx!.id })
        .orThrow();

      expect(reconciled).toMatchObject({
        status: "reconciled",
        bankTransactionId: tx!.id,
      });
      expect(
        hint(
          await tills.reconcileDeposit({
            depositId: deposit.id,
            bankTransactionId: tx!.id,
          }),
        ),
      ).toBe("TILL_STATUS");
    } finally {
      await s.close();
    }
  });
});
