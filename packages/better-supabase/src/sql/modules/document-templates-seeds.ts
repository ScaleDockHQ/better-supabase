import type { BlockSqlContext } from "../context.ts";
import type { BlockSeeds, SeedTable } from "../seeds.ts";

import { LETTERHEADS } from "../seed-labels.ts";

/**
 * The letterhead each locale starts with. A template prints it with
 * `{{texts.letterhead}}`. `en`, `nl` and `de` come from the seed catalog. `fr`
 * stays beside them.
 */
const LETTERHEAD_TEXT: Readonly<Record<string, string>> = {
  ...LETTERHEADS.locales,
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

    return Object.entries(LETTERHEAD_TEXT).map(([locale, body]) => ({
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
