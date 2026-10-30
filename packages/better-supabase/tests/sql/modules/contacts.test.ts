import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (
  options: Record<string, unknown> = {},
  extra: readonly string[] = [],
): string =>
  renderBlocks(["contacts", ...extra], { modules: { contacts: { options } } })
    .filter((file) => file.module === "contacts")
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
    const sql = renderBlocks(["contacts"], {
      modules: { contacts: { mode: "custom" } },
    })
      .filter((file) => file.module === "contacts")
      .map((file) => file.contents)
      .join("");

    expect(sql).not.toContain("save_company");
  });
});

describe("parties module identities", () => {
  it("keeps one person per address on a channel", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."person_identities"',
    );
    expect(sql).toContain('unique ("tenant_id", "channel", "address")');
    expect(sql).toContain(
      "create index if not exists person_identities_person_idx",
    );
    expect(sql).toContain('"avatar_url" text,');
  });

  it("resolves people for other blocks only", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      'revoke execute on function "better_supabase"."resolve_person"(uuid, jsonb) from public, anon, authenticated;',
    );
    expect(sql).toContain('"better_supabase"."find_person_by_identity"');
    expect(sql).toContain("PARTY_IDENTITY_TAKEN");
  });
});

describe("parties module with the inbox", () => {
  it("makes a conversation's contact a person only when the inbox is installed", () => {
    const sql = sqlOf({}, ["inbox"]);
    expect(sql).toContain(
      `alter table "better_supabase"."inbox_conversations" add constraint "inbox_conversations_contact_id_fkey"\n  foreign key ("contact_id") references "better_supabase"."people" ("id") on delete cascade;`,
    );
    expect(sql).toContain(
      `update "better_supabase"."inbox_conversations" x set "contact_id" = merge_people.keep`,
    );
    expect(sqlOf()).not.toContain("inbox_conversations");
    expect(sql).not.toContain("person_inbox_contacts");
  });
});
