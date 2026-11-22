import { describe, expect, it } from "vitest";

import {
  moduleBody,
  SQL_MODULES,
  moduleContext,
} from "../../../src/sql/index.ts";
import { taxRateKeyUpgrade } from "../../../src/sql/modules/tax-tables.ts";

describe("tax rates and codes", () => {
  const sql = moduleBody("tax")!;

  it("makes a code unique by id and tenant", () => {
    expect(sql).toContain('create unique index "tax_codes_id_tenant_key"');
    expect(sql).toContain('("id", "tenant_id");');
  });

  it("references the code together with the tenant", () => {
    expect(sql).toMatch(
      /constraint "tax_rates_tenant_code_fkey" foreign key \("tax_code_id", "tenant_id"\) references \S+ \("id", "tenant_id"\) on delete cascade/,
    );
  });

  it("bumps the version and upgrades version 1 without failing on old rows", () => {
    const tax = SQL_MODULES["tax"]!;
    const [step] = tax.upgrades!;

    expect(tax.version).toBe(2);
    expect(step!.from).toBe(1);
    expect(taxRateKeyUpgrade(moduleContext("tax", {}))).toMatch(/not valid/);
  });
});
