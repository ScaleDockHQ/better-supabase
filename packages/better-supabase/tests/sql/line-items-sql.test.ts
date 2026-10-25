import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";

const body = (module: string): string =>
  renderBlocks([module])
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("line item totals", () => {
  it.each([
    ["quotes", "quote_lines"],
    ["invoices", "invoice_lines"],
    ["deals", "deal_lines"],
  ])("recounts each %s record once per statement", (module, lines) => {
    const sql = body(module);
    const trigger = `bsb_${lines}_totals`;
    const table = `"better_supabase"."${lines}"`;

    expect(sql).toContain(
      `create trigger ${trigger}_insert after insert on ${table}\nreferencing new table as new_rows\nfor each statement execute function better_supabase.${trigger}();`,
    );
    expect(sql).toContain(
      `create trigger ${trigger}_update after update on ${table}\nreferencing old table as old_rows new table as new_rows\nfor each statement execute function better_supabase.${trigger}();`,
    );
    expect(sql).toContain(
      `create trigger ${trigger}_delete after delete on ${table}\nreferencing old table as old_rows\nfor each statement execute function better_supabase.${trigger}();`,
    );
    expect(sql).toContain(`drop trigger if exists ${trigger} on ${table};`);
    expect(sql).not.toContain(
      `for each row execute function better_supabase.${trigger}();`,
    );
    expect(sql).toContain(
      `when 'INSERT' then 'select distinct n."parent_id" from new_rows n order by 1'`,
    );
    expect(sql).toContain(
      `else 'select n."parent_id" from new_rows n union select o."parent_id" from old_rows o order by 1'`,
    );
    expect(sql).toContain(
      `revoke execute on function better_supabase.${trigger}() from public, anon, authenticated;`,
    );
  });
});

describe("line tables of the app's", () => {
  const files = (module: string, layout: Parameters<typeof renderBlocks>[1]) =>
    renderBlocks([module], layout)
      .filter((file) => file.module === module)
      .map((file) => file.contents)
      .join("\n");

  it.each([
    ["quotes", "quote_lines"],
    ["invoices", "invoice_lines"],
    ["deals", "deal_lines"],
  ])("runs %s over the app's %s", (module, lines) => {
    const sql = files(module, {
      ownTables: { [`public.${lines}`]: "supabase/schemas/lines.sql" },
      modules: {
        [module]: {
          tables: { lines: `public.${lines}` },
          columns: {
            lines: { tenant: "organization_id", parent: "record_id" },
          },
        },
      },
    });

    expect(sql).not.toContain(`create table if not exists "public"."${lines}"`);
    expect(sql).toContain(
      `alter table "public"."${lines}" add column if not exists "organization_id"`,
    );
    expect(sql).toContain(
      `insert into "public"."${lines}" ("organization_id", "record_id", `,
    );
  });

  it("writes and reads the line table's extra columns from each line's fields", () => {
    const sql = files("quotes", {
      modules: { quotes: { options: { lineExtraColumns: { sku: "text" } } } },
    });

    expect(sql).toContain(
      `alter table "better_supabase"."quote_lines" add column if not exists "sku" text;`,
    );
    expect(sql).toContain(
      "for v_line in select x.value -> 'fields' as fields, x.ordinality::integer as position",
    );
    expect(sql).toContain(
      `update "better_supabase"."quote_lines" x set "sku" =`,
    );
    expect(sql).toContain(`'fields', jsonb_build_object('sku', ql."sku")`);
  });

  it("refuses a line extra column that shadows a line column", () => {
    expect(() =>
      files("invoices", {
        modules: {
          invoices: { options: { lineExtraColumns: { position: "integer" } } },
        },
      }),
    ).toThrow(/lineExtraColumns\.position shadows a column/u);
  });
});
