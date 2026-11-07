import type { BlockSqlContext } from "../context.ts";
import type { BlockSeeds, SeedTable } from "../seeds.ts";

/**
 * The letterhead each locale starts with: the legal entity's name, register
 * number, tax number and bank account on one line, in that country's words. A
 * template prints it with `{{texts.letterhead}}`; `en` seeds none, because an
 * English speaking organization has no single country.
 */
const LETTERHEADS: Readonly<Record<string, string>> = {
  nl: "{{entity.name}} · KvK {{entity.cocNumber}} · BTW {{entity.vatNumber}} · IBAN {{entity.iban}}",
  de: "{{entity.name}} · Handelsregister {{entity.cocNumber}} · USt-IdNr. {{entity.vatNumber}} · IBAN {{entity.iban}}",
  fr: "{{entity.name}} · RCS {{entity.cocNumber}} · TVA {{entity.vatNumber}} · IBAN {{entity.iban}}",
};

/**
 * `document-templates.seeds`: one `letterhead` text block per locale, for the
 * organization (no legal entity). Reference data like this is a locale data
 * migration the app opts into by seeding, never a row `upgrade` writes.
 */
export const documentTemplateSeeds: BlockSeeds = {
  defaults: (ctx: BlockSqlContext): readonly SeedTable[] => {
    if (!ctx.hasTable("textBlocks")) {
      return [];
    }

    const y = (column: string): string => ctx.col("textBlocks", column);

    return Object.entries(LETTERHEADS).map(([locale, body]) => ({
      table: ctx.table("textBlocks"),
      tenantColumn: y("tenant"),
      key: [y("key"), y("language")],
      locales: [locale],
      rows: [
        {
          values: {
            [y("key")]: "letterhead",
            [y("language")]: locale,
            [y("body")]: body,
          },
        },
      ],
    }));
  },
};
