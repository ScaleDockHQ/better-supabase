import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";

const audit = (options: Record<string, unknown>): string =>
  renderBlocks(["audit"], { modules: { audit: { options } } }).find((file) =>
    file.path.includes("audit"),
  )!.contents;

describe("convert_audit_log_to_partitioned", () => {
  it("is written only for a partitioned log", () => {
    expect(audit({})).not.toContain("convert_audit_log_to_partitioned");

    const sql = audit({ partitioned: true });
    expect(sql).toContain(
      'create or replace procedure "better_supabase"."convert_audit_log_to_partitioned"',
    );
  });

  it("copies in committed batches, then swaps under a lock that leaves reads open", () => {
    const sql = audit({ partitioned: true });
    expect(sql).toContain("commit;");
    expect(sql).toContain("in exclusive mode");
    expect(sql).not.toContain("access exclusive");
    expect(sql).toContain("_unpartitioned");
  });

  it("adds occurred_at to the unique idempotency index", () => {
    expect(audit({ partitioned: true })).toContain(", occurred_at)");
  });

  it("can only be called by the service role", () => {
    expect(audit({ partitioned: true })).toMatch(
      /revoke execute on procedure [^;]+ from public, anon, authenticated;\ngrant execute on procedure [^;]+ to service_role;/,
    );
  });
});
