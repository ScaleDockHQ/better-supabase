import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { FUNDING } from "../../../src/sql/modules/funding.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "contacts", "funding"];

const ALL = [
  "memberships",
  "permissions",
  "subjects",
  "contacts",
  "outbox",
  "notifications",
  "audit",
  "funding",
];

const TIME = [...BASE, "time-tracking"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "funding")
    .map((file) => file.contents)
    .join("\n");

describe("funding module", () => {
  it("indexes every foreign key and keeps a source registered once", () => {
    const sql = sqlOf();
    expect(sql).toContain('"funding_awards_product_idx"');
    expect(sql).toContain('"funding_deliveries_award_idx"');
    expect(sql).toContain('"funding_deliveries_claim_line_idx"');
    expect(sql).toContain('"funding_claim_lines_claim_idx"');
    expect(sql).toContain('"funding_claim_lines_award_idx"');
    expect(sql).toContain('"funding_claim_lines_product_idx"');
    expect(sql).toMatch(
      /"funding_deliveries_source_idx" on [^(]+\("tenant_id", "source_type", "source_id"\) where "source_id" is not null/,
    );
  });

  it("reads awards and deliveries only for records the member may read", () => {
    const sql = sqlOf();
    expect(sql).toContain('"better_supabase"."can_subject"(');
    expect(sql).toContain("funding.read");
  });

  it("takes funders from contacts with the funder role", () => {
    const sql = sqlOf();
    expect(sql).toContain("'funder' = any (x.\"roles\")");
    expect(sql).toContain("FUNDING_FUNDER_INVALID");
  });

  it("emits an exceeded award and notifies the managers only with notifications", () => {
    expect(sqlOf()).toContain("funding_award.exceeded");
    expect(sqlOf(ALL)).toContain("'funding-exceeded:'");
    expect(sqlOf()).not.toContain("'funding-exceeded:'");
  });

  it("checks the claim format against options.formats", () => {
    const sql = sqlOf(BASE, {
      modules: { funding: { options: { formats: ["iwlz-aw319", "x837p"] } } },
    });

    expect(sql).toContain("v_format not in ('iwlz-aw319', 'x837p')");
    expect(sqlOf()).not.toContain("v_format not in");
    expect(() =>
      sqlOf(BASE, {
        modules: { funding: { options: { formats: ["Not A Key"] } } },
      }),
    ).toThrow('"Not A Key" is not a format key');
  });

  it("registers time entries only with time-tracking", () => {
    expect(sqlOf()).not.toContain("register_funding_deliveries_from_time");
    const sql = sqlOf(TIME);
    expect(sql).toContain("register_funding_deliveries_from_time");
    expect(sql).toContain("'no_award'");
    expect(sql).toContain("'several_awards'");
  });

  it("matches a time entry to a product by the timeCategory column", () => {
    const layout: Layout = {
      modules: {
        "time-tracking": { options: { extraColumns: { category: "text" } } },
        funding: { options: { timeCategory: "category" } },
      },
    };

    expect(sqlOf(TIME, layout)).toContain('x."category"::text');
    expect(() =>
      sqlOf(TIME, {
        modules: { funding: { options: { timeCategory: "zzz" } } },
      }),
    ).toThrow('"zzz" is not one of');
    expect(() =>
      sqlOf(BASE, {
        modules: { funding: { options: { timeCategory: "category" } } },
      }),
    ).toThrow("needs the time-tracking block");
  });

  it("invoices accepted claims only with invoices", () => {
    expect(sqlOf()).not.toContain("invoice_funding_claim");
    const sql = sqlOf([...BASE, "invoices"]);
    expect(sql).toContain("invoice_funding_claim");
    expect(sql).toContain("FUNDING_CLAIM_STATUS_INVALID");
  });

  it("numbers claims through numbering when it has a funding_claim format", () => {
    const layout: Layout = {
      modules: {
        numbering: {
          options: {
            entities: { funding_claim: { format: "FC-{seq}", period: "none" } },
          },
        },
      },
    };

    expect(sqlOf([...BASE, "numbering"], layout)).toContain(
      "'funding_claim', now()",
    );
    expect(sqlOf()).toContain('max(x."number"::bigint)');
  });

  it("adds extra columns to awards and writes them from attrs.fields", () => {
    const sql = sqlOf(BASE, {
      modules: {
        funding: { options: { extraColumns: { indication: "text" } } },
      },
    });

    expect(sql).toContain(
      `alter table "better_supabase"."funding_awards" add column if not exists "indication" text;`,
    );
    expect(sql).toContain("'fields', jsonb_build_object('indication'");
    expect(() =>
      sqlOf(BASE, {
        modules: {
          funding: { options: { extraColumns: { product: "text" } } },
        },
      }),
    ).toThrow("product");
    expect(sqlOf()).not.toContain("'fields'");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { funding: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(FUNDING.build(context, {})).toBe("");
    const [contract] = customContracts(["funding"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "save_funding_award",
        "register_funding_delivery",
        "build_funding_claim",
        "record_funding_claim_response",
      ]),
    );
  });
});
