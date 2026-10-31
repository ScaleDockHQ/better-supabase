import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { TestUser } from "./block-session.ts";

import { createAccounting } from "../../src/blocks/accounting/index.ts";
import { createBanking, parseMt940 } from "../../src/blocks/banking/index.ts";
import { createInvoices } from "../../src/blocks/invoices/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "attachments",
  "approvals",
  "subjects",
  "relations",
  "contacts",
  "ledger",
  "catalog",
  "accounting",
  "invoices",
  "expenses",
  "banking",
];

const MT940 = `{1:F01ABNANL2AXXXX0000000000}{2:I940ABNANL2AXXXXN}{4:
:20:ABN-275
:25:NL91ABNA0417164300EUR
:28C:00275/1
:60F:C261001EUR1000,00
:61:2610011001C242,00NTRFNONREF//BANK-0001
:86:/TRTP/SEPA OVERBOEKING/IBAN/NL02RABO0123456789/BIC/RABONL2U/NAME/A
cme B.V./REMI/USTD//Consulting October/EREF/E2E-42
:61:261001D70,55NDDTNONREF
:86:/TRTP/SEPA Incasso/CSID/NL99ZZZ/NAME/Energy Co/REMI/USTD//Invoice 2
026-118/EREF/NOTPROVIDED
:61:261001C12,00NTRFREF-3
:86:166?00GUTSCHRIFT?20EREF+DE-1?21SVWZ+Rechnung 77?31DE89370400440532
013000?32Muster GmbH
:62F:C261001EUR1183,45
-}`;

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("banking module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let s: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let tenant: string;
  let accountId: string;
  let invoiceId: string;

  const banking = () =>
    createBanking({ transport: sqlTransport(s.sql), tenant });

  const events = async (type: string): Promise<Record<string, unknown>[]> =>
    (
      await s.rows<{ data: Record<string, unknown> }>(
        "select payload as data from better_supabase.outbox_events where organization_id = $1 and type = $2 order by position",
        [tenant, type],
      )
    ).map((row) => row.data);

  beforeAll(async () => {
    s = await BlockSession.open(pool);
    owner = await s.user("banking-owner");
    member = await s.user("banking-member");
    await s.install(MODULES, {
      subjects: withBlockSubjects({}, ["contacts"], {}),
    });
    tenant = await s.organization(owner, { member });
    await s.as(owner);

    const books = createAccounting({ transport: sqlTransport(s.sql) });
    await books.setup(tenant, { functionalCurrency: "EUR" }).orThrow();
    await books.openFiscalYear(tenant, 2026).orThrow();
  });

  afterAll(async () => {
    await s.close();
    await pool.end();
  });

  it("adds an account on the bank journal and imports a statement once", async () => {
    await s.as(owner);

    const books = createAccounting({ transport: sqlTransport(s.sql) });

    const journal = (await books.journals(tenant).orThrow()).find(
      (row) => row.code === "BNK",
    );

    expect(
      hint(
        await banking().saveAccount({
          name: "Main",
          iban: "NL92ABNA0417164300",
          currency: "EUR",
        }),
      ),
    ).toBe("BANK_ACCOUNT_INVALID");

    const account = await banking()
      .saveAccount({
        name: "Main",
        iban: "NL91 ABNA 0417 1643 00",
        currency: "EUR",
        journalId: journal!.id,
      })
      .orThrow();

    expect(account).toMatchObject({
      iban: "NL91ABNA0417164300",
      journalId: journal!.id,
    });
    accountId = account.id;

    const [statement] = parseMt940(MT940);

    const first = await banking()
      .importStatement(accountId, statement!)
      .orThrow();

    const again = await banking()
      .importStatement(accountId, statement!)
      .orThrow();

    expect([first.imported, first.skipped]).toEqual([3, 0]);
    expect([again.imported, again.skipped]).toEqual([0, 3]);
    expect(first.statement.closingBalance).toEqual(eur(118_345n));
    expect(await banking().statements(accountId).orThrow()).toHaveLength(1);
    expect(await events("bank_statement.imported")).toHaveLength(2);
  });

  it("suggests the open invoice and records its payment on a match", async () => {
    await s.as(owner);

    const invoices = createInvoices({ transport: sqlTransport(s.sql) });

    const draft = await invoices
      .create(tenant, { title: "Consulting" }, [
        { description: "Consulting", unitAmount: eur(24_200n) },
      ])
      .orThrow();

    invoiceId = (await invoices.issue(draft.id).orThrow()).id;

    const payment = (await banking().transactions(accountId).orThrow()).find(
      (row) => row.amount.amount === 24_200n,
    );

    expect(payment?.counterpartyIban).toBe("NL02RABO0123456789");

    const [best] = await banking().suggestMatches(payment!.id).orThrow();

    expect(best).toMatchObject({ targetType: "invoice", targetId: invoiceId });
    expect(best!.reasons).toContain("amount");
    expect(
      hint(
        await banking().match(payment!.id, [
          { targetType: "invoice", targetId: invoiceId, amount: eur(100n) },
        ]),
      ),
    ).toBe("BANK_TRANSACTION_MATCH_INVALID");

    const matched = await banking()
      .match(payment!.id, [{ targetType: "invoice", targetId: invoiceId }])
      .orThrow();

    expect(matched.status).toBe("matched");
    expect(matched.matches).toHaveLength(1);

    const [invoice] = await s.rows<{ status: string }>(
      "select status from better_supabase.invoices where id = $1",
      [invoiceId],
    );

    expect(invoice?.status).toBe("paid");
    expect(
      hint(
        await banking().match(payment!.id, [
          { targetType: "invoice", targetId: invoiceId },
        ]),
      ),
    ).toBe("BANK_TRANSACTION_STATUS_INVALID");
    expect((await events("bank_transaction.matched")).at(-1)).toMatchObject({
      id: payment!.id,
      status: "matched",
    });
  });

  it("books and sets aside transactions through rules, then reconciles", async () => {
    await s.as(owner);

    const books = createAccounting({ transport: sqlTransport(s.sql) });

    const expense = (await books.accounts(tenant).orThrow()).find(
      (row) => row.code === "6000",
    );

    await banking()
      .saveRule({
        name: "Energy",
        conditions: {
          id: "root",
          type: "group",
          combinator: "and",
          rules: [
            {
              id: "name",
              type: "rule",
              path: ["counterpartyName"],
              operator: "is",
              value: "Energy Co",
            },
          ],
        },
        accountId: expense!.id,
        priority: 10,
      })
      .orThrow();
    await banking()
      .saveRule({
        name: "Refunds",
        conditions: {
          id: "root",
          type: "group",
          combinator: "and",
          rules: [
            {
              id: "name",
              type: "rule",
              path: ["counterpartyName"],
              operator: "contains",
              value: "Muster",
            },
          ],
        },
      })
      .orThrow();

    expect(await banking().applyRules(accountId).orThrow()).toEqual({
      matched: 1,
      ignored: 1,
    });

    const status = await banking().reconciliation(accountId).orThrow();

    expect(status.unmatchedCount).toBe(0);
    expect(status.statementBalance).toEqual(eur(118_345n));
  });

  it("lets members reconcile but not manage accounts or rules", async () => {
    await s.as(member);
    expect(
      hint(await banking().saveAccount({ name: "Petty", currency: "EUR" })),
    ).toBe("BANKING_FORBIDDEN");
    expect(hint(await banking().saveRule({ name: "Mine" }))).toBe(
      "BANKING_FORBIDDEN",
    );

    const energy = (await banking().transactions(accountId).orThrow()).find(
      (row) => row.counterpartyName === "Energy Co",
    );

    const undone = await banking().unmatch(energy!.id).orThrow();

    expect(undone).toMatchObject({ status: "unmatched", matches: [] });

    await s.service();

    const [reversed] = await s.rows<{ count: number }>(
      `select count(*)::integer as count from better_supabase.accounting_entries r
       join better_supabase.accounting_entries e on e.id = r.reverses_id
       where e.tenant_id = $1 and e.source_type = 'bank_transaction' and e.source_id = $2`,
      [tenant, energy!.id],
    );

    expect(reversed?.count).toBe(1);
    await s.as(owner);
  });
});
