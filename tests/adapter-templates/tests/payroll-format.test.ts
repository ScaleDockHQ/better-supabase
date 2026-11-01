import "temporal-polyfill/global";
import type { PayrollRun } from "better-supabase/blocks/payroll-export";

import { describe, expect, it } from "vitest";

import { examplePayrollFormat } from "../src/payroll-format.ts";

const AT = Temporal.Instant.from("2026-11-01T10:00:00Z");

const run: PayrollRun = {
  id: "r1",
  organizationId: "org-1",
  periodFrom: Temporal.PlainDate.from("2026-10-01"),
  periodTo: Temporal.PlainDate.from("2026-10-31"),
  status: "draft",
  createdAt: AT,
  updatedAt: AT,
  lineCount: 2,
  lines: [
    {
      id: "l1",
      employeeId: "e1",
      kind: "worked",
      paid: true,
      unit: "hours",
      quantity: 160,
      sourceCount: 20,
    },
    {
      id: "l2",
      employeeId: "e1",
      kind: "leave",
      code: "unpaid",
      paid: false,
      unit: "days",
      quantity: 1,
      sourceCount: 1,
    },
  ],
};

describe("payroll export format", () => {
  it("targets API version 1 and names itself", () => {
    expect(examplePayrollFormat.apiVersion).toBe(1);
    expect(examplePayrollFormat.name).toBe("example-payroll");
  });

  it("renders only paid lines, as the same bytes every time", async () => {
    const first = await examplePayrollFormat.render(run);
    const second = await examplePayrollFormat.render(run);

    expect(first).toEqual(second);
    expect(first.filename).toBe("payroll-2026-10-01-2026-10-31.txt");
    expect(first.body).toBe("e1|worked|160.00|hours\n");
  });
});
