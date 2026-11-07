import { describe, expect, it } from "vitest";

import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { renderBlocks } from "../app-columns.ts";
import { unnamedChecks } from "../unnamed-checks.ts";

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
    expect(unnamedChecks(sql)).toContain(
      'create table "better_supabase"."companies"',
    );
    expect(unnamedChecks(sql)).toContain(
      "create unique index people_email_idx",
    );
    expect(unnamedChecks(sql)).toContain(
      "create unique index company_people_primary_idx",
    );
    expect(unnamedChecks(sql)).toContain(
      "'{lead,prospect,customer,churned}'::text[]",
    );
    expect(unnamedChecks(sql)).not.toContain("notification_subscriptions");
  });

  it("adds extra columns to companies only and writes them on save", () => {
    const sql = sqlOf({ extraColumns: { segment: "text" } });
    expect(unnamedChecks(sql)).toContain(
      'alter table "better_supabase"."companies" add column "segment" text;',
    );
    expect(unnamedChecks(sql)).not.toContain('"people" add column "segment"');
    expect(unnamedChecks(sql)).toContain(
      '(jsonb_populate_record(null::"better_supabase"."companies", save_company.attrs))."segment"',
    );
  });

  it("uses configured lifecycle stages and watches with notifications", () => {
    const sql = sqlOf({ personLifecycles: ["new", "known"] }, [
      "notifications",
    ]);

    expect(unnamedChecks(sql)).toContain("'{new,known}'::text[]");
    expect(unnamedChecks(sql)).toContain("notification_subscriptions");
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

    expect(unnamedChecks(sql)).not.toContain("save_company");
  });
});

describe("parties module identities", () => {
  it("keeps one person per address on a channel", () => {
    const sql = sqlOf();
    expect(unnamedChecks(sql)).toContain(
      'create table "better_supabase"."person_identities"',
    );
    expect(unnamedChecks(sql)).toContain(
      'unique ("tenant_id", "channel", "address")',
    );
    expect(unnamedChecks(sql)).toContain(
      "create index person_identities_person_idx",
    );
    expect(unnamedChecks(sql)).toContain('"avatar_url" text,');
  });

  it("resolves people for other blocks only", () => {
    const sql = sqlOf();
    expect(unnamedChecks(sql)).toContain(
      'revoke execute on function "better_supabase"."resolve_person"(uuid, jsonb) from public, anon, authenticated;',
    );
    expect(unnamedChecks(sql)).toContain(
      '"better_supabase"."find_person_by_identity"',
    );
    expect(unnamedChecks(sql)).toContain("PARTY_IDENTITY_TAKEN");
  });

  it("grants resolve_person to service_role, and upgrades version 2", () => {
    const grant =
      'grant execute on function "better_supabase"."resolve_person"(uuid, jsonb) to service_role;';

    expect(sqlOf()).toContain(grant);

    const [plan] = upgradePlan([{ module: "contacts", version: 2 }]);
    expect(plan?.to).toBe(3);
    expect(plan?.steps.map((step) => step.sql)).toContain(grant);
  });
});

describe("parties module with the inbox", () => {
  it("makes a conversation's contact a person only when the inbox is installed", () => {
    const sql = sqlOf({}, ["inbox"]);
    expect(unnamedChecks(sql)).toContain(
      `alter table "better_supabase"."inbox_conversations" add constraint "inbox_conversations_contact_id_fkey"\n  foreign key ("contact_id") references "better_supabase"."people" ("id") on delete cascade;`,
    );
    expect(unnamedChecks(sql)).toContain(
      `update "better_supabase"."inbox_conversations" x set "contact_id" = merge_people.keep`,
    );
    expect(sqlOf()).not.toContain("inbox_conversations");
    expect(unnamedChecks(sql)).not.toContain("person_inbox_contacts");
  });
});

describe("parties module roles and suppliers", () => {
  it("adds the role and terms columns to companies and people", () => {
    const sql = sqlOf();
    expect(
      sql.match(/"roles" text\[\] not null default '\{\}'::text\[\],/g),
    ).toHaveLength(2);

    for (const table of ["companies", "people"]) {
      expect(unnamedChecks(sql)).not.toContain(
        `alter table "better_supabase"."${table}" add column if not exists "roles"`,
      );
      expect(unnamedChecks(sql)).toContain(
        `create index ${table}_roles_idx on "better_supabase"."${table}" using gin ("roles");`,
      );
      expect(unnamedChecks(sql)).toContain(
        `create index ${table}_supplier_status_idx`,
      );
    }

    expect(unnamedChecks(sql)).toContain(
      `"supplier_status" text check ("supplier_status" in ('approved', 'conditional', 'blocked'))`,
    );
    expect(unnamedChecks(sql)).toContain(
      `"credit_limit" bigint check ("credit_limit" >= 0 and num_nulls("credit_limit", "credit_currency") <> 1)`,
    );
    expect(unnamedChecks(sql)).toContain(
      "'credit_limit', x.\"credit_limit\"::text",
    );
    expect(unnamedChecks(sql)).toContain("hint = 'PARTY_TERMS_INVALID'");
  });

  it("sets roles from options.roles and the status behind its own permission", () => {
    const sql = sqlOf({ roles: ["supplier", "carrier"] });
    expect(unnamedChecks(sql)).toContain(
      '"better_supabase"."set_party_roles"(party uuid, roles text[])',
    );
    expect(unnamedChecks(sql)).toContain(
      "v_roles <@ '{supplier,carrier}'::text[]",
    );
    expect(unnamedChecks(sql)).toContain("'contacts.approve_supplier'");
    expect(unnamedChecks(sql)).toContain(
      "hint = 'PARTY_SUPPLIER_STATUS_INVALID'",
    );
    expect(unnamedChecks(sql)).toContain('list_people.role = any (x."roles")');
  });

  it("refuses roles that aren't lowercase names", () => {
    expect(() => sqlOf({ roles: [] })).toThrow(/options\.roles/);
    expect(() => sqlOf({ roles: ["Supplier"] })).toThrow(/options\.roles/);
  });

  it("records the status change when the outbox is installed", () => {
    const sql = sqlOf({}, ["outbox", "audit"]);

    for (const kind of ["company", "person"]) {
      expect(unnamedChecks(sql)).toContain(
        `emit_event('${kind}.supplier_status_changed'`,
      );
      expect(unnamedChecks(sql)).toContain(
        `event_type => '${kind}.supplier_status_changed'`,
      );
    }
  });

  it("derives a status from qualifications only when they are installed", () => {
    expect(sqlOf()).not.toContain("supplier_status_from_qualifications");
    const sql = sqlOf({}, ["qualifications"]);
    expect(unnamedChecks(sql)).toContain(
      `"better_supabase"."qualification_gaps"(v_tenant, 'company', jsonb_build_object('holderId', supplier_status_from_qualifications.party::text))`,
    );
    expect(unnamedChecks(sql)).toContain("in ('missing', 'expired')");
  });
});

describe("contacts payment terms and delivery", () => {
  const sql = sqlOf();

  it("renders the terms tables, the resolver and both import targets", () => {
    expect(unnamedChecks(sql)).toContain("payment_terms");
    expect(unnamedChecks(sql)).toContain("resolve_payment_terms");
    expect(unnamedChecks(sql)).toContain("import_payment_term");
    expect(unnamedChecks(sql)).toContain("import_document_delivery_preference");
    expect(unnamedChecks(sql)).toContain("DELIVERY_PREFERENCE_INVALID");
  });

  it("keeps the resolver out of reach of API roles", () => {
    expect(unnamedChecks(sql)).toMatch(
      /revoke execute on function [^\n]*resolve_payment_terms[^\n]* from public, anon, authenticated/,
    );
  });
});
