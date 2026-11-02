import type { BlockSqlContext } from "../context.ts";
import type { BlockSeeds, SeedTable } from "../seeds.ts";

import { taxSql } from "./tax-sql.ts";

/** A rate a country's tax codes start with. */
interface CountryCode {
  readonly code: string;
  readonly name: string;
  readonly type: "sales" | "zero" | "exempt";
  /** Basis points: 2100 is 21%. */
  readonly rateBps?: number;
}

/**
 * The standard value added tax codes per locale. The locale is the language the
 * defaults are applied in; `en` seeds none, because an English speaking
 * organization has no single country.
 */
const COUNTRIES: Readonly<Record<string, readonly CountryCode[]>> = {
  nl: [
    { code: "NL21", name: "BTW hoog 21%", type: "sales", rateBps: 2100 },
    { code: "NL9", name: "BTW laag 9%", type: "sales", rateBps: 900 },
    { code: "NL0", name: "BTW 0%", type: "zero" },
    { code: "NLVRIJ", name: "Vrijgesteld van BTW", type: "exempt" },
  ],
  de: [
    { code: "DE19", name: "Umsatzsteuer 19%", type: "sales", rateBps: 1900 },
    { code: "DE7", name: "Umsatzsteuer 7%", type: "sales", rateBps: 700 },
    { code: "DE0", name: "Umsatzsteuer 0%", type: "zero" },
  ],
  fr: [
    { code: "FR20", name: "TVA 20%", type: "sales", rateBps: 2000 },
    { code: "FR10", name: "TVA 10%", type: "sales", rateBps: 1000 },
    { code: "FR55", name: "TVA 5,5%", type: "sales", rateBps: 550 },
    { code: "FR0", name: "TVA 0%", type: "zero" },
  ],
};

/**
 * `tax.seeds`: the standard codes of a country, each with a rate that starts at
 * the epoch, for organizations created in that locale.
 */
export const taxSeeds: BlockSeeds = {
  defaults: (ctx: BlockSqlContext): readonly SeedTable[] => {
    const q = taxSql(ctx);
    const { c, r } = q;

    return Object.entries(COUNTRIES).flatMap(([locale, codes]) => [
      {
        table: q.codes,
        tenantColumn: c("tenant"),
        key: [c("code")],
        locales: [locale],
        rows: codes.map((entry) => ({
          values: {
            [c("code")]: entry.code,
            [c("name")]: entry.name,
            [c("type")]: entry.type,
          },
        })),
      },
      {
        table: q.rates,
        tenantColumn: r("tenant"),
        key: [r("taxCode")],
        locales: [locale],
        rows: codes.flatMap((entry) =>
          entry.rateBps === undefined
            ? []
            : [
                {
                  values: {
                    [r("taxCode")]: {
                      ref: {
                        table: q.codes,
                        tenantColumn: c("tenant"),
                        match: { [c("code")]: entry.code },
                        column: c("id"),
                      },
                    },
                    [r("rateBps")]: entry.rateBps,
                  },
                },
              ],
        ),
      },
    ]);
  },
};
