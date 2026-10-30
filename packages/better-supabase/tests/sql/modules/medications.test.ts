import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { MEDICATIONS } from "../../../src/sql/modules/medications.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "medications"];

const ALL = [
  "memberships",
  "permissions",
  "subjects",
  "outbox",
  "notifications",
  "audit",
  "medications",
];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "medications")
    .map((file) => file.contents)
    .join("\n");

describe("medications module", () => {
  it("indexes every foreign key and keeps one dose per order and time", () => {
    const sql = sqlOf();
    expect(sql).toContain('"medication_orders_item_idx"');
    expect(sql).toContain('"medication_administrations_order_idx"');
    expect(sql).toMatch(/unique \("order_id", "scheduled_at"\)/);
    expect(sql).toContain(
      'on conflict ("order_id", "scheduled_at") do nothing',
    );
  });

  it("reads orders and doses only for records the member may read", () => {
    const sql = sqlOf();
    expect(sql).toContain('"better_supabase"."can_subject"(');
    expect(sql).toContain("medications.read");
  });

  it("checks high-risk doses with a second member who may administer", () => {
    const sql = sqlOf();
    expect(sql).toContain("MEDICATION_DOUBLE_CHECK_REQUIRED");
    expect(sql).toContain("MEDICATION_DOUBLE_CHECK_SELF");
    expect(sql).toContain("MEDICATION_MAX_DOSE_EXCEEDED");
  });

  it("notifies the members who manage medications of a missed dose only with notifications", () => {
    expect(sqlOf(ALL)).toContain("medications.manage");
    expect(sqlOf(ALL)).toContain("'medication_administration.missed:'");
    expect(sqlOf()).not.toContain("notification_events");
  });

  it("takes the missed delay and time zone from the options", () => {
    const sql = sqlOf(BASE, {
      modules: {
        medications: {
          options: { missedAfterMinutes: 30, timeZone: "Europe/Amsterdam" },
        },
      },
    });

    expect(sql).toContain("interval '30 minutes'");
    expect(sql).toContain("'Europe/Amsterdam'");
    expect(() =>
      sqlOf(BASE, {
        modules: { medications: { options: { missedAfterMinutes: 0 } } },
      }),
    ).toThrow("missedAfterMinutes");
    expect(() =>
      sqlOf(BASE, {
        modules: { medications: { options: { timeZone: "Mars/Base" } } },
      }),
    ).toThrow('"Mars/Base" is not a time zone');
  });

  it("adds extra columns to orders and writes them from attrs.fields", () => {
    const sql = sqlOf(BASE, {
      modules: { medications: { options: { extraColumns: { ward: "text" } } } },
    });

    expect(sql).toContain(
      `alter table "better_supabase"."medication_orders" add column if not exists "ward" text;`,
    );
    expect(sql).toContain("coalesce(v_attrs -> 'fields', '{}'::jsonb)");
    expect(sql).toContain("coalesce(v_item -> 'fields', '{}'::jsonb)");
    expect(sql).toContain("'fields', jsonb_build_object('ward'");
    expect(sql).toContain("fields is an object");
    expect(() =>
      sqlOf(BASE, {
        modules: {
          medications: { options: { extraColumns: { medication: "text" } } },
        },
      }),
    ).toThrow("medication");
    expect(sqlOf()).not.toContain("'fields'");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { medications: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(MEDICATIONS.build(context, {})).toBe("");
    const [contract] = customContracts(["medications"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "prescribe_medication",
        "record_medication_administration",
        "medication_chart",
      ]),
    );
  });
});
