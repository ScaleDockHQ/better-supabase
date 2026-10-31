import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../../src/config/resolve.ts";
import { moduleLayout } from "../../../src/sql/layout.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const SOURCES = [
  "invoices",
  "expenses",
  "inventory",
  "leases",
  "donations",
] as const;

const BASE = [
  "memberships",
  "permissions",
  "subjects",
  "ledger",
  "numbering",
  "catalog",
  "assets",
  "approvals",
];

const render = (
  modules: readonly string[],
  layout: Layout = {},
): Readonly<Record<string, string>> => {
  const files: Record<string, string> = {};

  for (const file of renderBlocks(modules, layout)) {
    files[file.module] = `${files[file.module] ?? ""}\n${file.contents}`;
  }

  return files;
};

const ALL = [...BASE, "accounting", ...SOURCES];

const body = (sql: string, fn: string): string => {
  const start = sql.indexOf(`function "better_supabase"."${fn}"`);

  return start === -1 ? "" : sql.slice(start, sql.indexOf("$$;", start));
};

describe("accounting postings", () => {
  it("dispatches every contributed source and books it from the block's writes", () => {
    const files = render(ALL);
    const accounting = files["accounting"] ?? "";
    const dispatch = body(accounting, "accounting_post_source");

    for (const source of [
      "invoice",
      "invoice_payment",
      "expense_report",
      "expense_reimbursement",
      "stock_movement",
      "lease_rent",
      "lease_payment",
      "gift",
    ]) {
      expect(dispatch).toContain(`when '${source}' then`);
    }

    const writes: Record<string, Record<string, string[]>> = {
      invoices: {
        issue_invoice: [`accounting_post_source"('invoice'`],
        record_invoice_payment: [`accounting_post_source"('invoice_payment'`],
        void_invoice: ['accounting_reverse_source"('],
        reverse_invoice_payment: ['accounting_reverse_source"('],
      },
      expenses: {
        approve_expense_report: [`accounting_post_source"('expense_report'`],
      },
      donations: {
        donation_settle: [
          `accounting_post_source"('gift'`,
          'accounting_reverse_source"(',
        ],
      },
    };

    for (const [module, fns] of Object.entries(writes)) {
      for (const [fn, calls] of Object.entries(fns)) {
        const sql = body(files[module] ?? "", fn);

        for (const call of calls) {
          expect(sql, `${module}.${fn}`).toContain(call);
        }
      }
    }

    expect(files["inventory"]).toContain(
      `accounting_post_source"('stock_movement'`,
    );
    expect(files["leases"]).toContain(`accounting_post_source"('lease_rent'`);
    expect(files["leases"]).toContain(
      `accounting_post_source"('lease_payment'`,
    );
    expect(files["expenses"]).toContain(
      `accounting_post_source"('expense_reimbursement'`,
    );

    for (const module of SOURCES) {
      expect(files[module]).toMatch(
        /revoke execute on function "better_supabase"\."accounting_[a-z_]+_lines"\(text\) from public, anon, authenticated;/,
      );
    }
  });

  it("books nothing when accounting isn't installed", () => {
    const files = render([...BASE, ...SOURCES]);

    for (const module of SOURCES) {
      expect(files[module]).not.toContain("accounting_post_source");
      expect(files[module]).not.toContain('_lines"(source_id text)');
    }
  });

  it("books nothing when accounting is custom", () => {
    const files = render(ALL, { modules: { accounting: { mode: "custom" } } });

    for (const module of SOURCES) {
      expect(files[module]).not.toContain("accounting_post_source");
    }
  });

  it("leaves standalone expenses out", () => {
    const files = render(ALL, {
      modules: { expenses: { tables: { reports: null, lines: null } } },
    });

    expect(files["expenses"]).not.toContain("accounting_post_source");
    expect(
      body(files["accounting"] ?? "", "accounting_post_source"),
    ).not.toContain("'expense_report'");
  });

  it("posts the booked entries unless autoPost is off", () => {
    const on = render(ALL)["accounting"] ?? "";

    const off =
      render(ALL, {
        modules: { accounting: { options: { autoPost: false } } },
      })["accounting"] ?? "";

    expect(body(on, "accounting_post_source")).toContain('accounting_post"(');
    expect(body(off, "accounting_post_source")).not.toContain(
      'accounting_post"(',
    );
    expect(() =>
      render(ALL, {
        modules: { accounting: { options: { autoPost: "yes" } } },
      }),
    ).toThrow("autoPost");
  });

  it("refuses an unknown source and renders the tax report and budgets", () => {
    const alone = render([...BASE, "outbox", "accounting"])["accounting"] ?? "";

    expect(body(alone, "accounting_post_source")).toContain(
      "source_type not in ('asset_depreciation', 'asset_disposal')",
    );
    expect(
      body(
        render([
          ...BASE.filter((name) => name !== "assets"),
          "outbox",
          "accounting",
        ])["accounting"] ?? "",
        "accounting_post_source",
      ),
    ).toContain("or true");

    expect(
      [
        "post_accounting_source",
        "accounting_tax_report",
        "save_accounting_budget",
        "get_accounting_budget",
        "list_accounting_budgets",
        "accounting_budget_vs_actual",
      ].filter((fn) => body(alone, fn) === ""),
    ).toEqual([]);

    expect(alone).toContain("'accounting_budget.created'");
    expect(alone).toContain("'accounting_budget.updated'");
  });

  it("books invoice charges and write-offs", () => {
    const files = render(ALL);
    const dispatch = body(files["accounting"] ?? "", "accounting_post_source");
    const invoices = files["invoices"] ?? "";

    expect(dispatch).toContain("when 'invoice_charge' then");
    expect(dispatch).toContain("when 'invoice_write_off' then");
    expect(body(invoices, "add_invoice_charge")).toContain(
      `accounting_post_source"('invoice_charge'`,
    );
    expect(body(invoices, "remove_invoice_charge")).toContain(
      `accounting_reverse_source"(`,
    );
    expect(body(invoices, "write_off_invoice")).toContain(
      `accounting_post_source"('invoice_write_off'`,
    );
    expect(body(invoices, "void_invoice")).toContain("'invoice_charge'");
  });

  it("leaves billed time out of project costs when its revenue is on the dimension", () => {
    const files = render([...ALL, "tasks", "time-tracking", "billable-time"]);

    expect(body(files["billable-time"] ?? "", "project_costs")).toContain(
      "->> 'project' = v_project",
    );
  });

  it("lets a named instance book through its own accounting instance", () => {
    const config = resolveConfig(
      {
        blocks: {
          accounting: {},
          accountingEu: {
            block: "accounting",
            entities: {
              accounting_account: "eu_account",
              accounting_journal: "eu_journal",
              accounting_period: "eu_period",
              accounting_entry: "eu_entry",
              accounting_dimension: "eu_dimension",
              accounting_tax_code: "eu_tax_code",
              accounting_budget: "eu_budget",
            },
          },
          invoices: {},
          invoicesEu: {
            block: "invoices",
            entities: { invoice: "eu_invoice" },
            uses: { accounting: "accountingEu" },
          },
        },
      },
      "/app",
    );

    const files = renderBlocks(
      [...BASE, ...config.blockNames],
      moduleLayout(config),
    );

    const eu = files.find(
      (file) => file.kind === "schema" && file.instance === "invoicesEu",
    );

    const plain = files.find(
      (file) => file.kind === "schema" && file.instance === undefined,
    );

    expect(eu?.contents).toContain("accounting_post_source");
    expect(plain).toBeDefined();
  });

  it("books nothing for a named instance that leaves uses alone", () => {
    const config = resolveConfig(
      {
        blocks: {
          accounting: {},
          invoices: {},
          invoicesEu: {
            block: "invoices",
            entities: { invoice: "eu_invoice" },
          },
        },
      },
      "/app",
    );

    const eu = renderBlocks(
      [...BASE, ...config.blockNames],
      moduleLayout(config),
    ).find((file) => file.kind === "schema" && file.instance === "invoicesEu");

    expect(eu?.contents).not.toContain("accounting_post_source");
  });

  it("adds the disposal accounts to existing charts in a data step", () => {
    const data = renderBlocks([...BASE, "accounting"], {}).find(
      (file) => file.kind === "data" && file.module === "accounting",
    );

    expect(data?.contents).toContain("'disposal_gain'");
    expect(data?.contents).toContain("'disposal_loss'");
    expect(data?.contents).toContain("on conflict");
  });

  it("gives existing projects their project dimension value in a data step", () => {
    const data = renderBlocks([...BASE, "accounting", "tasks"], {}).find(
      (file) => file.kind === "data" && file.module === "tasks",
    );

    expect(data?.contents).toContain("accounting_sync_dimension_value");
  });
});
