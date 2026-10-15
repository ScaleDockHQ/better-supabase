import { describe, expect, it } from "vitest";

import type { BlocksConfig } from "../../../src/config/blocks.ts";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (modules: BlocksConfig = {}): string =>
  renderModules(["number-sequences"], { modules })
    .filter((file) => file.module === "number-sequences")
    .map((file) => file.contents)
    .join("\n");

describe("number sequences", () => {
  it("allocates inside the caller's transaction and keeps the function service-only", () => {
    const sql = sqlOf();
    expect(sql).toContain("on conflict");
    expect(sql).toContain("last_number");
    expect(sql).toContain("grant execute on function");
    expect(sql).toContain("to service_role");
    expect(sql).not.toContain("to authenticated, service_role");
    expect(sql).toContain("ACTOR_READ_ONLY");
    expect(sql).toContain("on conflict");
  });

  it("resets the period and fills a column when a document is issued", () => {
    const sql = sqlOf({
      "number-sequences": {
        options: {
          entities: {
            invoice: {
              period: "year",
              format: "INV-{yyyy}-{n:5}",
              table: "public.invoices",
              column: "number",
              assignOn: "new.status = 'sent'",
              tenantColumn: "organization_id",
            },
            order: {
              period: { fiscalYearStartMonth: 4 },
              format: "PO-{yyyy}-{n}",
            },
          },
        },
      },
    });
    expect(sql).toContain("to_char(next_number.at at time zone 'utc', 'YYYY')");
    expect(sql).toContain(
      "extract(month from next_number.at at time zone 'utc') >= 4",
    );
    expect(sql).toContain("new.status = 'sent'");
    expect(sql).toContain("NUMBER_IMMUTABLE");
    expect(sql).toContain("organization_id");
    expect(sql).toContain("INV-{yyyy}-{n:5}");
  });

  it("refuses a predicate that is not an expression", () => {
    expect(() =>
      sqlOf({
        "number-sequences": {
          options: {
            entities: {
              invoice: {
                period: "none",
                format: "{n}",
                table: "public.invoices",
                column: "number",
                assignOn: "new.status = 'sent'; drop table invoices",
              },
            },
          },
        },
      }),
    ).toThrow(/assignOn/);
  });
});
