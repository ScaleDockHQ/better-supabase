import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (
  options: Record<string, unknown> = {},
  extra: readonly string[] = [],
): string =>
  renderModules(["parties", ...extra], { modules: { parties: { options } } })
    .filter((file) => file.module === "parties")
    .map((file) => file.contents)
    .join("\n");

describe("parties module", () => {
  it("renders the tables, dedupe indexes and functions", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."companies"',
    );
    expect(sql).toContain("create unique index if not exists people_email_idx");
    expect(sql).toContain(
      "create unique index if not exists company_people_primary_idx",
    );
    expect(sql).toContain("'{lead,prospect,customer,churned}'::text[]");
    expect(sql).not.toContain("notification_subscriptions");
  });

  it("adds extra columns to companies only and writes them on save", () => {
    const sql = sqlOf({ extraColumns: { segment: "text" } });
    expect(sql).toContain(
      'alter table "better_supabase"."companies" add column if not exists "segment" text;',
    );
    expect(sql).not.toContain('"people" add column if not exists "segment"');
    expect(sql).toContain(
      '(jsonb_populate_record(null::"better_supabase"."companies", save_company.attrs))."segment"',
    );
  });

  it("uses configured lifecycle stages and watches with notifications", () => {
    const sql = sqlOf({ personLifecycles: ["new", "known"] }, [
      "notifications",
    ]);

    expect(sql).toContain("'{new,known}'::text[]");
    expect(sql).toContain("notification_subscriptions");
  });

  it("rejects an invalid lifecycle list", () => {
    expect(() => sqlOf({ companyLifecycles: ["Lead"] })).toThrow(
      /lowercase names/,
    );
    expect(() => sqlOf({ companyLifecycles: [] })).toThrow(/non-empty/);
  });
});

describe("parties module, custom mode", () => {
  it("renders no tables or functions", () => {
    const sql = renderModules(["parties"], {
      modules: { parties: { mode: "custom" } },
    })
      .filter((file) => file.module === "parties")
      .map((file) => file.contents)
      .join("");

    expect(sql).not.toContain("save_company");
  });
});

describe("parties module with the inbox", () => {
  it("links people to inbox contacts only when the inbox is installed", () => {
    const sql = sqlOf({}, ["inbox"]);
    expect(sql).toContain(
      'create table if not exists "better_supabase"."person_inbox_contacts"',
    );
    expect(sql).toContain("person_for_inbox_contact");
    expect(sqlOf()).not.toContain("person_inbox_contacts");
  });
});
