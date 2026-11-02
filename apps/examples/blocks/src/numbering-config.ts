import { defineConfig } from "better-supabase/config";

/**
 * Two legal entities each have an `INV-1`: with `legal-entities` installed and
 * `invoices` in `options.on`, invoices number per legal entity. `scopeColumn`
 * scopes another table the same way.
 */
export default defineConfig({
  blocks: {
    "legal-entities": {},
    numbering: {
      options: {
        on: ["invoices"],
        entities: {
          quote: {
            table: "quotes",
            column: "number",
            format: "Q-{yyyy}-{n:5}",
            period: "year",
            scopeColumn: "legal_entity_id",
          },
        },
      },
    },
  },
});
