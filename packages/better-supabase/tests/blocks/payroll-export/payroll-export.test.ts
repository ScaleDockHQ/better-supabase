import { describe, expect, it } from "vitest";

import {
  createPayrollExport,
  csvPayrollFormat,
  payrollExportBlock,
  payrollRunInputSchema,
} from "../../../src/blocks/payroll-export/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-11-01T08:00:00Z";

const LINE = {
  id: "l1",
  userId: "u1",
  employeeId: "e1",
  employeeName: "Ada; Lovelace",
  kind: "worked",
  paid: true,
  unit: "hours",
  quantity: 152.5,
  sourceCount: 19,
};

const RUN = {
  id: "r1",
  organizationId: "org-1",
  periodFrom: "2026-10-01",
  periodTo: "2026-10-31",
  label: "October",
  status: "draft",
  createdAt: AT,
  updatedAt: AT,
  lineCount: 2,
  lines: [
    LINE,
    {
      id: "l2",
      employeeId: "=cmd",
      kind: "leave",
      code: "vacation",
      paid: true,
      unit: "days",
      quantity: 2,
      sourceCount: 1,
    },
  ],
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createPayrollExport", () => {
  it("creates, lists, refreshes and deletes runs", async () => {
    const t = fieldsTransport({
      create_payroll_run: () => RUN,
      refresh_payroll_run: () => RUN,
      list_payroll_runs: () => [{ ...RUN, lines: undefined }],
      get_payroll_run: () => null,
      delete_payroll_run: () => null,
    });

    const payroll = createPayrollExport({ transport: t, tenant: "org-1" });
    const { PlainDate } = temporal();

    const created = await payroll
      .create({
        from: PlainDate.from("2026-10-01"),
        to: PlainDate.from("2026-10-31"),
        label: "October",
      })
      .orThrow();

    await payroll.refresh("r1").orThrow();
    const runs = await payroll.list().orThrow();
    const missing = await payroll.get("nope").orThrow();
    await payroll.delete("r1").orThrow();

    expect(created.periodTo.toString()).toBe("2026-10-31");
    expect(created.lines).toHaveLength(2);
    expect(created.lines[0]).toMatchObject({ quantity: 152.5, paid: true });
    expect(created.lines[1]?.userId).toBeUndefined();
    expect(runs[0]?.lineCount).toBe(2);
    expect(missing).toBeUndefined();
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "create_payroll_run",
      "refresh_payroll_run",
      "list_payroll_runs",
      "get_payroll_run",
      "delete_payroll_run",
    ]);
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      input: { from: "2026-10-01", to: "2026-10-31", label: "October" },
    });
  });

  it("renders the file, hashes it and locks the run", async () => {
    const t = fieldsTransport({
      get_payroll_run: () => RUN,
      mark_payroll_run_exported: () => ({
        ...RUN,
        status: "exported",
        format: "csv",
        exportedAt: AT,
      }),
    });

    const payroll = createPayrollExport({ transport: t, tenant: "org-1" });

    const result = await payroll
      .exportRun({ runId: "r1", format: csvPayrollFormat() })
      .orThrow();

    expect(result.file.filename).toBe("payroll-2026-10-01-2026-10-31.csv");
    expect(result.file.contentType).toBe("text/csv");
    expect(result.file.body.split("\r\n")).toEqual([
      "employee_id;user_id;employee_name;kind;code;paid;unit;quantity",
      'e1;u1;"Ada; Lovelace";worked;;yes;hours;152.50',
      "'=cmd;;;leave;vacation;yes;days;2.00",
      "",
    ]);
    expect(result.run.status).toBe("exported");

    const [fn, args] = t.calls[1] ?? [];
    expect(fn).toBe("mark_payroll_run_exported");
    expect(args).toMatchObject({ run_id: "r1", format: "csv" });
    expect(args?.["checksum"]).toMatch(/^[0-9a-f]{64}$/);
  });

  it("uses the delimiter and decimal separator it is given", async () => {
    const file = await csvPayrollFormat({
      delimiter: ",",
      decimal: ",",
      name: "comma",
    }).render({
      ...(await createPayrollExport({
        transport: fieldsTransport({ create_payroll_run: () => RUN }),
        tenant: "org-1",
      })
        .create({
          from: temporal().PlainDate.from("2026-10-01"),
          to: temporal().PlainDate.from("2026-10-31"),
        })
        .orThrow()),
    });

    expect(file.body).toContain('"152,50"');
  });

  it("reads every optional field of an exported run and its lines", async () => {
    const full = {
      ...RUN,
      status: "exported",
      format: "csv",
      checksum: "abc",
      exportedAt: AT,
      exportedBy: "u9",
      createdBy: "u8",
      lines: [{ ...LINE, code: "sick", employeeId: undefined }],
    };

    const payroll = createPayrollExport({
      transport: fieldsTransport({
        get_payroll_run: () => full,
        list_payroll_runs: () => [full],
      }),
      tenant: "org-1",
    });

    const run = await payroll.get("r1").orThrow();
    const [listed] = await payroll.list().orThrow();

    expect(run).toMatchObject({
      format: "csv",
      checksum: "abc",
      exportedBy: "u9",
      createdBy: "u8",
    });
    expect(run?.exportedAt?.toString()).toBe("2026-11-01T08:00:00Z");
    expect(run?.lines[0]).toMatchObject({ code: "sick", paid: true });
    expect(listed?.label).toBe("October");
  });

  it("renders the lines with the default separators", async () => {
    const file = await csvPayrollFormat().render({
      id: "r1",
      organizationId: "org-1",
      periodFrom: temporal().PlainDate.from("2026-10-01"),
      periodTo: temporal().PlainDate.from("2026-10-31"),
      status: "draft",
      createdAt: temporal().Instant.from(AT),
      updatedAt: temporal().Instant.from(AT),
      lineCount: 1,
      lines: [
        {
          id: "l",
          kind: "worked",
          paid: false,
          unit: "hours",
          quantity: 1.5,
          sourceCount: 1,
        },
      ],
    });

    expect(file.body).toContain(";no;hours;1.50");
  });

  it("fails for a run that does not exist and for a format of another version", async () => {
    const t = fieldsTransport({ get_payroll_run: () => null });
    const payroll = createPayrollExport({ transport: t, tenant: "org-1" });

    const missing = await payroll.exportRun({
      runId: "nope",
      format: csvPayrollFormat(),
    });

    expect(missing.ok).toBe(false);
    expect(missing.ok ? undefined : missing.error).toMatchObject({
      kind: "not_found",
      hint: "PAYROLL_RUN_NOT_FOUND",
    });

    const future = await payroll.exportRun({
      runId: "r1",
      format: {
        // SAFETY: a format built for a later API version.
        apiVersion: 2 as unknown as 1,
        name: "future",
        render: () => ({ filename: "f", contentType: "text/plain", body: "" }),
      },
    });

    expect(future.ok).toBe(false);
    expect(t.calls).toHaveLength(1);
  });

  it("rejects a malformed row", async () => {
    const t = fieldsTransport({
      list_payroll_runs: () => [{ ...RUN, status: "unknown" }],
    });

    const payroll = createPayrollExport({ transport: t, tenant: "org-1" });

    expect((await payroll.list()).ok).toBe(false);
  });

  it("runs the hooks", async () => {
    const seen: string[] = [];

    const payroll = createPayrollExport({
      transport: fieldsTransport({ list_payroll_runs: () => [] }),
      tenant: "org-1",
      hooks: { list: { after: () => void seen.push("list") } },
    });

    await payroll.list().orThrow();

    expect(seen).toEqual(["list"]);
  });
});

describe("payroll-export block", () => {
  it("names itself and validates the run input", () => {
    expect(payrollExportBlock.name).toBe("payroll-export");
    expect(
      validate(payrollRunInputSchema, {
        from: temporal().PlainDate.from("2026-10-01"),
        to: temporal().PlainDate.from("2026-10-31"),
      }).issues,
    ).toBeUndefined();
    expect(
      validate(payrollRunInputSchema, { from: "nope" }).issues,
    ).toBeDefined();
  });
});
