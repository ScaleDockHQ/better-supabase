import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (
  module: string,
  names: readonly string[],
  layout: BlockSqlLayout = {},
): string =>
  renderBlocks([...names], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const RECURRING: BlockSqlLayout = {
  modules: { bookings: { options: { recurring: true } } },
};

const CREDITS: BlockSqlLayout = {
  modules: {
    bookings: { options: { recurring: true } },
    "admission-passes": {
      options: { credits: true, creditRefundBefore: "1 day" },
    },
  },
};

describe("bookings recurring option", () => {
  it("adds nothing while it is off", () => {
    const sql = sqlOf("bookings", ["organizations", "bookings"]);
    expect(sql).not.toContain("booking_series");
    expect(sql).not.toContain("series_id");
    expect(sql).not.toContain("reschedule_booking");
  });

  it("adds series, an indexed series key and the series functions", () => {
    const sql = sqlOf("bookings", ["organizations", "bookings"], RECURRING);
    expect(sql).toContain(
      `create table if not exists "better_supabase"."booking_series"`,
    );
    expect(sql).toContain(
      `add column if not exists "series_id" uuid references "better_supabase"."booking_series" ("id") on delete set null`,
    );
    expect(sql).toContain("bookings_series_idx");

    for (const index of ["service_idx", "resource_idx", "customer_idx"]) {
      expect(sql).toContain(`booking_series_${index}`);
    }

    for (const fn of [
      "book_series",
      "reschedule_booking",
      "cancel_booking_series",
      "get_booking_series",
      "booking_series_starts",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `grant execute on function "better_supabase"\\."${fn}"\\([^)]*\\) to authenticated`,
        ),
      );
    }

    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."move_booking"\([^)]*\) to service_role;/,
    );
    expect(sql).toContain("'seriesId', bk.\"series_id\"");
  });

  it("only applies to managed tables", () => {
    const sql = sqlOf("bookings", ["organizations", "bookings"], {
      modules: {
        bookings: {
          mode: "adopt",
          options: { recurring: true },
          tables: { series: null },
        },
      },
    });

    expect(sql).not.toContain("book_series");
  });
});

describe("passes credits option", () => {
  const modules = ["organizations", "outbox", "bookings", "admission-passes"];

  it("adds nothing while it is off or without bookings", () => {
    expect(sqlOf("admission-passes", modules)).not.toContain(
      "book_with_credit",
    );
    expect(
      sqlOf("admission-passes", ["organizations", "admission-passes"], {
        modules: { "admission-passes": { options: { credits: true } } },
      }),
    ).not.toContain("book_with_credit");
  });

  it("installs the ledger along with the credits", () => {
    const files = renderBlocks(modules, CREDITS).map((file) => file.module);
    expect(files).toContain("ledger");
    expect(renderBlocks(modules).map((file) => file.module)).not.toContain(
      "ledger",
    );
  });

  it("posts credits on the ledger, with the refund trigger and the functions", () => {
    const sql = sqlOf("admission-passes", modules, CREDITS);
    expect(sql).not.toContain("pass_credit_entries");
    expect(sql).toContain(`"better_supabase"."ledger_post"(`);
    expect(sql).toContain("'pass-credit:' || ");
    expect(sql).toContain(`"passes_credit_refund"`);

    expect(sql).toContain(
      `after update of "status" on "better_supabase"."bookings"`,
    );
    expect(sql).toContain(`'1 day'::interval`);
    expect(sql).toContain("'bs:moving'");
    expect(sql).toContain("emit_event('pass.credit_used'");
    expect(sql).toContain("emit_event('pass.credit_refunded'");

    for (const fn of ["book_with_credit", "list_pass_credits"]) {
      expect(sql).toMatch(
        new RegExp(
          `grant execute on function "better_supabase"\\."${fn}"\\([^)]*\\) to authenticated`,
        ),
      );
    }
  });
});
