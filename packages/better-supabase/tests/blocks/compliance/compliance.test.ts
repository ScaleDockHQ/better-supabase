import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  controlEvidenceInputSchema,
  controlFrameworkInputSchema,
  controlInputSchema,
  complianceBlock,
  createCompliance,
  evidenceTaskInputSchema,
  policyInputSchema,
} from "../../../src/blocks/compliance/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";
const ID = "00000000-0000-4000-8000-000000000001";

const FRAMEWORK = {
  id: "f1",
  organizationId: "org-1",
  key: "soc2",
  name: "SOC 2",
  kind: "standard",
  version: "2017",
  description: "Trust services criteria",
  createdAt: AT,
  updatedAt: AT,
};

const BARE_FRAMEWORK = {
  id: "f2",
  organizationId: "org-1",
  key: "iso",
  name: "ISO 27001",
  createdAt: AT,
  updatedAt: AT,
};

const CONTROL = {
  id: "c1",
  organizationId: "org-1",
  frameworkId: "f1",
  code: "CC6.1",
  title: "Logical access",
  description: "Access is restricted",
  ownerId: "u1",
  applicable: true,
  source: "GDPR article 30",
  jurisdiction: "EU",
  status: "passing",
  createdAt: AT,
  updatedAt: AT,
  fields: { tier: "high" },
};

const BARE_CONTROL = {
  id: "c2",
  organizationId: "org-1",
  frameworkId: "f1",
  code: "CC7.1",
  title: "Monitoring",
  applicable: false,
  status: "not_applicable",
  createdAt: AT,
  updatedAt: AT,
};

const EVIDENCE = {
  id: "e1",
  organizationId: "org-1",
  controlId: "c1",
  evidenceTaskId: "t1",
  attachmentId: "a1",
  note: "Access review export",
  collectedBy: "u1",
  collectedAt: AT,
  validUntil: "2027-01-20",
  valid: true,
};

const BARE_EVIDENCE = {
  id: "e2",
  organizationId: "org-1",
  controlId: "c1",
  collectedAt: AT,
  validUntil: null,
  valid: false,
};

const TASK = {
  id: "t1",
  organizationId: "org-1",
  controlId: "c1",
  title: "Quarterly access review",
  assigneeId: "u1",
  intervalDays: 90,
  dueOn: "2026-10-01",
  lastCollectedAt: AT,
  active: true,
  overdue: true,
  controlCode: "CC6.1",
  controlTitle: "Logical access",
  createdAt: AT,
  updatedAt: AT,
};

const BARE_TASK = {
  id: "t2",
  organizationId: "org-1",
  controlId: "c1",
  title: "Pen test",
  intervalDays: "365",
  dueOn: "2027-01-01",
  active: false,
  overdue: false,
  createdAt: AT,
  updatedAt: AT,
};

const POLICY = {
  id: "p1",
  organizationId: "org-1",
  key: "security",
  title: "Information security policy",
  ownerId: "u1",
  requiresAcknowledgement: true,
  versionId: "v1",
  versionNumber: 2,
  publishedAt: AT,
  archivedAt: AT,
  acknowledgedAt: AT,
  acknowledgedCount: 3,
  memberCount: "4",
  createdAt: AT,
  updatedAt: AT,
};

const BARE_POLICY = {
  id: "p2",
  organizationId: "org-1",
  key: "travel",
  title: "Travel policy",
  requiresAcknowledgement: false,
  versionNumber: null,
  acknowledgedCount: 0,
  memberCount: 0,
  createdAt: AT,
  updatedAt: AT,
};

const Fields = v.object({ tier: v.picklist(["high", "low"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createCompliance", () => {
  it("saves and lists frameworks", async () => {
    const t = fieldsTransport({
      save_control_framework: () => FRAMEWORK,
      list_control_frameworks: () => [FRAMEWORK, BARE_FRAMEWORK],
    });

    const controls = createCompliance({ transport: t });

    const saved = await controls
      .saveFramework("org-1", {
        key: "soc2",
        name: "SOC 2",
        version: "2017",
        description: "Trust services criteria",
      })
      .orThrow();

    await controls
      .saveFramework("org-1", { key: "iso", name: "ISO", kind: "legal" })
      .orThrow();

    const [, bare] = await controls.frameworks("org-1").orThrow();

    expect(saved).toMatchObject({
      key: "soc2",
      kind: "standard",
      version: "2017",
    });
    expect(bare?.kind).toBe("standard");
    expect(Object.keys(bare ?? {}).toSorted()).toEqual([
      "createdAt",
      "id",
      "key",
      "kind",
      "name",
      "organizationId",
      "updatedAt",
    ]);
    expect(t.calls).toEqual([
      [
        "save_control_framework",
        {
          tenant: "org-1",
          key: "soc2",
          name: "SOC 2",
          version: "2017",
          description: "Trust services criteria",
          kind: "standard",
        },
      ],
      [
        "save_control_framework",
        {
          tenant: "org-1",
          key: "iso",
          name: "ISO",
          version: null,
          description: null,
          kind: "legal",
        },
      ],
      ["list_control_frameworks", { tenant: "org-1" }],
    ]);
  });

  it("saves a control with its extra fields and checks them", async () => {
    const t = fieldsTransport({ save_control: () => CONTROL });
    const controls = createCompliance({ transport: t, fields: Fields });

    const saved = await controls
      .saveControl({
        frameworkId: "f1",
        code: "CC6.1",
        title: "Logical access",
        description: "Access is restricted",
        ownerId: "u1",
        applicable: false,
        controlId: "c1",
        source: "GDPR article 30",
        jurisdiction: "EU",
        fields: { tier: "high" },
      })
      .orThrow();

    await controls
      .saveControl({ frameworkId: "f1", code: "CC6.2", title: "Keys" })
      .orThrow();

    const refused = await controls.saveControl({
      frameworkId: "f1",
      code: "CC6.3",
      title: "Bad",
      // SAFETY: a value the schema refuses, to prove the client checks it.
      fields: { tier: "mid" } as unknown as { tier: "high" },
    });

    expect(saved.fields.tier).toBe("high");
    expect(saved).toMatchObject({
      source: "GDPR article 30",
      jurisdiction: "EU",
    });
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(t.calls).toEqual([
      [
        "save_control",
        {
          framework_id: "f1",
          code: "CC6.1",
          title: "Logical access",
          description: "Access is restricted",
          owner_id: "u1",
          applicable: false,
          control_id: "c1",
          source: "GDPR article 30",
          jurisdiction: "EU",
          fields: { tier: "high" },
        },
      ],
      [
        "save_control",
        {
          framework_id: "f1",
          code: "CC6.2",
          title: "Keys",
          description: null,
          owner_id: null,
          applicable: true,
          control_id: null,
          source: null,
          jurisdiction: null,
        },
      ],
    ]);
  });

  it("reads a control with its evidence and tasks", async () => {
    const t = fieldsTransport({
      get_control: (args) =>
        args["control_id"] === "c1"
          ? { ...CONTROL, evidence: [EVIDENCE, BARE_EVIDENCE], tasks: [TASK] }
          : BARE_CONTROL,
    });

    const controls = createCompliance({ transport: t });

    const detail = await controls.getControl("c1").orThrow();
    const bare = await controls.getControl("c2").orThrow();

    expect(detail.evidence.map((item) => item.id)).toEqual(["e1", "e2"]);
    expect(detail.evidence[0]).toMatchObject({
      evidenceTaskId: "t1",
      attachmentId: "a1",
      note: "Access review export",
      collectedBy: "u1",
      valid: true,
    });
    expect(detail.evidence[0]?.validUntil?.toString()).toBe("2027-01-20");
    expect(Object.keys(detail.evidence[1] ?? {}).toSorted()).toEqual([
      "collectedAt",
      "controlId",
      "id",
      "organizationId",
      "valid",
    ]);
    expect(detail.tasks[0]).toMatchObject({
      assigneeId: "u1",
      controlCode: "CC6.1",
      controlTitle: "Logical access",
      overdue: true,
    });
    expect(bare).toMatchObject({
      applicable: false,
      status: "not_applicable",
      evidence: [],
      tasks: [],
      fields: {},
    });
    expect(bare).not.toHaveProperty("ownerId");
  });

  it("lists controls with and without filters", async () => {
    const t = fieldsTransport({ list_controls: () => [CONTROL, BARE_CONTROL] });
    const controls = createCompliance({ transport: t });

    expect(await controls.controls("org-1").orThrow()).toHaveLength(2);
    await controls
      .controls("org-1", {
        frameworkId: "f1",
        status: "failing",
        ownerId: "u1",
        pageSize: 20,
      })
      .orThrow();

    expect(t.calls).toEqual([
      [
        "list_controls",
        {
          tenant: "org-1",
          framework_id: null,
          status: null,
          owner_id: null,
          page_size: null,
        },
      ],
      [
        "list_controls",
        {
          tenant: "org-1",
          framework_id: "f1",
          status: "failing",
          owner_id: "u1",
          page_size: 20,
        },
      ],
    ]);
  });

  it("adds and removes evidence", async () => {
    const t = fieldsTransport({
      add_control_evidence: () => EVIDENCE,
      remove_control_evidence: () => BARE_EVIDENCE,
    });

    const controls = createCompliance({ transport: t });

    await controls
      .addEvidence("c1", {
        attachmentId: "a1",
        note: "Export",
        validUntil: Temporal.PlainDate.from("2027-01-20"),
        evidenceTaskId: "t1",
      })
      .orThrow();
    await controls.addEvidence("c1", { note: "Checked" }).orThrow();
    await controls.addEvidence("c1", { attachmentId: "a2" }).orThrow();

    const removed = await controls.removeEvidence("e2").orThrow();

    expect(removed.valid).toBe(false);
    expect(t.calls).toEqual([
      [
        "add_control_evidence",
        {
          control_id: "c1",
          attachment_id: "a1",
          note: "Export",
          valid_until: "2027-01-20",
          task_id: "t1",
        },
      ],
      [
        "add_control_evidence",
        {
          control_id: "c1",
          attachment_id: null,
          note: "Checked",
          valid_until: null,
          task_id: null,
        },
      ],
      [
        "add_control_evidence",
        {
          control_id: "c1",
          attachment_id: "a2",
          note: null,
          valid_until: null,
          task_id: null,
        },
      ],
      ["remove_control_evidence", { evidence_id: "e2" }],
    ]);
  });

  it("saves and lists evidence tasks, and reports the overdue ones", async () => {
    const t = fieldsTransport({
      save_evidence_task: () => TASK,
      list_evidence_tasks: () => [TASK, BARE_TASK],
      notify_overdue_evidence_tasks: () => 2,
    });

    const controls = createCompliance({ transport: t });

    await controls
      .saveEvidenceTask("c1", {
        title: "Quarterly access review",
        intervalDays: 90,
        dueOn: Temporal.PlainDate.from("2026-10-01"),
        assigneeId: "u1",
        active: false,
        evidenceTaskId: "t1",
      })
      .orThrow();
    await controls
      .saveEvidenceTask("c1", { title: "Pen test", intervalDays: 365 })
      .orThrow();

    const [, bare] = await controls.evidenceTasks("org-1").orThrow();

    await controls
      .evidenceTasks("org-1", {
        controlId: "c1",
        assigneeId: "u1",
        overdueOnly: true,
      })
      .orThrow();

    expect(bare).toMatchObject({ intervalDays: 365, active: false });
    expect(bare).not.toHaveProperty("assigneeId");
    expect(bare?.dueOn.toString()).toBe("2027-01-01");
    expect(await controls.notifyOverdue().orThrow()).toBe(2);
    expect(t.calls.slice(0, 4)).toEqual([
      [
        "save_evidence_task",
        {
          control_id: "c1",
          title: "Quarterly access review",
          interval_days: 90,
          due_on: "2026-10-01",
          assignee_id: "u1",
          active: false,
          task_id: "t1",
        },
      ],
      [
        "save_evidence_task",
        {
          control_id: "c1",
          title: "Pen test",
          interval_days: 365,
          due_on: null,
          assignee_id: null,
          active: true,
          task_id: null,
        },
      ],
      [
        "list_evidence_tasks",
        {
          tenant: "org-1",
          control_id: null,
          assignee_id: null,
          overdue_only: false,
        },
      ],
      [
        "list_evidence_tasks",
        {
          tenant: "org-1",
          control_id: "c1",
          assignee_id: "u1",
          overdue_only: true,
        },
      ],
    ]);
  });

  it("rolls up the posture per framework", async () => {
    const t = fieldsTransport({
      control_posture: () => [
        {
          frameworkId: "f1",
          key: "soc2",
          name: "SOC 2",
          version: "2017",
          total: 10,
          passing: 6,
          failing: "2",
          notStarted: 1,
          notApplicable: 1,
          overdueTasks: 2,
        },
        { frameworkId: "f2", key: "iso", name: "ISO" },
      ],
    });

    const controls = createCompliance({ transport: t });

    const [soc2, iso] = await controls.posture("org-1").orThrow();

    await controls.posture("org-1", "f1").orThrow();

    expect(soc2).toMatchObject({ version: "2017", failing: 2, total: 10 });
    expect(iso).toEqual({
      frameworkId: "f2",
      key: "iso",
      name: "ISO",
      total: 0,
      passing: 0,
      failing: 0,
      notStarted: 0,
      notApplicable: 0,
      overdueTasks: 0,
    });
    expect(t.calls).toEqual([
      ["control_posture", { tenant: "org-1", framework_id: null }],
      ["control_posture", { tenant: "org-1", framework_id: "f1" }],
    ]);
  });

  it("saves, publishes, archives and acknowledges policies", async () => {
    const t = fieldsTransport({
      save_policy: () => POLICY,
      publish_policy: () => POLICY,
      archive_policy: () => BARE_POLICY,
      acknowledge_policy: () => POLICY,
      list_policies: () => [POLICY, BARE_POLICY],
    });

    const controls = createCompliance({ transport: t });

    const saved = await controls
      .savePolicy("org-1", {
        key: "security",
        title: "Information security policy",
        ownerId: "u1",
        requiresAcknowledgement: false,
        policyId: "p1",
      })
      .orThrow();

    await controls
      .savePolicy("org-1", { key: "travel", title: "Travel" })
      .orThrow();
    await controls.publishPolicy("p1", { body: "Text" }).orThrow();
    await controls.publishPolicy("p1", { body: "Text" }, "2026").orThrow();

    const archived = await controls.archivePolicy("p2").orThrow();

    await controls.acknowledgePolicy("p1").orThrow();
    await controls.policies("org-1").orThrow();
    await controls
      .policies("org-1", { includeArchived: true, pendingOnly: true })
      .orThrow();

    expect(saved).toMatchObject({
      versionId: "v1",
      versionNumber: 2,
      memberCount: 4,
      acknowledgedCount: 3,
      ownerId: "u1",
    });
    expect(saved.acknowledgedAt?.toString()).toBe(AT);
    expect(Object.keys(archived).toSorted()).toEqual([
      "acknowledgedCount",
      "createdAt",
      "id",
      "key",
      "memberCount",
      "organizationId",
      "requiresAcknowledgement",
      "title",
      "updatedAt",
    ]);
    expect(t.calls).toEqual([
      [
        "save_policy",
        {
          tenant: "org-1",
          key: "security",
          title: "Information security policy",
          owner_id: "u1",
          requires_acknowledgement: false,
          policy_id: "p1",
        },
      ],
      [
        "save_policy",
        {
          tenant: "org-1",
          key: "travel",
          title: "Travel",
          owner_id: null,
          requires_acknowledgement: true,
          policy_id: null,
        },
      ],
      [
        "publish_policy",
        { policy_id: "p1", content: { body: "Text" }, label: null },
      ],
      [
        "publish_policy",
        { policy_id: "p1", content: { body: "Text" }, label: "2026" },
      ],
      ["archive_policy", { policy_id: "p2" }],
      ["acknowledge_policy", { policy_id: "p1" }],
      [
        "list_policies",
        { tenant: "org-1", include_archived: false, pending_only: false },
      ],
      [
        "list_policies",
        { tenant: "org-1", include_archived: true, pending_only: true },
      ],
    ]);
  });

  it("reads who acknowledged a policy", async () => {
    const t = fieldsTransport({
      policy_acknowledgements: (args) =>
        args["policy_id"] === "p1"
          ? {
              id: "p1",
              versionId: "v1",
              versionNumber: 2,
              members: [
                { userId: "u1", acknowledgedAt: AT },
                { userId: "u2", acknowledgedAt: null },
              ],
            }
          : { id: "p2", versionNumber: null },
    });

    const controls = createCompliance({ transport: t });

    const acknowledged = await controls.acknowledgements("p1").orThrow();
    const unpublished = await controls.acknowledgements("p2").orThrow();

    expect(acknowledged.policyId).toBe("p1");
    expect(acknowledged.versionNumber).toBe(2);
    expect(acknowledged.members[0]?.acknowledgedAt?.toString()).toBe(AT);
    expect(acknowledged.members[1]).toEqual({ userId: "u2" });
    expect(unpublished).toEqual({ policyId: "p2", members: [] });
  });

  it("rejects malformed rows and stored fields the schema refuses", async () => {
    const t = fieldsTransport({
      get_control: () => ({ ...BARE_CONTROL, status: "green" }),
      save_evidence_task: () => ({ ...BARE_TASK, dueOn: null }),
      list_controls: () => [{ ...CONTROL, fields: { tier: "mid" } }],
    });

    const controls = createCompliance({ transport: t, fields: Fields });

    expect((await controls.getControl("c2")).ok).toBe(false);
    expect(
      (await controls.saveEvidenceTask("c1", { title: "x", intervalDays: 1 }))
        .ok,
    ).toBe(false);

    const listed = await controls.controls("org-1");

    expect(listed.ok ? undefined : listed.error.kind).toBe("validation");
  });

  it("runs the hooks and logs through the logger", async () => {
    const seen: string[] = [];

    const controls = createCompliance({
      transport: fieldsTransport({ notify_overdue_evidence_tasks: () => 0 }),
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      hooks: {
        notifyOverdue: {
          after: () => {
            seen.push("notifyOverdue");
          },
        },
      },
    });

    await controls.notifyOverdue().orThrow();

    expect(seen).toEqual(["notifyOverdue"]);
  });
});

describe("compliance block", () => {
  it("names the block and validates the inputs", () => {
    expect(complianceBlock.name).toBe("compliance");
    expect(
      validate(controlFrameworkInputSchema, { key: "soc2", name: "SOC 2" })
        .issues,
    ).toBeUndefined();
    expect(
      validate(controlInputSchema, { frameworkId: ID, code: "A", title: "B" })
        .issues,
    ).toBeUndefined();
    expect(
      validate(controlInputSchema, { frameworkId: "f1", code: "A", title: "B" })
        .issues,
    ).toBeDefined();
    expect(
      validate(controlEvidenceInputSchema, { validUntil: "later" }).issues,
    ).toBeDefined();
    expect(
      validate(evidenceTaskInputSchema, { title: "Review", intervalDays: 0 })
        .issues,
    ).toBeDefined();
    expect(
      validate(policyInputSchema, { key: "security", title: "Security" })
        .issues,
    ).toBeUndefined();
  });
});
