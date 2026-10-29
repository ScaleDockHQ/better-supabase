import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (): string =>
  renderBlocks(["outbox", "enrollments", "courses"], {})
    .filter((file) => file.module === "courses")
    .map((file) => file.contents)
    .join("\n");

describe("courses module", () => {
  it("expires a certificate the course's validForMonths after it is issued", () => {
    const sql = sqlOf();

    expect(sql).toContain(
      `alter table "better_supabase"."courses" add column if not exists "valid_for_months" integer check ("valid_for_months" is null or "valid_for_months" between 1 and 240);`,
    );
    expect(sql).toContain(
      `alter table "better_supabase"."course_certificates" add column if not exists "expires_at" timestamptz;`,
    );
    expect(sql).toContain(
      "now() + make_interval(months => v_enrollment.valid_for)",
    );
    expect(sql).toContain(
      "validForMonths must be a whole number of months from 1 to 240, or null",
    );
    expect(sql).toMatch(
      /'expired', coalesce\(\S+"expires_at" <= now\(\), false\)/u,
    );
    expect(sql).toMatch(/'expiresAt', v_certificate\."expires_at"/u);
  });
});
