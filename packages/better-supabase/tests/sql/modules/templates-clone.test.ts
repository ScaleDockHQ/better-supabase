import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";

describe("clone tenant checks", () => {
  it.each(["invoices", "quotes", "tasks"] as const)(
    "%s clones check the target tenant before copying",
    (name) => {
      const sql = moduleBody(name, {});
      expect(sql).toContain("v_tenant");
      expect(sql).toContain("'tenantId'");
      expect(sql).toMatch(/v_tenant is distinct from v_src\./);
    },
  );
});
