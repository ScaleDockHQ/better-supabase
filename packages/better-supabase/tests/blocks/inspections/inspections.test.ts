import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createInspections,
  inspectionFindingInputSchema,
  inspectionInputSchema,
  inspectionProgramInputSchema,
  inspectionsBlock,
} from "../../../src/blocks/inspections/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";
const ID = "00000000-0000-4000-8000-000000000001";

const PROGRAM = {
  id: "p1",
  organizationId: "org-1",
  name: "Audit programme 2027",
  periodStart: "2027-01-01",
  periodEnd: "2027-12-31",
  ownerId: "u1",
  status: "draft",
  notes: "ISO 9001 cycle",
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const INSPECTION = {
  id: "i1",
  organizationId: "org-1",
  programId: "p1",
  number: "AUD-2026-001",
  kind: "internal_audit",
  title: "Warehouse audit",
  scope: "Receiving and storage",
  criteria: "ISO 9001 8.5",
  auditee: { type: "site", id: "north" },
  leadId: "u1",
  plannedStart: "2026-11-02",
  plannedEnd: "2026-11-03",
  startedAt: AT,
  status: "in_progress",
  checklistFormId: "f1",
  checklistSubmissionId: "s1",
  createdAt: AT,
  updatedAt: AT,
  fields: { site: "north" },
};

const BARE = {
  id: "i2",
  organizationId: "org-1",
  number: "AUD-2026-002",
  kind: "supplier_audit",
  title: "Supplier visit",
  auditee: null,
  status: "closed",
  closedAt: AT,
  createdAt: AT,
  updatedAt: AT,
  fields: { site: "south" },
};

const FINDING = {
  id: "fi1",
  organizationId: "org-1",
  inspectionId: "i1",
  number: 1,
  type: "major_nonconformity",
  title: "Unlabelled stock",
  description: "Pallets without labels",
  clause: "ISO 9001 8.5.2",
  controlId: "c1",
  evidence: "Photo 12",
  caseId: null,
  needsCase: true,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const Fields = v.object({ site: v.picklist(["north", "south"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

const date = (value: string) => temporal().PlainDate.from(value);

describe("createInspections", () => {
  it("saves, approves, closes and lists programmes", async () => {
    const t = fieldsTransport({
      save_inspection_program: () => PROGRAM,
      approve_inspection_program: () => ({ ...PROGRAM, status: "approved" }),
      close_inspection_program: () => ({ ...PROGRAM, status: "closed" }),
      list_inspection_programs: () => [PROGRAM],
    });

    const inspections = createInspections({ transport: t, tenant: "org-1" });

    const saved = await inspections
      .saveProgram({
        name: "Audit programme 2027",
        periodStart: date("2027-01-01"),
        periodEnd: date("2027-12-31"),
      })
      .orThrow();

    const approved = await inspections.approveProgram("p1").orThrow();
    const closed = await inspections.closeProgram("p1").orThrow();
    const listed = await inspections.programs().orThrow();

    expect(saved.periodEnd.toString()).toBe("2027-12-31");
    expect(saved).toMatchObject({ ownerId: "u1", notes: "ISO 9001 cycle" });
    expect(saved.archivedAt).toBeUndefined();
    expect(approved.status).toBe("approved");
    expect(closed.status).toBe("closed");
    expect(listed).toHaveLength(1);
    expect(t.calls).toEqual([
      [
        "save_inspection_program",
        {
          tenant: "org-1",
          name: "Audit programme 2027",
          period_start: "2027-01-01",
          period_end: "2027-12-31",
          owner_id: null,
          notes: null,
          program_id: null,
        },
      ],
      ["approve_inspection_program", { program_id: "p1" }],
      ["close_inspection_program", { program_id: "p1" }],
      ["list_inspection_programs", { tenant: "org-1" }],
    ]);
  });

  it("schedules, updates and lists inspections with their extra fields", async () => {
    const t = fieldsTransport({
      schedule_inspection: () => INSPECTION,
      update_inspection: () => BARE,
      list_inspections: () => [INSPECTION, BARE],
    });

    const inspections = createInspections({
      transport: t,
      tenant: "org-1",
      fields: Fields,
    });

    const scheduled = await inspections
      .schedule({
        kind: "internal_audit",
        title: "Warehouse audit",
        plannedStart: date("2026-11-02"),
        members: [{ userId: "u2", role: "auditor" }],
        fields: { site: "north" },
      })
      .orThrow();

    const updated = await inspections
      .update("i2", { plannedEnd: null, title: "Supplier visit" })
      .orThrow();

    const listed = await inspections
      .list({
        status: "planned",
        from: date("2026-01-01"),
        auditee: { type: "site", id: "north" },
      })
      .orThrow();

    expect(scheduled).toMatchObject({
      number: "AUD-2026-001",
      auditee: { type: "site", id: "north" },
      checklistSubmissionId: "s1",
      fields: { site: "north" },
    });
    expect(scheduled.plannedStart?.toString()).toBe("2026-11-02");
    expect(updated.auditee).toBeUndefined();
    expect(updated.closedAt?.toString()).toBe(AT);
    expect(listed.map((row) => row.fields.site)).toEqual(["north", "south"]);
    expect(t.calls).toEqual([
      [
        "schedule_inspection",
        {
          tenant: "org-1",
          input: {
            kind: "internal_audit",
            title: "Warehouse audit",
            plannedStart: "2026-11-02",
            members: [{ userId: "u2", role: "auditor" }],
            fields: { site: "north" },
          },
        },
      ],
      [
        "update_inspection",
        {
          inspection_id: "i2",
          changes: { plannedEnd: null, title: "Supplier visit" },
        },
      ],
      [
        "list_inspections",
        {
          tenant: "org-1",
          filters: {
            status: "planned",
            from: "2026-01-01",
            auditeeType: "site",
            auditeeId: "north",
          },
        },
      ],
    ]);
  });

  it("runs an inspection from start to close", async () => {
    const t = fieldsTransport({
      set_inspection_members: () => INSPECTION,
      start_inspection: () => INSPECTION,
      save_inspection_checklist: () => ({ id: "s1" }),
      complete_inspection: () => ({ ...INSPECTION, status: "reporting" }),
      close_inspection: () => BARE,
      cancel_inspection: () => ({ ...BARE, status: "canceled" }),
      get_inspection: () => ({
        ...INSPECTION,
        members: [{ userId: "u1", role: "lead" }],
        findings: [FINDING],
        checklist: { formId: "f1", submissionId: "s1", status: "submitted" },
        assessedControls: [
          { id: "c1", title: "Stock labelling" },
          { id: "c2" },
        ],
      }),
    });

    const inspections = createInspections({ transport: t, tenant: "org-1" });

    await inspections
      .setMembers("i1", [{ userId: "u3", role: "observer" }])
      .orThrow();
    await inspections.start("i1").orThrow();

    const saved = await inspections
      .saveChecklist("i1", { q1: "yes" }, { draft: false })
      .orThrow();

    await inspections.saveChecklist("i1", { q1: "no" }).orThrow();

    const completed = await inspections
      .complete("i1", "Two findings")
      .orThrow();

    await inspections.complete("i1").orThrow();
    await inspections.close("i1").orThrow();
    const canceled = await inspections.cancel("i2").orThrow();
    const detail = await inspections.get("i1").orThrow();

    expect(saved).toEqual({ submissionId: "s1" });
    expect(completed.status).toBe("reporting");
    expect(canceled.status).toBe("canceled");
    expect(detail.members).toEqual([{ userId: "u1", role: "lead" }]);
    expect(detail.findings[0]).toMatchObject({ needsCase: true, number: 1 });
    expect(detail.checklist).toEqual({
      formId: "f1",
      submissionId: "s1",
      status: "submitted",
    });
    expect(detail.assessedControls).toEqual([
      { id: "c1", title: "Stock labelling" },
      { id: "c2" },
    ]);
    expect(t.calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "set_inspection_members",
        { inspection_id: "i1", members: [{ userId: "u3", role: "observer" }] },
      ],
      ["start_inspection", { inspection_id: "i1" }],
      [
        "save_inspection_checklist",
        { inspection_id: "i1", answers: { q1: "yes" }, draft: false },
      ],
      [
        "save_inspection_checklist",
        { inspection_id: "i1", answers: { q1: "no" }, draft: true },
      ],
      ["complete_inspection", { inspection_id: "i1", summary: "Two findings" }],
      ["complete_inspection", { inspection_id: "i1", summary: null }],
      ["close_inspection", { inspection_id: "i1" }],
      ["cancel_inspection", { inspection_id: "i2", reason: null }],
      ["get_inspection", { inspection_id: "i1" }],
    ]);
  });

  it("adds, changes, deletes and raises cases for findings", async () => {
    const t = fieldsTransport({
      add_inspection_finding: () => FINDING,
      update_inspection_finding: () => ({ ...FINDING, clause: null }),
      delete_inspection_finding: () => FINDING,
      raise_inspection_finding_case: () => ({ ...FINDING, caseId: "case-1" }),
    });

    const inspections = createInspections({ transport: t });

    const added = await inspections
      .addFinding("i1", { type: "major_nonconformity", title: "Unlabelled" })
      .orThrow();

    const changed = await inspections
      .updateFinding("fi1", { clause: null })
      .orThrow();

    await inspections.deleteFinding("fi1").orThrow();
    const raised = await inspections.raiseCase("fi1").orThrow();
    await inspections
      .raiseCase("fi1", { kind: "nonconformity", ownerId: "u2" })
      .orThrow();

    expect(added).toMatchObject({ controlId: "c1", evidence: "Photo 12" });
    expect(added.caseId).toBeUndefined();
    expect(changed.clause).toBeUndefined();
    expect(raised.caseId).toBe("case-1");
    expect(t.calls).toEqual([
      [
        "add_inspection_finding",
        {
          inspection_id: "i1",
          type: "major_nonconformity",
          title: "Unlabelled",
          description: null,
          clause: null,
          control_id: null,
          evidence: null,
        },
      ],
      [
        "update_inspection_finding",
        { finding_id: "fi1", changes: { clause: null } },
      ],
      ["delete_inspection_finding", { finding_id: "fi1" }],
      [
        "raise_inspection_finding_case",
        { finding_id: "fi1", kind: "finding", owner_id: null },
      ],
      [
        "raise_inspection_finding_case",
        { finding_id: "fi1", kind: "nonconformity", owner_id: "u2" },
      ],
    ]);
  });

  it("rejects a malformed row", async () => {
    const t = fieldsTransport({
      start_inspection: () => ({ ...INSPECTION, status: "pending" }),
      list_inspection_programs: () => [{ ...PROGRAM, periodStart: null }],
      get_inspection: () => ({
        ...INSPECTION,
        members: [{ userId: "u1", role: "boss" }],
        findings: [],
        assessedControls: [],
      }),
    });

    const inspections = createInspections({ transport: t, tenant: "org-1" });

    expect((await inspections.start("i1")).ok).toBe(false);
    expect((await inspections.programs()).ok).toBe(false);
    expect((await inspections.get("i1")).ok).toBe(false);
  });

  it("needs a tenant for the organization calls", async () => {
    const t = fieldsTransport({});

    const result = await createInspections({ transport: t }).list();

    expect(result.ok).toBe(false);
    expect(t.calls).toEqual([]);
  });

  it("runs the hooks", async () => {
    const seen: string[] = [];

    const inspections = createInspections({
      transport: fieldsTransport({ close_inspection: () => BARE }),
      hooks: {
        close: {
          after: () => {
            seen.push("close");
          },
        },
      },
    });

    await inspections.close("i2").orThrow();

    expect(seen).toEqual(["close"]);
  });
});

describe("inspections block", () => {
  it("names the block and validates the inputs", () => {
    expect(inspectionsBlock.name).toBe("inspections");
    expect(
      validate(inspectionInputSchema, { kind: "internal_audit", title: "A" })
        .issues,
    ).toBeUndefined();
    expect(
      validate(inspectionInputSchema, { kind: "", title: "A" }).issues,
    ).toBeDefined();
    expect(
      validate(inspectionProgramInputSchema, {
        name: "P",
        periodStart: date("2027-01-01"),
        periodEnd: date("2027-12-31"),
        programId: ID,
      }).issues,
    ).toBeUndefined();
    expect(
      validate(inspectionFindingInputSchema, {
        type: "observation",
        title: "Tidy",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(inspectionFindingInputSchema, { type: "observation", title: "" })
        .issues,
    ).toBeDefined();
  });
});
