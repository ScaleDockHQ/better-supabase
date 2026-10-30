import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createInspections } from "../../src/blocks/inspections/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "pipelines",
  "numbering",
  "relations",
  "tasks",
  "cases",
  "forms",
  "compliance",
  "inspections",
];

const LAYOUT = {
  modules: {
    permissions: {
      roles: { owner: ["*"], auditor: ["inspections.write"], member: [] },
    },
  },
};

const CHECKLIST = {
  steps: [
    {
      key: "storage",
      fields: [
        {
          key: "labelled",
          label: "Is all stock labelled?",
          type: "bool",
          required: true,
        },
      ],
    },
  ],
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("inspections", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("runs an audit from programme to a closed inspection with a case per finding", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const auditor = await s.user("auditor");
      const outsider = await s.user("auditor2");
      await s.install(MODULES, LAYOUT);
      const org = await s.organization(owner, { auditor, auditor2: outsider });

      const inspections = createInspections({
        transport: sqlTransport(s.sql),
        tenant: org,
      });

      await s.asRole(owner);

      const form = await s.value<{ id: string }>(
        "better_supabase.create_form($1, 'warehouse-checklist', 'Warehouse checklist')",
        [org],
      );

      await s.value("better_supabase.publish_form_version($1, $2)", [
        form.id,
        CHECKLIST,
      ]);
      await s.value("better_supabase.update_form($1, null, null, 'open')", [
        form.id,
      ]);

      const framework = await s.value<{ id: string }>(
        "better_supabase.save_control_framework($1, 'iso9001', 'ISO 9001')",
        [org],
      );

      const control = await s.value<{ id: string }>(
        "better_supabase.save_control($1, '8.5.2', 'Identification and traceability')",
        [framework.id],
      );

      const programme = await inspections
        .saveProgram({
          name: "Audit programme 2027",
          periodStart: Temporal.PlainDate.from("2027-01-01"),
          periodEnd: Temporal.PlainDate.from("2027-12-31"),
        })
        .orThrow();

      expect(
        (await inspections.approveProgram(programme.id).orThrow()).status,
      ).toBe("approved");

      const audit = await inspections
        .schedule({
          programId: programme.id,
          kind: "internal_audit",
          title: "Warehouse audit",
          leadId: owner.id,
          checklistFormId: form.id,
          plannedStart: Temporal.PlainDate.from("2027-02-01"),
          members: [{ userId: auditor.id, role: "auditor" }],
        })
        .orThrow();

      expect(audit).toMatchObject({ status: "planned", leadId: owner.id });
      expect(audit.number).toMatch(/^AUD-/);
      expect(
        await inspections
          .schedule({ kind: "astrology", title: "Odd" })
          .then(hint),
      ).toBe("INSPECTION_KIND_UNKNOWN");

      await s.asRole(outsider);
      expect(await inspections.start(audit.id).then(hint)).toBe(
        "INSPECTION_FORBIDDEN",
      );

      await s.asRole(auditor);
      await inspections.start(audit.id).orThrow();

      const labels = await inspections
        .addFinding(audit.id, {
          type: "major_nonconformity",
          title: "Unlabelled stock",
          clause: "ISO 9001 8.5.2",
          controlId: control.id,
        })
        .orThrow();

      const tidy = await inspections
        .addFinding(audit.id, { type: "positive", title: "Tidy aisles" })
        .orThrow();

      expect(labels).toMatchObject({ number: 1, needsCase: true });
      expect(tidy).toMatchObject({ number: 2, needsCase: false });
      expect(await inspections.complete(audit.id).then(hint)).toBe(
        "INSPECTION_FORBIDDEN",
      );

      await s.asRole(owner);
      expect(await inspections.complete(audit.id).then(hint)).toBe(
        "INSPECTION_CHECKLIST_INCOMPLETE",
      );

      await s.asRole(auditor);
      await inspections
        .saveChecklist(audit.id, { labelled: false }, { draft: false })
        .orThrow();

      await s.asRole(owner);
      expect(
        (await inspections.complete(audit.id, "One major").orThrow()).status,
      ).toBe("reporting");

      await s.asRole(outsider);
      expect(await inspections.get(audit.id).then(hint)).toBe(
        "INSPECTION_NOT_FOUND",
      );
      expect(await inspections.list().orThrow()).toEqual([]);

      await s.asRole(owner);
      expect(await inspections.close(audit.id).then(hint)).toBe(
        "INSPECTION_FINDINGS_OPEN",
      );

      const raised = await inspections.raiseCase(labels.id).orThrow();

      expect(raised.caseId).toBeDefined();
      expect(await inspections.deleteFinding(labels.id).then(hint)).toBe(
        "INSPECTION_FINDING_HAS_CASE",
      );

      const detail = await inspections.get(audit.id).orThrow();

      expect(detail.checklist).toMatchObject({
        formId: form.id,
        status: "submitted",
      });
      expect(detail.assessedControls.map((row) => row.id)).toEqual([
        control.id,
      ]);
      expect(detail.members.map((member) => member.role)).toEqual([
        "lead",
        "auditor",
      ]);
      expect((await inspections.close(audit.id).orThrow()).status).toBe(
        "closed",
      );

      await s.service();

      const kase = await s.value<{ number: string; title: string }>(
        "(select to_jsonb(c) from better_supabase.cases c where c.id = $1)",
        [raised.caseId],
      );

      expect(kase.title).toBe(`${audit.number}: Unlabelled stock`);
      expect(kase.number).toMatch(/^FND-/);

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'inspection%'",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "inspection_program.created",
          "inspection_program.approved",
          "inspection.scheduled",
          "inspection.started",
          "inspection_finding.created",
          "inspection.completed",
          "inspection_finding.case_raised",
          "inspection.closed",
        ]),
      );
    } finally {
      await s.close();
    }
  });

  it("refuses raising a case without the cases block", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install(
        MODULES.filter((name) => name !== "cases"),
        LAYOUT,
      );
      const org = await s.organization(owner);

      const inspections = createInspections({
        transport: sqlTransport(s.sql),
        tenant: org,
      });

      await s.asRole(owner);

      const audit = await inspections
        .schedule({ kind: "supplier_audit", title: "Supplier visit" })
        .orThrow();

      await inspections.start(audit.id).orThrow();

      const finding = await inspections
        .addFinding(audit.id, { type: "minor_nonconformity", title: "No CoC" })
        .orThrow();

      expect(await inspections.raiseCase(finding.id).then(hint)).toBe(
        "INSPECTION_CASES_NOT_INSTALLED",
      );
    } finally {
      await s.close();
    }
  });
});
