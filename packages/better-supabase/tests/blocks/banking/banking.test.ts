import { Temporal } from "temporal-polyfill";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { BankFeed } from "../../../src/blocks/banking/index.ts";
import type { FilterQuery } from "../../../src/list/filter-query.ts";

import {
  bankAccountInputSchema,
  bankFeedOf,
  bankingBlock,
  bankMatchInputSchema,
  bankRuleInputSchema,
  createBanking,
} from "../../../src/blocks/banking/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T10:00:00Z";

const ACCOUNT = {
  id: "a1",
  organizationId: "org-1",
  name: "Operating",
  iban: "NL91ABNA0417164300",
  bic: null,
  currency: "EUR",
  journalId: "j1",
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const STATEMENT = {
  id: "s1",
  organizationId: "org-1",
  accountId: "a1",
  reference: "STMT-1",
  fromOn: "2026-10-01",
  untilOn: "2026-10-01",
  openingBalance: "100000",
  closingBalance: "124200",
  currency: "EUR",
  format: "camt053",
  attachmentId: null,
  importedBy: "u1",
  createdAt: AT,
};

const TRANSACTION = {
  id: "t1",
  organizationId: "org-1",
  accountId: "a1",
  statementId: "s1",
  bookedOn: "2026-10-01",
  valueOn: "2026-10-02",
  amount: "24200",
  currency: "EUR",
  counterpartyName: "Acme B.V.",
  counterpartyIban: "NL02RABO0123456789",
  remittance: null,
  structuredReference: "RF73INV20260042",
  endToEndId: null,
  externalId: "BANK-0001",
  status: "matched",
  ruleId: null,
  matchedAt: AT,
  matchedBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  matches: [
    {
      id: "m1",
      transactionId: "t1",
      targetType: "invoice",
      targetId: "i1",
      amount: "24200",
      createdBy: "u1",
      createdAt: AT,
    },
  ],
};

const RULE = {
  id: "r1",
  organizationId: "org-1",
  name: "Bank fees",
  conditions: {
    id: "root",
    type: "group",
    combinator: "and",
    rules: [
      {
        id: "r",
        type: "rule",
        path: ["counterpartyName"],
        operator: "contains",
        value: "Bank",
      },
    ],
  } satisfies FilterQuery,
  accountId: "acc-fees",
  partyId: null,
  dimensions: { costCenter: "ops" },
  priority: 10,
  active: true,
  createdAt: AT,
  updatedAt: AT,
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createBanking", () => {
  it("reads and writes the extra columns through fields", async () => {
    const Fields = v.object({
      ledger_code: v.pipe(v.string(), v.minLength(2)),
    });

    const t = fieldsTransport({
      save_bank_account: () => ({
        ...ACCOUNT,
        fields: { ledger_code: "1100" },
      }),
      list_bank_accounts: () => [{ ...ACCOUNT, fields: { ledger_code: "x" } }],
    });

    const banking = createBanking({
      transport: t,
      tenant: "org-1",
      fields: Fields,
    });

    const saved = await banking
      .saveAccount({ name: "Operating", fields: { ledger_code: "1100" } })
      .orThrow();

    expect(saved.fields.ledger_code).toBe("1100");
    expect(t.calls[0]?.[1]).toMatchObject({
      input: { fields: { ledger_code: "1100" } },
    });
    expect(
      (await banking.saveAccount({ fields: { ledger_code: "1" } })).ok,
    ).toBe(false);
    expect(t.calls).toHaveLength(1);
    expect((await banking.accounts()).ok).toBe(false);
  });

  it("saves and lists bank accounts", async () => {
    const t = fieldsTransport({
      save_bank_account: () => ACCOUNT,
      list_bank_accounts: () => [
        { ...ACCOUNT, archivedAt: AT, bic: "ABNANL2A" },
      ],
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    const saved = await banking
      .saveAccount({
        name: "Operating",
        iban: "NL91 ABNA 0417 1643 00",
        currency: "EUR",
      })
      .orThrow();

    expect(saved).toMatchObject({
      id: "a1",
      iban: "NL91ABNA0417164300",
      journalId: "j1",
    });
    expect(saved).not.toHaveProperty("bic");

    const [archived] = await banking
      .accounts({ includeArchived: true })
      .orThrow();

    expect(archived?.bic).toBe("ABNANL2A");
    expect(archived?.archivedAt?.toString()).toBe(AT);
    expect(t.calls).toEqual([
      [
        "save_bank_account",
        {
          tenant: "org-1",
          input: {
            name: "Operating",
            iban: "NL91 ABNA 0417 1643 00",
            currency: "EUR",
          },
          account_id: null,
        },
      ],
      ["list_bank_accounts", { tenant: "org-1", include_archived: true }],
    ]);
  });

  it("imports statements with money in minor units and plain dates", async () => {
    const t = fieldsTransport({
      import_bank_statement: () => ({
        statement: STATEMENT,
        imported: 1,
        skipped: 0,
      }),
      list_bank_statements: () => [STATEMENT],
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    const result = await banking
      .importStatement("a1", {
        reference: "STMT-1",
        fromOn: temporal().PlainDate.from("2026-10-01"),
        untilOn: "2026-10-01",
        openingBalance: money(100_000n, "EUR"),
        closingBalance: money(124_200n, "EUR"),
        format: "camt053",
        transactions: [
          {
            externalId: "BANK-0001",
            bookedOn: "2026-10-01",
            amount: money(24_200n, "EUR"),
            structuredReference: "RF73INV20260042",
          },
        ],
      })
      .orThrow();

    expect(result.imported).toBe(1);
    expect(result.statement.closingBalance).toEqual(money(124_200n, "EUR"));
    expect(result.statement.fromOn?.toString()).toBe("2026-10-01");
    expect(t.calls[0]).toEqual([
      "import_bank_statement",
      {
        account_id: "a1",
        statement: {
          reference: "STMT-1",
          fromOn: "2026-10-01",
          untilOn: "2026-10-01",
          openingBalance: "100000",
          closingBalance: "124200",
          format: "camt053",
          transactions: [
            {
              externalId: "BANK-0001",
              bookedOn: "2026-10-01",
              amount: "24200",
              currency: "EUR",
              structuredReference: "RF73INV20260042",
            },
          ],
        },
      },
    ]);

    const [listed] = await banking.statements("a1").orThrow();

    expect(listed?.format).toBe("camt053");
    expect(listed?.importedBy).toBe("u1");
  });

  it("reads, matches, unmatches and ignores transactions", async () => {
    const unmatched = {
      ...TRANSACTION,
      status: "unmatched",
      matches: [],
      matchedAt: null,
      matchedBy: null,
    };

    const t = fieldsTransport({
      list_bank_transactions: () => [unmatched],
      get_bank_transaction: (args) =>
        args["transaction_id"] === "t1" ? TRANSACTION : null,
      suggest_bank_matches: () => [
        {
          targetType: "invoice",
          targetId: "i1",
          label: "INV-2026-0042",
          balance: "24200",
          currency: "EUR",
          score: 150,
          reasons: ["reference", "amount", "counterparty"],
        },
      ],
      match_bank_transaction: () => TRANSACTION,
      unmatch_bank_transaction: () => unmatched,
      ignore_bank_transaction: () => ({ ...unmatched, status: "ignored" }),
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    const [listed] = await banking
      .transactions("a1", {
        status: "unmatched",
        since: "2026-10-01",
        limit: 50,
      })
      .orThrow();

    expect(listed?.amount).toEqual(money(24_200n, "EUR"));
    expect(listed?.valueOn?.toString()).toBe("2026-10-02");
    expect(listed?.matches).toEqual([]);

    const found = await banking.getTransaction("t1").orThrow();

    expect(found?.matches[0]).toMatchObject({
      targetType: "invoice",
      amount: money(24_200n, "EUR"),
    });
    expect(await banking.getTransaction("t2").orThrow()).toBeUndefined();

    const [suggestion] = await banking.suggestMatches("t1").orThrow();

    expect(suggestion).toEqual({
      targetType: "invoice",
      targetId: "i1",
      label: "INV-2026-0042",
      balance: money(24_200n, "EUR"),
      score: 150,
      reasons: ["reference", "amount", "counterparty"],
    });

    const matched = await banking
      .match("t1", [
        {
          targetType: "invoice",
          targetId: "i1",
          amount: money(24_200n, "EUR"),
        },
        { targetType: "accounting_entry", targetId: "e1" },
      ])
      .orThrow();

    expect(matched.status).toBe("matched");
    expect((await banking.unmatch("t1").orThrow()).status).toBe("unmatched");
    expect((await banking.ignore("t1").orThrow()).status).toBe("ignored");

    expect(t.calls).toContainEqual([
      "list_bank_transactions",
      {
        account_id: "a1",
        filter: { status: "unmatched", since: "2026-10-01", limit: 50 },
      },
    ]);
    expect(t.calls).toContainEqual([
      "match_bank_transaction",
      {
        transaction_id: "t1",
        matches: [
          { targetType: "invoice", targetId: "i1", amount: "24200" },
          { targetType: "accounting_entry", targetId: "e1" },
        ],
      },
    ]);
    expect(t.calls).toContainEqual([
      "ignore_bank_transaction",
      { transaction_id: "t1", ignored: true },
    ]);
  });

  it("saves, lists, applies and deletes bank rules", async () => {
    const t = fieldsTransport({
      save_bank_rule: () => RULE,
      list_bank_rules: () => [{ ...RULE, accountId: null, dimensions: null }],
      apply_bank_rules: () => ({ matched: 2, ignored: 1 }),
      delete_bank_rule: () => null,
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    const rule = await banking
      .saveRule({
        name: "Bank fees",
        conditions: RULE.conditions,
        accountId: "acc-fees",
      })
      .orThrow();

    expect(rule.dimensions).toEqual({ costCenter: "ops" });
    expect(rule.conditions).toEqual(RULE.conditions);

    const [listed] = await banking.rules().orThrow();

    expect(listed).not.toHaveProperty("accountId");
    expect(listed?.dimensions).toEqual({});
    expect(await banking.applyRules("a1").orThrow()).toEqual({
      matched: 2,
      ignored: 1,
    });
    expect((await banking.deleteRule("r1")).ok).toBe(true);
  });

  it("refuses a bank rule row without a filter tree", async () => {
    const t = fieldsTransport({
      list_bank_rules: () => [{ ...RULE, conditions: {} }],
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    expect((await banking.rules()).ok).toBe(false);
  });

  it("reads the reconciliation status", async () => {
    const t = fieldsTransport({
      bank_reconciliation_status: () => ({
        accountId: "a1",
        asOf: "2026-10-31",
        currency: "EUR",
        statementId: "s1",
        statementBalance: "124200",
        transactionTotal: "24200",
        unmatchedCount: 0,
        unmatchedTotal: "0",
        ledgerBalance: "124200",
        difference: "0",
        reconciled: true,
      }),
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    const status = await banking.reconciliation("a1", "2026-10-31").orThrow();

    expect(status).toMatchObject({
      reconciled: true,
      statementBalance: money(124_200n, "EUR"),
      difference: money(0n, "EUR"),
      unmatchedCount: 0,
    });
    expect(status.asOf.toString()).toBe("2026-10-31");
    expect(t.calls[0]).toEqual([
      "bank_reconciliation_status",
      { account_id: "a1", as_of: "2026-10-31" },
    ]);
  });

  it("syncs a bank feed through importStatement", async () => {
    const t = fieldsTransport({
      import_bank_statement: () => ({
        statement: {
          ...STATEMENT,
          format: "feed",
          reference: "test:acc-9:2026-10-01",
        },
        imported: 1,
        skipped: 0,
      }),
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    const feed: BankFeed = {
      apiVersion: 1,
      name: "test",
      listAccounts: () => AsyncResult.ok([{ ref: "acc-9", currency: "EUR" }]),
      transactions: () =>
        AsyncResult.ok([
          {
            externalId: "f1",
            bookedOn: "2026-10-02",
            amount: money(-500n, "EUR"),
          },
        ]),
    };

    const result = await banking
      .syncFeed("a1", feed, { accountRef: "acc-9", since: "2026-10-01" })
      .orThrow();

    expect(result.statement.format).toBe("feed");
    expect(t.calls[0]?.[1]).toEqual({
      account_id: "a1",
      statement: {
        reference: "test:acc-9:2026-10-01",
        fromOn: "2026-10-01",
        format: "feed",
        transactions: [
          {
            externalId: "f1",
            bookedOn: "2026-10-02",
            amount: "-500",
            currency: "EUR",
          },
        ],
      },
    });
  });

  it("refuses a bank feed for another API version", () => {
    expect(() =>
      // SAFETY: a feed written for a later API, which the check exists to catch.
      bankFeedOf({ apiVersion: 2, name: "next" } as unknown as BankFeed),
    ).toThrow("targets bank feed API 2");
  });
});

const BATCH = {
  id: "b1",
  organizationId: "org-1",
  accountId: "a1",
  reference: "Run 31 Oct",
  messageId: "BATCH-1",
  dueBy: "2026-11-05",
  executionOn: "2026-11-02",
  currency: "EUR",
  total: "9800",
  itemCount: 1,
  status: "draft",
  createdAt: AT,
  items: [
    {
      id: "bi1",
      invoiceId: "i1",
      partyId: "c1",
      creditorName: "Bakker",
      creditorIban: "NL02ABNA0123456789",
      amount: "9800",
      discount: "200",
      endToEndId: "BILL-1",
      status: "open",
    },
  ],
};

describe("payment batches", () => {
  it("creates a batch and exports it as a SEPA file", async () => {
    const t = fieldsTransport({
      create_payment_batch: () => BATCH,
      get_payment_batch: () => BATCH,
      list_bank_accounts: () => [ACCOUNT],
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    const batch = await banking
      .createPaymentBatch({
        accountId: "a1",
        dueBy: Temporal.PlainDate.from("2026-11-05"),
        creditors: { c1: { name: "Bakker", iban: "NL02ABNA0123456789" } },
      })
      .orThrow();

    expect(batch.total).toEqual(money(9800n, "EUR"));
    expect(batch.items[0]?.discount).toEqual(money(200n, "EUR"));

    const xml = await banking.exportSepaCreditTransfer("b1").orThrow();

    expect(xml).toContain("<MsgId>BATCH-1</MsgId>");
    expect(xml).toContain('<InstdAmt Ccy="EUR">98.00</InstdAmt>');
  });

  it("lists, posts and cancels batches and passes every option", async () => {
    const t = fieldsTransport({
      create_payment_batch: () => BATCH,
      list_payment_batches: () => [BATCH],
      post_payment_batch: () => ({ ...BATCH, status: "posted" }),
      cancel_payment_batch: () => ({ ...BATCH, status: "cancelled" }),
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    await banking
      .createPaymentBatch({
        accountId: "a1",
        dueBy: Temporal.PlainDate.from("2026-11-05"),
        executionOn: Temporal.PlainDate.from("2026-11-02"),
        reference: "Run",
        invoiceIds: ["i1"],
        creditors: { c1: { name: "Bakker", iban: "NL02ABNA0123456789" } },
      })
      .orThrow();
    expect(t.calls[0]?.[1]).toMatchObject({
      input: {
        executionOn: "2026-11-02",
        reference: "Run",
        invoiceIds: ["i1"],
      },
    });
    expect(await banking.paymentBatches().orThrow()).toHaveLength(1);
    expect(
      await banking.paymentBatches({ status: "posted", limit: 5 }).orThrow(),
    ).toHaveLength(1);
    expect((await banking.postPaymentBatch("b1").orThrow()).status).toBe(
      "posted",
    );
    expect((await banking.cancelPaymentBatch("b1").orThrow()).status).toBe(
      "cancelled",
    );
  });

  it("reads every optional batch field and writes them to the file", async () => {
    const full = {
      ...BATCH,
      transactionId: "t1",
      createdBy: "u1",
      postedAt: AT,
      reconciledAt: AT,
      status: "reconciled",
      items: [
        {
          ...BATCH.items[0]!,
          creditorBic: "COBADEFFXXX",
          remittance: "Invoice 1",
          status: "paid",
        },
        {
          ...BATCH.items[0]!,
          id: "bi2",
          endToEndId: "BILL-2",
          status: "cancelled",
        },
      ],
    };

    const t = fieldsTransport({
      get_payment_batch: () => full,
      list_bank_accounts: () => [{ ...ACCOUNT, bic: "ABNANL2A" }],
    });

    const banking = createBanking({ transport: t, tenant: "org-1" });

    const batch = await banking.getPaymentBatch("b1").orThrow();

    expect(batch.transactionId).toBe("t1");
    expect(batch.createdBy).toBe("u1");
    expect(batch.postedAt).toBeDefined();
    expect(batch.reconciledAt).toBeDefined();
    expect(batch.items[0]?.creditorBic).toBe("COBADEFFXXX");

    const xml = await banking
      .exportSepaCreditTransfer("b1", {
        debtorName: "Acme",
        initiatingPartyName: "Acme Treasury",
      })
      .orThrow();

    expect(xml).toContain("<Nm>Acme Treasury</Nm>");
    expect(xml).toContain("<BICFI>ABNANL2A</BICFI>");
    expect(xml).toContain("<Ustrd>Invoice 1</Ustrd>");
    expect(xml).not.toContain("BILL-2");
  });

  it("refuses an export when the bank account has no IBAN", async () => {
    const t = fieldsTransport({
      get_payment_batch: () => BATCH,
      list_bank_accounts: () => [{ ...ACCOUNT, iban: null }],
    });

    const result = await createBanking({
      transport: t,
      tenant: "org-1",
    }).exportSepaCreditTransfer("b1");

    expect(result.ok).toBe(false);
  });

  it("returns an error, not an exception, when the file is refused", async () => {
    const t = fieldsTransport({
      get_payment_batch: () => ({ ...BATCH, currency: "USD" }),
      list_bank_accounts: () => [ACCOUNT],
    });

    const result = await createBanking({
      transport: t,
      tenant: "org-1",
    }).exportSepaCreditTransfer("b1");

    expect(result.ok).toBe(false);
  });
});

describe("bankingBlock", () => {
  it("describes the block and validates its inputs", () => {
    expect(bankingBlock.name).toBe("banking");
    expect(bankingBlock.category).toBe("commerce");
    expect(bankingBlock.events.types).toEqual([
      "bank_statement.imported",
      "bank_transaction.matched",
      "bank_transaction.unmatched",
    ]);
    expect(
      validate(bankAccountInputSchema, { name: "Operating", currency: "EUR" })
        .issues,
    ).toBeUndefined();
    expect(
      validate(bankAccountInputSchema, { currency: "EURO" }).issues,
    ).toBeDefined();
    expect(
      validate(bankMatchInputSchema, {
        targetType: "invoice",
        targetId: "8f9c0f8e-9a8b-4e3b-9a51-7cf0b0d3c111",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(bankMatchInputSchema, { targetType: "order", targetId: "x" })
        .issues,
    ).toBeDefined();
    expect(
      validate(bankRuleInputSchema, { priority: 1.5 }).issues,
    ).toBeDefined();
  });
});
