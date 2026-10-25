import { describe, expect, it } from "vitest";

import type { BlockConfig } from "../../../src/config/blocks.ts";

import { moduleBody } from "../../../src/sql/render.ts";

const audit = (options: BlockConfig["options"] = {}) =>
  moduleBody("audit", { modules: { audit: { options } } })!;

describe("audit request_ip()", () => {
  it("reads the last x-forwarded-for hop by default", () => {
    expect(audit()).toContain(
      "reverse(split_part(reverse(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for'), ',', 1))",
    );
  });

  it("reads the header and hop ipHeader names", () => {
    expect(audit({ ipHeader: "X-Real-IP" })).toContain(
      "-- The client address from the x-real-ip header (the last hop), or null.",
    );
    expect(
      audit({ ipHeader: { name: "x-forwarded-for", hop: "first" } }),
    ).toContain(
      "return nullif(trim(split_part(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ',', 1)), '')::inet;",
    );
  });

  it("refuses a header that isn't a header name or a bad hop", () => {
    expect(() => audit({ ipHeader: "x-ip'; drop" })).toThrow(
      /is not a header name/,
    );
    expect(() => audit({ ipHeader: { name: "x-ip", hop: "middle" } })).toThrow(
      /hop must be "first" or "last"/,
    );
  });
});

describe("audit staff actor kind", () => {
  it("records staff for a caller carrying staffClaim", () => {
    const sql = audit({ staffClaim: "app_metadata.platform_role" });

    expect(sql).toContain(
      "when auth.jwt() #>> '{app_metadata,platform_role}' is not null then 'staff'",
    );
    expect(audit()).not.toContain("'staff'");
  });

  it("refuses a claim that isn't a dotted path", () => {
    expect(() => audit({ staffClaim: "a}' or true" })).toThrow(
      /dotted claim path/,
    );
  });
});

describe("audit subjectColumns", () => {
  it("adds a guarded generated column and a partial index", () => {
    const sql = audit({
      subjectColumns: {
        job_id: { type: "uuid" },
        ticket: { type: "bigint", from: "ticket_no" },
      },
    });

    expect(sql).toContain(
      `alter table "better_supabase"."audit_events" add column if not exists "job_id" uuid generated always as (case when coalesce("new_record" ->> 'job_id', "old_record" ->> 'job_id', "metadata" ->> 'job_id') ~ '^[0-9a-fA-F]{8}-`,
    );
    expect(sql).toContain(
      `create index if not exists "audit_events_job_id_idx" on "better_supabase"."audit_events" ("job_id") where "job_id" is not null;`,
    );
    expect(sql).toContain(
      `case when coalesce("new_record" ->> 'ticket_no', "old_record" ->> 'ticket_no', "metadata" ->> 'ticket_no') ~ '^-?[0-9]{1,18}$' then`,
    );
  });

  it("refuses a bad name, a taken name or an unknown type", () => {
    expect(() =>
      audit({ subjectColumns: { "Job Id": { type: "uuid" } } }),
    ).toThrow(/is not a valid column name/);
    expect(() =>
      audit({ subjectColumns: { actor_id: { type: "uuid" } } }),
    ).toThrow(/already a column/);
    expect(() =>
      audit({ subjectColumns: { job_id: { type: "timestamptz" } } }),
    ).toThrow(/type must be one of text, uuid, bigint/);
  });
});
