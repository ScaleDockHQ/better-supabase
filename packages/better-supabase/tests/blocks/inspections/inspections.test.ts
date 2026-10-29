import { describe, expect, it } from "vitest";

import { createInspections } from "../../../src/blocks/inspections/index.ts";

const PROGRAM = {
  id: "p1",
  organizationId: "org",
  name: "2026 internal audits",
  periodStart: "2026-01-01",
  periodEnd: "2026-12-31",
  status: "draft",
};

const INSPECTION = {
  id: "i1",
  organizationId: "org",
  number: "AUD-2026-001",
  kind: "internal_audit",
  title: "Supplier audit",
  status: "planned",
};

const FINDING = {
  id: "f1",
  organizationId: "org",
  inspectionId: "i1",
  number: 1,
  type: "minor_nonconformity",
  title: "Missing record",
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args?: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);

      return Promise.resolve(results[fn]);
    },
  };
}

describe("createInspections", () => {
  it("schedules, runs and closes an inspection", async () => {
    const transport = fakeTransport({
      save_inspection_program: PROGRAM,
      list_inspection_programs: [PROGRAM],
      schedule_inspection: INSPECTION,
      start_inspection: { ...INSPECTION, status: "in_progress" },
      add_inspection_finding: FINDING,
      raise_inspection_finding_case: { id: "c1" },
      complete_inspection: { ...INSPECTION, status: "reporting" },
      close_inspection: { ...INSPECTION, status: "closed" },
      get_inspection: { ...INSPECTION, findings: [FINDING] },
      list_inspections: [INSPECTION],
      notify_due_inspections: 1,
    });

    const client = createInspections({ transport, schema: "app" });

    expect(
      (await client.saveProgram("org", {
        name: PROGRAM.name,
        periodStart: Temporal.PlainDate.from("2026-01-01"),
        periodEnd: Temporal.PlainDate.from("2026-12-31"),
      }).orThrow()).name,
    ).toBe(PROGRAM.name);
    expect(await client.programs("org").orThrow()).toHaveLength(1);
    expect(
      (await client.schedule("org", { title: "Supplier audit" }).orThrow())
        .number,
    ).toBe("AUD-2026-001");
    expect((await client.start("i1").orThrow()).status).toBe("in_progress");
    expect(
      (await client.addFinding("i1", {
        type: "minor_nonconformity",
        title: "Missing record",
      }).orThrow()).type,
    ).toBe("minor_nonconformity");
    expect(await client.raiseCase("f1").orThrow()).toEqual({ id: "c1" });
    expect((await client.complete("i1", "done").orThrow()).status).toBe(
      "reporting",
    );
    expect((await client.close("i1").orThrow()).status).toBe("closed");
    expect((await client.get("i1").orThrow()).findings).toHaveLength(1);
    expect(await client.list("org").orThrow()).toHaveLength(1);
    expect(await client.notifyDue().orThrow()).toBe(1);
  });
});
