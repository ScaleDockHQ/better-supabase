import { describe, expect, it } from "vitest";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
import { unnamedChecks } from "../unnamed-checks.ts";

const imports = unnamedChecks(moduleBody("imports", { modules: {} })!);

describe("import runner gaps", () => {
  it("sends a failed chunk back to pending with a new job when it is enqueued again", () => {
    expect(imports).toContain("v_failed integer[]");
    expect(imports).toMatch(
      /update "better_supabase"\."import_chunks" x set "status" = 'pending'[^;]*"status" = 'failed'/s,
    );
    expect(imports).toContain("':retry:'");
  });

  it("reads the records of a batch once", () => {
    expect(imports).toContain("v_known := coalesce(");
    expect(imports).toContain("v_slot = any (v_seen)");
    expect(imports).not.toMatch(
      /select \* into v_rec from "better_supabase"\."import_records" x\s+where x\."tenant_id" = v_run\."tenant_id"[^;]*;\s+v_found := found;\s+v_source_at/s,
    );
  });

  it("re-records dry run issues after the rollback and cleans them up on cancel", () => {
    expect(imports).toContain("coalesce(v_result -> 'conflictKeys'");
    expect(imports).toMatch(
      /delete from "better_supabase"\."import_chunks" x where x\."run_id" = cancel_import_run\.id/,
    );
  });

  it("takes the supplier of a supplier item from its supplier or customer ref", () => {
    const sql = renderBlocks(["catalog"], {})
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      "import_supplier_item.item -> 'resolved' ->> 'supplier'",
    );
    expect(sql).toContain(
      "import_supplier_item.item -> 'resolved' ->> 'customer'",
    );
  });
});
