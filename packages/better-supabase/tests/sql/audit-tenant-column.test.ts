import { describe, expect, it } from "vitest";

import { moduleBody } from "../../src/sql/render.ts";
import { ownTablesOf } from "../fixtures/own-tables.ts";

/** The audit module over the app's own log table, with `sql.tenantColumn` set. */
const appAudit = (
  options: Readonly<Record<string, unknown>>,
  blockTenantColumn = "org_id",
) => {
  const modules = {
    audit: { tables: { log: "public.activity_log" }, options },
  };

  return moduleBody("audit", {
    modules,
    ownTables: ownTablesOf(modules),
    blockTenantColumn,
  })!;
};

describe("the audit dynamic insert and sql.tenantColumn", () => {
  it("writes the configured tenant column, not the default", () => {
    const sql = appAudit({ metadataColumns: { ticket_id: "ticketId" } });

    expect(sql).toMatch(/entry_row := [^;]*'org_id'/su);
    expect(sql).not.toMatch(/entry_row := [^;]*'tenant_id'/su);
  });

  it("refuses a metadata column named like the configured tenant column", () => {
    expect(() => appAudit({ metadataColumns: { org_id: "org" } })).toThrow(
      /already fills it/u,
    );
  });
});
