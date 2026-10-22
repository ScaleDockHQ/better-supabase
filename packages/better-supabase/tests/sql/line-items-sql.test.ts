import { describe, expect, it } from "vitest";

import { renderModules } from "../../src/sql/render.ts";

const body = (module: string): string =>
  renderModules([module])
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
