import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  caseActionInputSchema,
  caseInputSchema,
  caseKindInputSchema,
  casesBlock,
  createCases,
} from "../../../src/blocks/cases/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";
const ID = "00000000-0000-4000-8000-000000000001";

const KIND = {
  id: "k1",
  organizationId: "org-1",
  key: "complaint",
  name: "Complaint",
  prefix: "CMP",
  pipelineId: "p1",
  effectivenessAfterDays: "30",
  requiresRootCause: true,
  requiresActions: true,
  requiresEffectiveness: false,
  requiresRevisions: false,
  createdAt: AT,
  updatedAt: AT,
};

const CASE = {
  id: "c1",
  organizationId: "org-1",
  kindId: "k1",
  number: "CMP-2026-0001",
  title: "Late delivery",
  description: "Two weeks late",
  severity: "major",
  source: "customer",
  reporterContact: { email: "a@example.com" },
  ownerId: "u1",
  occurredAt: AT,
  dueOn: "2026-11-15",
  stageId: "s1",
  status: "open",
  effective: true,
  effectivenessDueOn: "2026-12-01",
  rank: "8",
  createdAt: AT,
  updatedAt: AT,
  fields: { site: "north" },
};

const BARE = {
  id: "c2",
  organizationId: "org-1",
  kindId: "k1",
  number: "CMP-2026-0002",
  title: "Rude call",
  source: "internal",
  status: "closed",
  closedAt: AT,
  createdAt: AT,
  updatedAt: AT,
  fields: { site: "south" },
};

const Fields = v.object({ site: v.picklist(["north", "south"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createCases", () => {
  it("saves, archives and lists kinds", async () => {
    const t = fieldsTransport({
      save_case_kind: () => KIND,
      archive_case_kind: () => ({ ...KIND, archivedAt: AT }),
      list_case_kinds: () => [KIND],
    });

    const cases = createCases({ transport: t, tenant: "org-1" });

    const saved = await cases
      .saveKind({ key: "complaint", name: "Complaint", prefix: "CMP" })
      .orThrow();

    const archived = await cases.archiveKind("k1").orThrow();
    const listed = await cases.kinds({ includeArchived: true }).orThrow();

    expect(saved).toMatchObject({ prefix: "CMP", effectivenessAfterDays: 30 });
    expect(archived.archivedAt?.toString()).toBe(AT);
    expect(listed).toHaveLength(1);
    expect(t.calls).toEqual([
      [
        "save_case_kind",
        {
          tenant: "org-1",
          key: "complaint",
          name: "Complaint",
          prefix: "CMP",
          investigation_form_id: null,
          effectiveness_form_id: null,
          effectiveness_after_days: null,
          requires_root_cause: true,
          requires_actions: true,
          requires_effectiveness: false,
          requires_revisions: false,
          kind_id: null,
        },
      ],
      ["archive_case_kind", { kind_id: "k1" }],
      ["list_case_kinds", { tenant: "org-1", include_archived: true }],
    ]);
  });

  it("opens, updates and moves a case with its extra fields", async () => {
    const t = fieldsTransport({
      open_case: () => CASE,
      update_case: () => BARE,
    });

    const cases = createCases({
      transport: t,
      tenant: "org-1",
      fields: Fields,
    });

    const opened = await cases
      .open({
        kind: "complaint",
        title: "Late delivery",
        occurredAt: temporal().Instant.from(AT),
        dueOn: temporal().PlainDate.from("2026-11-15"),
        fields: { site: "north" },
      })
      .orThrow();

    const updated = await cases
      .update({ caseId: "c2", change: { title: "Rude call", dueOn: null } })
      .orThrow();

    await cases.move({ caseId: "c2", to: { stageId: "s2" } }).orThrow();

    const refused = await cases.open({
      kind: "complaint",
      title: "Bad",
      // SAFETY: a value the schema refuses, to prove the client checks it.
      fields: { site: "east" } as unknown as { site: "north" },
    });

    expect(opened.fields.site).toBe("north");
    expect(opened.dueOn?.toString()).toBe("2026-11-15");
    expect(opened.reporterContact).toEqual({ email: "a@example.com" });
    expect(opened.effective).toBe(true);
    expect(updated.closedAt?.toString()).toBe(AT);
    expect(updated.description).toBeUndefined();
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(t.calls).toEqual([
      [
        "open_case",
        {
          tenant: "org-1",
          kind: "complaint",
          title: "Late delivery",
          description: null,
          severity: null,
          source: "internal",
          occurred_at: AT,
          owner_id: null,
          due_on: "2026-11-15",
          fields: { site: "north" },
        },
      ],
      [
        "update_case",
        { case_id: "c2", changes: { title: "Rude call", dueOn: null } },
      ],
      ["update_case", { case_id: "c2", changes: { stageId: "s2" } }],
    ]);
  });

  it("records the root cause, actions and effectiveness, and closes", async () => {
    const t = fieldsTransport({
      record_case_root_cause: () => CASE,
      create_case_action: () => ({ actionId: "a1", taskId: "t1" }),
      link_case_action: () => ({ actionId: "a2", taskId: "t2" }),
      remove_case_action: () => CASE,
      record_case_effectiveness: () => CASE,
      case_close_blockers: () => ["CASE_ACTIONS_OPEN"],
      close_case: () => BARE,
      reopen_case: () => CASE,
      cancel_case: () => ({ ...BARE, status: "canceled" }),
    });

    const cases = createCases({ transport: t, tenant: "org-1" });

    await cases
      .recordRootCause({ caseId: "c1", rootCause: "No buffer stock" })
      .orThrow();

    const created = await cases
      .createAction({
        caseId: "c1",
        input: {
          type: "corrective",
          title: "Add buffer stock",
          dueAt: temporal().Instant.from(AT),
        },
      })
      .orThrow();

    const linked = await cases
      .linkAction({
        caseId: "c1",
        taskId: "t2",
        type: "containment",
        required: false,
      })
      .orThrow();

    await cases.removeAction("a2").orThrow();
    await cases
      .recordEffectiveness({
        caseId: "c1",
        effective: true,
        note: "No repeats",
      })
      .orThrow();
    const blockers = await cases.blockers("c1").orThrow();
    const closed = await cases.close({ caseId: "c1" }).orThrow();
    await cases.reopen({ caseId: "c2", reason: "Came back" }).orThrow();
    const canceled = await cases.cancel({ caseId: "c2" }).orThrow();

    expect(created).toEqual({ actionId: "a1", taskId: "t1" });
    expect(linked).toEqual({ actionId: "a2", taskId: "t2" });
    expect(blockers).toEqual(["CASE_ACTIONS_OPEN"]);
    expect(closed.status).toBe("closed");
    expect(canceled.status).toBe("canceled");
    expect(t.calls).toEqual([
      [
        "record_case_root_cause",
        { case_id: "c1", root_cause: "No buffer stock", submission_id: null },
      ],
      [
        "create_case_action",
        {
          case_id: "c1",
          type: "corrective",
          title: "Add buffer stock",
          assignee_id: null,
          due_at: AT,
          required: true,
        },
      ],
      [
        "link_case_action",
        { case_id: "c1", task_id: "t2", type: "containment", required: false },
      ],
      ["remove_case_action", { action_id: "a2" }],
      [
        "record_case_effectiveness",
        {
          case_id: "c1",
          effective: true,
          submission_id: null,
          note: "No repeats",
        },
      ],
      ["case_close_blockers", { case_id: "c1" }],
      ["close_case", { case_id: "c1", note: null }],
      ["reopen_case", { case_id: "c2", reason: "Came back" }],
      ["cancel_case", { case_id: "c2", reason: null }],
    ]);
  });

  it("reads a case with its kind, stage, actions, blockers and relations", async () => {
    const t = fieldsTransport({
      get_case: () => ({
        ...CASE,
        kind: KIND,
        stage: { id: "s1", key: "acting", name: "Acting", outcome: "open" },
        actions: [
          {
            id: "a1",
            taskId: "t1",
            type: "corrective",
            required: true,
            title: "Add buffer stock",
            state: "todo",
            dueAt: AT,
            done: false,
            assignees: ["u1"],
            createdAt: AT,
          },
          "not an action",
        ],
        blockers: ["CASE_ACTIONS_OPEN"],
        relations: { affects: "2" },
      }),
    });

    const cases = createCases({ transport: t, tenant: "org-1" });

    const detail = await cases.get("c1").orThrow();

    expect(detail.kind.key).toBe("complaint");
    expect(detail.stage).toEqual({
      id: "s1",
      key: "acting",
      name: "Acting",
      outcome: "open",
    });
    expect(detail.actions).toHaveLength(1);
    expect(detail.actions[0]).toMatchObject({
      taskId: "t1",
      done: false,
      assignees: ["u1"],
    });
    expect(detail.blockers).toEqual(["CASE_ACTIONS_OPEN"]);
    expect(detail.relations).toEqual({ affects: 2 });
    expect(t.calls).toEqual([["get_case", { case_id: "c1" }]]);
  });

  it("reads a case without a stage, actions or relations", async () => {
    const t = fieldsTransport({ get_case: () => ({ ...BARE, kind: KIND }) });

    const detail = await createCases({ transport: t, tenant: "org-1" })
      .get("c2")
      .orThrow();

    expect(detail.stage).toBeUndefined();
    expect(detail.actions).toEqual([]);
    expect(detail.blockers).toEqual([]);
    expect(detail.relations).toEqual({});
  });

  it("lists cases, counts them and reports due effectiveness checks", async () => {
    const t = fieldsTransport({
      list_cases: () => ({ items: [CASE, BARE], nextCursor: "next" }),
      case_stats: () => [
        { key: "major", count: "2" },
        { key: null, count: 1 },
      ],
      notify_due_case_effectiveness: () => 3,
    });

    const cases = createCases({ transport: t, tenant: "org-1" });

    const page = await cases.list({ kind: "complaint", limit: 10 }).orThrow();

    const stats = await cases
      .stats({
        groupBy: "kind",
        since: temporal().PlainDate.from("2026-01-01"),
      })
      .orThrow();

    const due = await cases.notifyDueEffectiveness().orThrow();

    expect(page.items.map((item) => item.number)).toEqual([
      "CMP-2026-0001",
      "CMP-2026-0002",
    ]);
    expect(page.nextCursor).toBe("next");
    expect(stats).toEqual([
      { key: "major", count: 2 },
      { key: null, count: 1 },
    ]);
    expect(due).toBe(3);
    expect(t.calls).toEqual([
      [
        "list_cases",
        { tenant: "org-1", filters: { kind: "complaint", limit: 10 } },
      ],
      [
        "case_stats",
        {
          tenant: "org-1",
          kind: null,
          since: "2026-01-01",
          until: null,
          group_by: "kind",
        },
      ],
      ["notify_due_case_effectiveness", {}],
    ]);
  });

  it("fills the defaults and reads sparse rows", async () => {
    const { effectivenessAfterDays: _days, ...bareKind } = KIND;
    const { fields: _fields, ...noFields } = BARE;

    const t = fieldsTransport({
      list_case_kinds: () => [bareKind],
      create_case_action: () => ({ actionId: "a1", taskId: "t1" }),
      link_case_action: () => ({ actionId: "a2", taskId: "t2" }),
      record_case_effectiveness: () => noFields,
      reopen_case: () => noFields,
      case_stats: () => [{ key: "x" }],
      get_case: () => ({
        ...BARE,
        kind: KIND,
        actions: [
          { id: "a1", taskId: "t1", type: "preventive", createdAt: AT },
        ],
      }),
    });

    const cases = createCases({
      transport: t,
      tenant: "org-1",
      logger: console,
    });

    const [kind] = await cases.kinds().orThrow();
    await cases
      .createAction({
        caseId: "c1",
        input: { type: "preventive", title: "Train staff", assigneeId: "u2" },
      })
      .orThrow();
    await cases
      .linkAction({ caseId: "c1", taskId: "t2", type: "correction" })
      .orThrow();

    const recorded = await cases
      .recordEffectiveness({ caseId: "c1", effective: false })
      .orThrow();

    await cases.reopen({ caseId: "c2" }).orThrow();

    const [stat] = await cases
      .stats({
        kind: "complaint",
        until: temporal().PlainDate.from("2026-12-31"),
      })
      .orThrow();

    const detail = await cases.get("c2").orThrow();

    expect(kind?.effectivenessAfterDays).toBeUndefined();
    expect(recorded.fields).toEqual({});
    expect(stat).toEqual({ key: "x", count: 0 });
    expect(detail.actions[0]).toMatchObject({
      required: false,
      done: false,
      assignees: [],
    });
    expect(t.calls).toEqual([
      ["list_case_kinds", { tenant: "org-1", include_archived: false }],
      [
        "create_case_action",
        {
          case_id: "c1",
          type: "preventive",
          title: "Train staff",
          assignee_id: "u2",
          due_at: null,
          required: true,
        },
      ],
      [
        "link_case_action",
        { case_id: "c1", task_id: "t2", type: "correction", required: true },
      ],
      [
        "record_case_effectiveness",
        { case_id: "c1", effective: false, submission_id: null, note: null },
      ],
      ["reopen_case", { case_id: "c2", reason: null }],
      [
        "case_stats",
        {
          tenant: "org-1",
          kind: "complaint",
          since: null,
          until: "2026-12-31",
          group_by: "severity",
        },
      ],
      ["get_case", { case_id: "c2" }],
    ]);
  });

  it("rejects a malformed row", async () => {
    const t = fieldsTransport({
      open_case: () => ({ ...CASE, status: "pending" }),
    });

    const result = await createCases({ transport: t, tenant: "org-1" }).open({
      kind: "complaint",
      title: "A",
    });

    expect(result.ok).toBe(false);
  });

  it("needs a tenant for the organization calls", async () => {
    const t = fieldsTransport({});

    const result = await createCases({ transport: t }).kinds();

    expect(result.ok).toBe(false);
    expect(t.calls).toEqual([]);
  });

  it("runs the hooks", async () => {
    const seen: string[] = [];

    const cases = createCases({
      transport: fieldsTransport({ notify_due_case_effectiveness: () => 0 }),
      hooks: {
        notifyDueEffectiveness: {
          after: () => {
            seen.push("notifyDueEffectiveness");
          },
        },
      },
    });

    await cases.notifyDueEffectiveness().orThrow();

    expect(seen).toEqual(["notifyDueEffectiveness"]);
  });
});

describe("cases block", () => {
  it("names the block and validates the inputs", () => {
    expect(casesBlock.name).toBe("cases");
    expect(
      validate(caseInputSchema, { kind: "complaint", title: "A" }).issues,
    ).toBeUndefined();
    expect(
      validate(caseInputSchema, { kind: "", title: "A" }).issues,
    ).toBeDefined();
    expect(
      validate(caseKindInputSchema, {
        key: "k",
        name: "K",
        prefix: "K",
        kindId: ID,
      }).issues,
    ).toBeUndefined();
    expect(
      validate(caseActionInputSchema, { type: "corrective", title: "Fix" })
        .issues,
    ).toBeUndefined();
    expect(
      validate(caseActionInputSchema, { type: "repair", title: "Fix" }).issues,
    ).toBeDefined();
  });
});
