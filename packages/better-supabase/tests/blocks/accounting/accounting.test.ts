import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  accountingAccountInputSchema,
  accountingBlock,
  accountingEntryInputSchema,
  accountingJournalInputSchema,
  createAccounting,
} from "../../../src/blocks/accounting/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";
const ID = "00000000-0000-4000-8000-000000000001";

const SETTINGS = {
  organizationId: "org-1",
  functionalCurrency: "EUR",
  fiscalYearStartMonth: 1,
  lockDate: "2026-03-31",
  createdAt: AT,
  updatedAt: AT,
};

const ACCOUNT = {
  id: "a1",
  organizationId: "org-1",
  code: "1300",
  name: "Accounts receivable",
  type: "asset",
  subtype: "receivable",
  parentId: "a0",
  currency: "EUR",
  reconcilable: true,
  normalSide: "debit",
  level: 2,
  active: true,
  roles: ["receivable"],
  createdAt: AT,
  updatedAt: AT,
};

const BARE_ACCOUNT = {
  id: "a2",
  organizationId: "org-1",
  code: "8000",
  name: "Revenue",
  type: "income",
  reconcilable: false,
  normalSide: "credit",
  level: 1,
  active: false,
  createdAt: AT,
  updatedAt: AT,
  archivedAt: AT,
};

const JOURNAL = {
  id: "j1",
  organizationId: "org-1",
  code: "SAL",
  name: "Sales",
  type: "sales",
  defaultAccountId: "a2",
  currency: "EUR",
  createdAt: AT,
  updatedAt: AT,
};

const PERIOD = {
  id: "p1",
  organizationId: "org-1",
  fiscalYear: 2026,
  number: 1,
  startsOn: "2026-01-01",
  endsOn: "2026-01-31",
  status: "closed",
  closedAt: AT,
  closedBy: "u1",
};

const LINE = {
  id: "l1",
  accountId: "a1",
  accountCode: "1300",
  accountName: "Accounts receivable",
  debit: "12100",
  credit: "0",
  currency: "USD",
  amountCurrency: "13000",
  fxRate: "0.930769",
  taxCodeId: "t1",
  partyId: "c1",
  dimensions: { project: "apollo", region: 3 },
  description: "Invoice 42",
};

const BARE_LINE = {
  id: "l2",
  accountId: "a2",
  accountCode: "8000",
  accountName: "Revenue",
  debit: "0",
  credit: "12100",
  currency: "EUR",
  amountCurrency: "-12100",
  dimensions: null,
};

const ENTRY = {
  id: "e1",
  organizationId: "org-1",
  journalId: "j1",
  number: "SAL-2026-00001",
  fiscalYear: 2026,
  periodId: "p1",
  entryDate: "2026-01-15",
  reference: "INV-42",
  memo: "Invoice 42",
  sourceType: "invoice",
  sourceId: "i1",
  status: "posted",
  total: "12100",
  postedAt: AT,
  postedBy: "u1",
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  lines: [LINE, BARE_LINE],
  fields: { channel: "web" },
};

const DRAFT = {
  id: "e2",
  organizationId: "org-1",
  journalId: "j1",
  entryDate: "2026-01-16",
  status: "draft",
  total: "500",
  createdAt: AT,
  updatedAt: AT,
};

const Fields = v.object({ channel: v.picklist(["web", "shop"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createAccounting", () => {
  it("sets up the books and reads the settings", async () => {
    const t = fieldsTransport({
      setup_accounting: () => SETTINGS,
      get_accounting_settings: (args) =>
        args["tenant"] === "org-1" ? SETTINGS : null,
      set_accounting_lock_date: () => ({ ...SETTINGS, lockDate: null }),
    });

    const books = createAccounting({ transport: t });

    const settings = await books
      .setup({
        organizationId: "org-1",
        input: { functionalCurrency: "EUR", fiscalYearStartMonth: 4 },
      })
      .orThrow();

    await books.setup({ organizationId: "org-1" }).orThrow();

    const missing = await books.settings("org-2").orThrow();

    const cleared = await books
      .setLockDate({ organizationId: "org-1", lockDate: null })
      .orThrow();

    await books
      .setLockDate({
        organizationId: "org-1",
        lockDate: Temporal.PlainDate.from("2026-03-31"),
      })
      .orThrow();

    expect(settings.lockDate?.toString()).toBe("2026-03-31");
    expect(missing).toBeUndefined();
    expect(cleared).not.toHaveProperty("lockDate");
    expect(t.calls).toEqual([
      [
        "setup_accounting",
        {
          tenant: "org-1",
          functional_currency: "EUR",
          fiscal_year_start_month: 4,
        },
      ],
      [
        "setup_accounting",
        {
          tenant: "org-1",
          functional_currency: null,
          fiscal_year_start_month: null,
        },
      ],
      ["get_accounting_settings", { tenant: "org-2" }],
      ["set_accounting_lock_date", { tenant: "org-1", lock_date: null }],
      [
        "set_accounting_lock_date",
        { tenant: "org-1", lock_date: "2026-03-31" },
      ],
    ]);
  });

  it("saves, archives and lists accounts and their roles", async () => {
    const t = fieldsTransport({
      save_accounting_account: () => ACCOUNT,
      archive_accounting_account: () => BARE_ACCOUNT,
      set_accounting_account_role: () => ({ receivable: "a1", bank: "a3" }),
      list_accounting_accounts: () => [ACCOUNT, BARE_ACCOUNT],
    });

    const books = createAccounting({ transport: t });

    const saved = await books
      .saveAccount({
        organizationId: "org-1",
        input: {
          code: "1300",
          name: "Accounts receivable",
          type: "asset",
          subtype: "receivable",
          parentId: "a0",
          currency: "EUR",
          reconcilable: true,
          accountId: "a1",
        },
      })
      .orThrow();

    await books
      .saveAccount({
        organizationId: "org-1",
        input: { code: "8000", name: "Revenue", type: "income" },
      })
      .orThrow();

    const archived = await books.archiveAccount({ accountId: "a2" }).orThrow();

    await books.archiveAccount({ accountId: "a2", archived: false }).orThrow();

    const roles = await books
      .setAccountRole({
        organizationId: "org-1",
        role: "receivable",
        accountId: "a1",
      })
      .orThrow();

    const listed = await books.accounts({ organizationId: "org-1" }).orThrow();

    await books
      .accounts({ organizationId: "org-1", includeArchived: true })
      .orThrow();

    expect(saved).toMatchObject({ roles: ["receivable"], reconcilable: true });
    expect(archived.archivedAt?.toString()).toBe("2026-10-22T10:00:00Z");
    expect(archived.roles).toEqual([]);
    expect(archived).not.toHaveProperty("subtype");
    expect(roles).toEqual({ receivable: "a1", bank: "a3" });
    expect(listed).toHaveLength(2);
    expect(t.calls).toEqual([
      [
        "save_accounting_account",
        {
          tenant: "org-1",
          code: "1300",
          name: "Accounts receivable",
          type: "asset",
          subtype: "receivable",
          parent_id: "a0",
          currency: "EUR",
          reconcilable: true,
          account_id: "a1",
          normal_side: null,
          default_tax_code_id: null,
          active: null,
        },
      ],
      [
        "save_accounting_account",
        {
          tenant: "org-1",
          code: "8000",
          name: "Revenue",
          type: "income",
          subtype: null,
          parent_id: null,
          currency: null,
          reconcilable: null,
          account_id: null,
          normal_side: null,
          default_tax_code_id: null,
          active: null,
        },
      ],
      ["archive_accounting_account", { account_id: "a2", archived: true }],
      ["archive_accounting_account", { account_id: "a2", archived: false }],
      [
        "set_accounting_account_role",
        { tenant: "org-1", role: "receivable", account_id: "a1" },
      ],
      [
        "list_accounting_accounts",
        { tenant: "org-1", include_archived: false },
      ],
      ["list_accounting_accounts", { tenant: "org-1", include_archived: true }],
    ]);
  });

  it("refuses an account type it does not know", async () => {
    const t = fieldsTransport({
      list_accounting_accounts: () => [{ ...ACCOUNT, type: "other" }],
    });

    const listed = await createAccounting({ transport: t }).accounts({
      organizationId: "org-1",
    });

    expect(listed.ok).toBe(false);
  });

  it("saves journals, fiscal years and periods", async () => {
    const t = fieldsTransport({
      save_accounting_journal: () => JOURNAL,
      list_accounting_journals: () => [JOURNAL],
      open_fiscal_year: () => [PERIOD],
      list_accounting_periods: () => [{ ...PERIOD, status: "open" }],
    });

    const books = createAccounting({ transport: t });

    await books
      .saveJournal({
        organizationId: "org-1",
        input: {
          code: "SAL",
          name: "Sales",
          type: "sales",
          defaultAccountId: "a2",
          currency: "EUR",
          journalId: "j1",
        },
      })
      .orThrow();
    await books
      .saveJournal({
        organizationId: "org-1",
        input: { code: "GEN", name: "General", type: "general" },
      })
      .orThrow();

    const journals = await books.journals("org-1").orThrow();

    const [opened] = await books
      .openFiscalYear({ organizationId: "org-1", fiscalYear: 2026 })
      .orThrow();

    const [listed] = await books.periods({ organizationId: "org-1" }).orThrow();

    await books
      .periods({ organizationId: "org-1", fiscalYear: 2026 })
      .orThrow();

    expect(journals[0]).toMatchObject({ code: "SAL", defaultAccountId: "a2" });
    expect(opened?.startsOn.toString()).toBe("2026-01-01");
    expect(opened?.closedBy).toBe("u1");
    expect(listed?.status).toBe("open");
    expect(t.calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "save_accounting_journal",
        {
          tenant: "org-1",
          code: "SAL",
          name: "Sales",
          type: "sales",
          default_account_id: "a2",
          currency: "EUR",
          journal_id: "j1",
          contra_account_id: null,
          bank_account_id: null,
        },
      ],
      [
        "save_accounting_journal",
        {
          tenant: "org-1",
          code: "GEN",
          name: "General",
          type: "general",
          default_account_id: null,
          currency: null,
          journal_id: null,
          contra_account_id: null,
          bank_account_id: null,
        },
      ],
      ["list_accounting_journals", { tenant: "org-1" }],
      ["open_fiscal_year", { tenant: "org-1", fiscal_year: 2026 }],
      ["list_accounting_periods", { tenant: "org-1", fiscal_year: null }],
      ["list_accounting_periods", { tenant: "org-1", fiscal_year: 2026 }],
    ]);
  });

  it("saves dimensions and exchange rates", async () => {
    const DIMENSION = {
      id: "d1",
      organizationId: "org-1",
      key: "project",
      name: "Project",
      values: [
        { id: "v1", code: "apollo", name: "Apollo" },
        { id: "v2", code: "gemini", name: "Gemini", archivedAt: AT },
      ],
      createdAt: AT,
    };

    const t = fieldsTransport({
      save_accounting_dimension: () => ({ ...DIMENSION, values: null }),
      save_accounting_dimension_value: () => DIMENSION,
      list_accounting_dimensions: () => [DIMENSION],
      set_accounting_fx_rate: () => ({
        organizationId: "org-1",
        base: "USD",
        quote: "EUR",
        onDate: "2026-01-15",
        rate: "0.930769",
      }),
      accounting_fx_rate: () => 0.93,
    });

    const books = createAccounting({ transport: t });
    const on = Temporal.PlainDate.from("2026-01-15");

    const dimension = await books
      .saveDimension({
        organizationId: "org-1",
        key: "project",
        name: "Project",
      })
      .orThrow();

    await books
      .saveDimensionValue({
        dimensionId: "d1",
        input: { code: "apollo", name: "Apollo" },
      })
      .orThrow();
    await books
      .saveDimensionValue({
        dimensionId: "d1",
        input: { code: "gemini", name: "Gemini", archived: true },
      })
      .orThrow();

    const [listed] = await books.dimensions("org-1").orThrow();

    const rate = await books
      .setFxRate({
        organizationId: "org-1",
        input: { base: "USD", quote: "EUR", onDate: on, rate: "0.930769" },
      })
      .orThrow();

    const looked = await books
      .fxRate({
        organizationId: "org-1",
        base: "USD",
        quote: "EUR",
        onDate: on,
      })
      .orThrow();

    expect(dimension.values).toEqual([]);
    expect(listed?.values[1]?.archivedAt?.toString()).toBe(
      "2026-10-22T10:00:00Z",
    );
    expect(rate.rate).toBe("0.930769");
    expect(rate.onDate.toString()).toBe("2026-01-15");
    expect(looked).toBe("0.93");
    expect(t.calls).toContainEqual([
      "save_accounting_dimension_value",
      { dimension_id: "d1", code: "apollo", name: "Apollo", archived: false },
    ]);
    expect(t.calls).toContainEqual([
      "accounting_fx_rate",
      { tenant: "org-1", base: "USD", quote: "EUR", on_date: "2026-01-15" },
    ]);
  });

  it("saves an entry with its lines and extra fields", async () => {
    const t = fieldsTransport({ save_accounting_entry: () => ENTRY });
    const books = createAccounting({ transport: t, fields: Fields });

    const saved = await books
      .saveEntry({
        journalId: "j1",
        entryDate: Temporal.PlainDate.from("2026-01-15"),
        lines: [
          {
            accountCode: "1300",
            debit: money(12_100n, "EUR"),
            amountCurrency: money(13_000n, "USD"),
            fxRate: "0.930769",
            taxCodeId: "t1",
            partyId: "c1",
            dimensions: { project: "apollo" },
            description: "Invoice 42",
          },
          { accountId: "a2", credit: 12_100n },
          { accountId: "a3", credit: money(0n, "EUR") },
        ],
        memo: "Invoice 42",
        reference: "INV-42",
        sourceType: "invoice",
        sourceId: "i1",
        entryId: ID,
        fields: { channel: "web" },
      })
      .orThrow();

    const refused = await books.saveEntry({
      journalId: "j1",
      entryDate: Temporal.PlainDate.from("2026-01-15"),
      lines: [],
      // SAFETY: a value the schema refuses, to prove the client checks it.
      fields: { channel: "fax" } as unknown as { channel: "web" },
    });

    expect(saved).toMatchObject({
      number: "SAL-2026-00001",
      status: "posted",
      total: 12_100n,
      fields: { channel: "web" },
    });
    expect(saved.lines?.[0]).toMatchObject({
      debit: 12_100n,
      credit: 0n,
      amountCurrency: 13_000n,
      fxRate: "0.930769",
      dimensions: { project: "apollo" },
    });
    expect(saved.lines?.[1]).toMatchObject({
      amountCurrency: -12_100n,
      dimensions: {},
    });
    expect(saved.lines?.[1]).not.toHaveProperty("fxRate");
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(t.calls).toEqual([
      [
        "save_accounting_entry",
        {
          journal_id: "j1",
          entry_date: "2026-01-15",
          lines: [
            {
              accountCode: "1300",
              debit: "12100",
              currency: "USD",
              amountCurrency: "13000",
              fxRate: "0.930769",
              taxCodeId: "t1",
              partyId: "c1",
              dimensions: { project: "apollo" },
              description: "Invoice 42",
            },
            { accountId: "a2", credit: "12100" },
            { accountId: "a3", credit: "0", currency: "EUR" },
          ],
          memo: "Invoice 42",
          reference: "INV-42",
          source_type: "invoice",
          source_id: "i1",
          entry_id: ID,
          fields: { channel: "web" },
        },
      ],
    ]);
  });

  it("posts, reverses, deletes, reads and lists entries", async () => {
    const t = fieldsTransport({
      post_accounting_entry: () => ENTRY,
      reverse_accounting_entry: () => ({
        ...ENTRY,
        id: "e3",
        reversesId: "e1",
      }),
      delete_accounting_entry: () => DRAFT,
      get_accounting_entry: (args) =>
        args["entry_id"] === "e1" ? ENTRY : null,
      list_accounting_entries: () => [ENTRY, DRAFT],
    });

    const books = createAccounting({ transport: t });

    await books.postEntry("e1").orThrow();

    const reversal = await books.reverseEntry({ entryId: "e1" }).orThrow();

    await books
      .reverseEntry({
        entryId: "e1",
        entryDate: Temporal.PlainDate.from("2026-02-01"),
      })
      .orThrow();

    const deleted = await books.deleteEntry("e2").orThrow();
    const found = await books.getEntry("e1").orThrow();
    const missing = await books.getEntry("e9").orThrow();
    const listed = await books.entries({ organizationId: "org-1" }).orThrow();

    await books
      .entries({
        organizationId: "org-1",
        journalId: "j1",
        status: "posted",
        since: Temporal.PlainDate.from("2026-01-01"),
        until: Temporal.PlainDate.from("2026-01-31"),
        pageSize: 50,
      })
      .orThrow();

    expect(reversal.reversesId).toBe("e1");
    expect(deleted).not.toHaveProperty("lines");
    expect(deleted).not.toHaveProperty("number");
    expect(found?.lines).toHaveLength(2);
    expect(missing).toBeUndefined();
    expect(listed.map((item) => item.status)).toEqual(["posted", "draft"]);
    expect(t.calls).toEqual([
      ["post_accounting_entry", { entry_id: "e1" }],
      ["reverse_accounting_entry", { entry_id: "e1", entry_date: null }],
      [
        "reverse_accounting_entry",
        { entry_id: "e1", entry_date: "2026-02-01" },
      ],
      ["delete_accounting_entry", { entry_id: "e2" }],
      ["get_accounting_entry", { entry_id: "e1" }],
      ["get_accounting_entry", { entry_id: "e9" }],
      [
        "list_accounting_entries",
        {
          tenant: "org-1",
          journal_id: null,
          status: null,
          since: null,
          until: null,
          page_size: null,
        },
      ],
      [
        "list_accounting_entries",
        {
          tenant: "org-1",
          journal_id: "j1",
          status: "posted",
          since: "2026-01-01",
          until: "2026-01-31",
          page_size: 50,
        },
      ],
    ]);
  });

  it("closes and reopens periods and closes a fiscal year", async () => {
    const t = fieldsTransport({
      accounting_period_close_blockers: (args) =>
        args["period_id"] === "p1" ? ["draft_entries"] : null,
      close_accounting_period: () => PERIOD,
      reopen_accounting_period: () => ({
        ...PERIOD,
        status: "open",
        closedAt: null,
        closedBy: null,
      }),
      close_fiscal_year: (args) =>
        args["fiscal_year"] === 2026
          ? { organizationId: "org-1", fiscalYear: 2026, closingEntryId: "e9" }
          : { organizationId: "org-1", fiscalYear: 2025, closingEntryId: null },
    });

    const books = createAccounting({ transport: t });

    const blockers = await books.closeBlockers("p1").orThrow();
    const none = await books.closeBlockers("p2").orThrow();
    const closed = await books.closePeriod("p1").orThrow();

    const reopened = await books
      .reopenPeriod({ periodId: "p1", reason: "Late invoice" })
      .orThrow();

    const year = await books
      .closeFiscalYear({ organizationId: "org-1", fiscalYear: 2026 })
      .orThrow();

    const empty = await books
      .closeFiscalYear({ organizationId: "org-1", fiscalYear: 2025 })
      .orThrow();

    expect(blockers).toEqual(["draft_entries"]);
    expect(none).toEqual([]);
    expect(closed.status).toBe("closed");
    expect(reopened).not.toHaveProperty("closedAt");
    expect(year.closingEntryId).toBe("e9");
    expect(empty).not.toHaveProperty("closingEntryId");
    expect(t.calls).toContainEqual([
      "reopen_accounting_period",
      { period_id: "p1", reason: "Late invoice" },
    ]);
  });

  it("reads the reports", async () => {
    const LINE_ROW = {
      accountId: "a2",
      code: "8000",
      name: "Revenue",
      type: "income",
      subtype: "sales",
      amount: "12100",
    };

    const t = fieldsTransport({
      accounting_trial_balance: () => ({
        accounts: [
          {
            accountId: "a1",
            code: "1300",
            name: "Accounts receivable",
            type: "asset",
            opening: "0",
            debit: "12100",
            credit: "0",
            closing: "12100",
          },
        ],
        totals: { opening: "0", debit: "12100", credit: "12100", closing: "0" },
      }),
      accounting_profit_and_loss: () => ({
        income: [LINE_ROW],
        expenses: null,
        totalIncome: "12100",
        totalExpenses: "0",
        netIncome: "12100",
      }),
      accounting_balance_sheet: () => ({
        asOf: "2026-12-31",
        assets: [{ ...LINE_ROW, type: "asset", subtype: null }],
        liabilities: [],
        equity: [],
        currentEarnings: "12100",
        totalAssets: "12100",
        totalLiabilities: "0",
        totalEquity: "12100",
        balanced: true,
      }),
      accounting_general_ledger: () => ({
        account: { id: "a1", code: "1300", name: "AR", type: "asset" },
        opening: "100",
        lines: [
          {
            entryId: "e1",
            number: "SAL-2026-00001",
            entryDate: "2026-01-15",
            journalId: "j1",
            debit: "12100",
            credit: "0",
            balance: "12200",
            description: "Invoice 42",
            partyId: "c1",
          },
        ],
        closing: "12200",
      }),
    });

    const books = createAccounting({ transport: t });
    const since = Temporal.PlainDate.from("2026-01-01");
    const until = Temporal.PlainDate.from("2026-12-31");

    const trial = await books
      .trialBalance({
        organizationId: "org-1",
        since,
        until,
        dimensions: { project: "apollo" },
      })
      .orThrow();

    const pnl = await books
      .profitAndLoss({ organizationId: "org-1" })
      .orThrow();

    const sheet = await books
      .balanceSheet({ organizationId: "org-1", asOf: until })
      .orThrow();

    const ledger = await books
      .generalLedger({ accountId: "a1", since, until })
      .orThrow();

    await books.balanceSheet({ organizationId: "org-1" }).orThrow();
    await books.generalLedger({ accountId: "a1" }).orThrow();

    expect(trial.accounts[0]?.closing).toBe(12_100n);
    expect(trial.totals.closing).toBe(0n);
    expect(pnl).toMatchObject({ expenses: [], netIncome: 12_100n });
    expect(pnl.income[0]?.subtype).toBe("sales");
    expect(sheet).toMatchObject({ balanced: true, currentEarnings: 12_100n });
    expect(sheet.assets[0]).not.toHaveProperty("subtype");
    expect(ledger.lines[0]?.balance).toBe(12_200n);
    expect(ledger.closing).toBe(12_200n);
    expect(t.calls).toEqual([
      [
        "accounting_trial_balance",
        {
          tenant: "org-1",
          since: "2026-01-01",
          until: "2026-12-31",
          dimensions: { project: "apollo" },
        },
      ],
      [
        "accounting_profit_and_loss",
        { tenant: "org-1", since: null, until: null, dimensions: {} },
      ],
      [
        "accounting_balance_sheet",
        { tenant: "org-1", as_of: "2026-12-31", dimensions: {} },
      ],
      [
        "accounting_general_ledger",
        { account_id: "a1", since: "2026-01-01", until: "2026-12-31" },
      ],
      [
        "accounting_balance_sheet",
        { tenant: "org-1", as_of: null, dimensions: {} },
      ],
      [
        "accounting_general_ledger",
        { account_id: "a1", since: null, until: null },
      ],
    ]);
  });
});

describe("accounting schemas", () => {
  it("checks the inputs", () => {
    expect(
      validate(accountingAccountInputSchema, {
        code: "1300",
        name: "Receivables",
        type: "asset",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(accountingAccountInputSchema, {
        code: "1300",
        name: "Receivables",
        type: "other",
      }).issues,
    ).toBeDefined();
    expect(
      validate(accountingJournalInputSchema, {
        code: "SAL",
        name: "Sales",
        type: "sales",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(accountingEntryInputSchema, {
        journalId: ID,
        entryDate: Temporal.PlainDate.from("2026-01-15"),
        lines: [{ accountCode: "1300", debit: "100" }],
      }).issues,
    ).toBeUndefined();
  });

  it("registers the block", () => {
    expect(accountingBlock.name).toBe("accounting");
    expect(accountingBlock.sql).toEqual(["accounting"]);
  });
});
