import { describe, expect, it } from "vitest";

import { exampleAuditFileAdapter } from "../src/audit-file-adapter.ts";

const records = async (source: string): Promise<unknown[]> => {
  const found: unknown[] = [];

  for await (const record of exampleAuditFileAdapter.parse(source)) {
    found.push(record);
  }

  return found;
};

describe("audit file adapter", () => {
  it("targets API version 1 and names the format version it follows", () => {
    expect(exampleAuditFileAdapter.apiVersion).toBe(1);
    expect(exampleAuditFileAdapter.version).toBe("1");
  });

  it("reads one account per line", async () => {
    await expect(
      records('{"code":"1000","name":"Bank"}\n\n{"code":"2000","name":"Debt"}'),
    ).resolves.toEqual([
      {
        kind: "account",
        account: {
          code: "1000",
          name: "Bank",
          type: "asset",
          typeAssumed: true,
        },
      },
      {
        kind: "account",
        account: {
          code: "2000",
          name: "Debt",
          type: "asset",
          typeAssumed: true,
        },
      },
    ]);
  });

  it("rejects a line it cannot read", async () => {
    await expect(records('{"code":1}')).rejects.toThrow(/bad account line/);
  });

  it("writes the accounts back as the same lines", () => {
    const chunks = [
      ...exampleAuditFileAdapter.export({
        header: {
          fiscalYear: 2026,
          startDate: "2026-01-01",
          endDate: "2026-12-31",
          currency: "EUR",
          company: { name: "Acme" },
        },
        accounts: [{ code: "1000", name: "Bank", type: "asset" }],
        parties: [],
        taxCodes: [],
        journals: [],
        openingBalances: [],
        entries: [],
      }),
    ];

    expect(chunks.join("")).toBe('{"code":"1000","name":"Bank"}\n');
  });
});
