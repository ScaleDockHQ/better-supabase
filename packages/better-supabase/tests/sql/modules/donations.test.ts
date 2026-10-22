import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === "donations")
    .map((file) => file.contents)
    .join("\n");

describe("donations module", () => {
  it("posts and reverses gifts on the ledger with keys per gift", () => {
    const sql = sqlOf(["donations"]);

    expect(sql).toContain(`'donation:' || v_row."id"::text || ':posted'`);
    expect(sql).toContain(`'donation:' || v_row."id"::text || ':refunded'`);
    expect(sql).toContain("'donations:cash:'");
    expect(sql).toContain("'donations:fund:'");
  });

  it("charges a pledge period once", () => {
    const sql = sqlOf(["donations"]);

    expect(sql).toContain(`unique ("pledge_id", "period_start")`);
    expect(sql).toContain(
      `on conflict ("pledge_id", "period_start") do nothing`,
    );
  });

  it("numbers receipts per organization, from number-sequences when configured", () => {
    expect(sqlOf(["donations"])).toContain("'R-' || v_seq::text");

    const sequenced = sqlOf(["donations", "number-sequences"], {
      modules: {
        "number-sequences": {
          options: {
            entities: {
              donation_receipt: { period: "year", format: "R-{yyyy}-{n}" },
            },
          },
        },
      },
    });

    expect(sequenced).toContain("format_assigned_number('R-{yyyy}-{n}'");
  });

  it("keeps settling internal", () => {
    expect(sqlOf(["donations"])).toMatch(
      /revoke execute on function "better_supabase"\."donation_settle"\(uuid, text, text, text\) from public, anon, authenticated/,
    );
  });

  it("needs the managed ledger tables", () => {
    expect(() =>
      renderModules(["donations"], { modules: { ledger: { mode: "custom" } } }),
    ).toThrow(/ledger can't be in custom mode/);
  });
});
