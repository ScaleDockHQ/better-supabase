import type { BlockSqlContext } from "../context.ts";
import type { BlockSeeds, SeedRow, SeedTable } from "../seeds.ts";
import type { ChartAccount } from "./accounting-shared.ts";

import {
  accountingConfig,
  DEFAULT_JOURNALS,
  GENERIC_CHART,
} from "./accounting-shared.ts";

/** The chart variants `accounting.seeds` offers. */
const ACCOUNTING_VARIANTS = ["generic", "nl-rgs"] as const;

interface ChartJournal {
  readonly code: string;
  readonly name: string;
  readonly type: (typeof DEFAULT_JOURNALS)[number]["type"];
  readonly account?: string;
}

/**
 * A Dutch chart in the layout the Referentiegrootboekschema (RGS) groups by:
 * fixed assets, current assets, equity, liabilities, then costs and revenue. It
 * uses the numeric codes small Dutch companies book with, every account role
 * has an account, and it stays within the default subtypes. The alphanumeric
 * RGS reference codes come from importing the full scheme.
 */
export const NL_RGS_CHART: readonly ChartAccount[] = [
  {
    code: "0100",
    name: "Vaste activa",
    type: "asset",
    subtype: "fixed_asset",
    role: "fixed_asset",
  },
  {
    code: "0190",
    name: "Cumulatieve afschrijvingen",
    type: "asset",
    subtype: "fixed_asset",
    role: "accumulated_depreciation",
  },
  { code: "1000", name: "Kas", type: "asset", subtype: "cash" },
  {
    code: "1100",
    name: "Bank",
    type: "asset",
    subtype: "bank",
    reconcilable: true,
    role: "bank",
  },
  {
    code: "1200",
    name: "Debiteuren",
    type: "asset",
    subtype: "receivable",
    reconcilable: true,
    role: "receivable",
  },
  {
    code: "1300",
    name: "Voorraad",
    type: "asset",
    subtype: "inventory",
    role: "inventory",
  },
  {
    code: "1350",
    name: "Onderhanden werk",
    type: "asset",
    subtype: "inventory",
    role: "work_in_progress",
  },
  {
    code: "1400",
    name: "Te vorderen btw",
    type: "asset",
    subtype: "current_asset",
    role: "tax_receivable",
  },
  {
    code: "1900",
    name: "Kruisposten",
    type: "asset",
    subtype: "current_asset",
    role: "suspense",
  },
  { code: "2000", name: "Eigen vermogen", type: "equity", subtype: "equity" },
  {
    code: "2900",
    name: "Overige reserves",
    type: "equity",
    subtype: "equity",
    role: "retained_earnings",
  },
  {
    code: "3000",
    name: "Crediteuren",
    type: "liability",
    subtype: "payable",
    reconcilable: true,
    role: "payable",
  },
  {
    code: "3100",
    name: "Te betalen btw",
    type: "liability",
    subtype: "tax",
    role: "tax_payable",
  },
  {
    code: "3200",
    name: "Vooruitontvangen opbrengsten",
    type: "liability",
    subtype: "current_liability",
    role: "deferred_revenue",
  },
  {
    code: "4000",
    name: "Bedrijfskosten",
    type: "expense",
    subtype: "operating_expense",
    role: "expense",
  },
  {
    code: "4800",
    name: "Afschrijvingen",
    type: "expense",
    subtype: "operating_expense",
    role: "depreciation_expense",
  },
  {
    code: "7000",
    name: "Kostprijs van de omzet",
    type: "expense",
    subtype: "cogs",
    role: "cogs",
  },
  {
    code: "8000",
    name: "Omzet",
    type: "income",
    subtype: "revenue",
    role: "revenue",
  },
  {
    code: "8900",
    name: "Koerswinsten",
    type: "income",
    subtype: "other_income",
    role: "fx_gain",
  },
  {
    code: "8910",
    name: "Boekwinst op verkoop van activa",
    type: "income",
    subtype: "other_income",
    role: "disposal_gain",
  },
  {
    code: "9900",
    name: "Koersverliezen",
    type: "expense",
    subtype: "other_expense",
    role: "fx_loss",
  },
  {
    code: "9910",
    name: "Boekverlies op verkoop van activa",
    type: "expense",
    subtype: "other_expense",
    role: "disposal_loss",
  },
];

const NL_RGS_JOURNALS: readonly ChartJournal[] = [
  { code: "VK", name: "Verkoop", type: "sales" },
  { code: "IK", name: "Inkoop", type: "purchase" },
  { code: "BNK", name: "Bank", type: "bank", account: "1100" },
  { code: "KAS", name: "Kas", type: "cash", account: "1000" },
  { code: "MEM", name: "Memoriaal", type: "general" },
];

/**
 * One variant's accounts, account roles and journals, in the order they depend
 * on each other.
 */
function chartTables(
  ctx: BlockSqlContext,
  variant: (typeof ACCOUNTING_VARIANTS)[number],
  chart: readonly ChartAccount[],
  journals: readonly ChartJournal[],
): readonly SeedTable[] {
  const a = (column: string): string => ctx.col("accounts", column);
  const r = (column: string): string => ctx.col("roles", column);
  const j = (column: string): string => ctx.col("journals", column);

  const account = (code: string) =>
    ({
      ref: {
        table: ctx.table("accounts"),
        tenantColumn: a("tenant"),
        column: a("id"),
        match: { [a("code")]: code },
      },
    }) as const;

  // The generic chart is also the default when no variant is named.
  const scope =
    variant === "generic"
      ? ({ variant, defaultVariant: true } as const)
      : ({ variant } as const);

  return [
    {
      table: ctx.table("accounts"),
      tenantColumn: a("tenant"),
      key: [a("code")],
      ...scope,
      rows: chart.map((entry): SeedRow => ({
        values: {
          [a("code")]: entry.code,
          [a("name")]: entry.name,
          [a("type")]: entry.type,
          [a("subtype")]: entry.subtype,
          [a("reconcilable")]: entry.reconcilable ?? false,
          [a("normalSide")]:
            entry.type === "asset" || entry.type === "expense"
              ? "debit"
              : "credit",
        },
      })),
    },
    {
      table: ctx.table("roles"),
      tenantColumn: r("tenant"),
      key: [r("role")],
      ...scope,
      rows: chart.flatMap((entry): readonly SeedRow[] =>
        entry.role === undefined
          ? []
          : [
              {
                values: {
                  [r("role")]: entry.role,
                  [r("account")]: account(entry.code),
                },
              },
            ],
      ),
    },
    {
      table: ctx.table("journals"),
      tenantColumn: j("tenant"),
      key: [j("code")],
      ...scope,
      rows: journals.map((journal): SeedRow => ({
        values: {
          [j("code")]: journal.code,
          [j("name")]: journal.name,
          [j("type")]: journal.type,
          [j("defaultAccount")]:
            journal.account === undefined ? null : account(journal.account),
        },
      })),
    },
  ];
}

/**
 * `accounting.seeds`: the built-in cost center and cost object dimensions for
 * every organization, then a chart of accounts with its account roles and
 * journals. `generic` is the default; `nl-rgs` seeds the Dutch chart. With
 * `options.chart: "none"` the app imports its own chart and none is declared.
 * `setup_accounting` applies `generic` to an organization without accounts.
 */
export const accountingSeeds: BlockSeeds = {
  variants: ACCOUNTING_VARIANTS,
  defaults: (ctx: BlockSqlContext): readonly SeedTable[] => {
    const d = (column: string): string => ctx.col("dimensions", column);

    const dimensions: SeedTable = {
      table: ctx.table("dimensions"),
      tenantColumn: d("tenant"),
      key: [d("key")],
      rows: [
        { values: { [d("key")]: "cost_center", [d("name")]: "Cost center" } },
        { values: { [d("key")]: "cost_object", [d("name")]: "Cost object" } },
      ],
    };

    if (accountingConfig(ctx).chart !== "generic") {
      return [dimensions];
    }

    return [
      dimensions,
      ...chartTables(ctx, "generic", GENERIC_CHART, DEFAULT_JOURNALS),
      ...chartTables(ctx, "nl-rgs", NL_RGS_CHART, NL_RGS_JOURNALS),
    ];
  },
};
