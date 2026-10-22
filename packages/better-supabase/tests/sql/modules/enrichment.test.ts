import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (blocks: Record<string, unknown> = {}): string =>
  renderBlocks(["enrichment", "contacts", "outbox"], {
    modules: { enrichment: {}, ...blocks },
    // SAFETY: a partial config; the renderer fills in the defaults.
  })
    .filter((file) => file.module === "enrichment")
    .map((file) => file.contents)
    .join("\n");

describe("enrichment module", () => {
  it("stores one result per record and provider, deleted with the record", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      '"company_id" uuid references "better_supabase"."companies" ("id") on delete cascade',
    );
    expect(sql).toContain('unique ("company_id", "provider")');
    expect(sql).toContain('unique ("person_id", "provider")');
    expect(sql).toContain(
      'check (num_nonnulls("company_id", "person_id") = 1)',
    );
  });

  it("fills only empty columns and leaves out a domain another company holds", () => {
    const sql = sqlOf();
    expect(sql).toContain('v_company."domain" is null and v_domain ~');
    expect(sql).toContain('v_person."title" is null');
    expect(sql).toContain("'party.enriched'");
  });

  it("names records by the parties block's renamed subject types", () => {
    const sql = sqlOf({
      contacts: { entities: { company: { name: "account" } } },
    });

    expect(sql).toContain("subject_type = 'account'");
  });

  it("lists due records to the service role only", () => {
    const sql = sqlOf();
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."enrichment_due"\(text, integer, interval, text\) to service_role/u,
    );
    expect(sql).toContain("interval '30 days'");
  });
});
