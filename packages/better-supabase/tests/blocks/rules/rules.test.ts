import { describe, expect, it } from "vitest";

import type { BlockTransport, Rule } from "../../../src/blocks/rules/index.ts";

import {
  approvalsAction,
  checkRuleConditions,
  createRuleDispatcher,
  createRules,
  createRulesAdmin,
  createRuleSink,
  defineRuleFields,
  evaluateRule,
  notifyAction,
  ruleFilterFields,
  rulesBlock,
  setFieldAction,
  webhookAction,
  workflowAction,
} from "../../../src/blocks/rules/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";

type Answer = (args: Record<string, unknown>) => unknown;

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  const transport: BlockTransport = {
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);
      const result = results[fn];

      const value =
        typeof result === "function" ? (result as Answer)({ ...args }) : result;

      return Promise.resolve(value);
    },
  };

  return { calls, transport };
}

const expenses = defineRuleFields("expense", {
  status: { type: "select", options: ["draft", "submitted"] },
  amount: { type: "number", nullable: false },
  "submitter.seniority": { type: "select", label: "Submitter seniority" },
});

const conditions = {
  id: "root",
  type: "group",
  combinator: "and",
  rules: [
    {
      id: "a",
      type: "rule",
      path: ["status"],
      operator: "is",
      value: "submitted",
    },
    { id: "b", type: "rule", path: ["amount"], operator: "gt", value: 500 },
  ],
} as const;

const ruleRow = (overrides: Record<string, unknown> = {}) => ({
  id: "r1",
  organizationId: "org-1",
  subjectType: "expense",
  trigger: "expense.submitted",
  name: "Large expenses",
  description: null,
  conditions,
  actions: [{ kind: "approvals.request", config: { action: "finance" } }],
  enabled: true,
  stopProcessing: false,
  rank: "a0",
  version: 3,
  createdBy: "u1",
  updatedBy: "u1",
  createdAt: "2026-10-19T12:00:00Z",
  updatedAt: "2026-10-19T12:05:00Z",
  ...overrides,
});

const fieldRows = expenses.fields.map((field) => ({
  ...field,
  description: null,
  options: field.options ?? null,
  operators: null,
}));

describe("defineRuleFields", () => {
  it("fills labels, columns and column types", () => {
    expect(expenses.fields).toMatchObject([
      {
        id: "status",
        label: "Status",
        column: "status",
        columnType: "text",
        nullable: true,
      },
      { id: "amount", columnType: "numeric", nullable: false },
      { id: "submitter.seniority", label: "Submitter seniority" },
    ]);
    expect(expenses.fields[0]?.options).toEqual([
      { value: "draft", label: "Draft" },
      { value: "submitted", label: "Submitted" },
    ]);
  });

  it("rejects operators the type doesn't have and non-date column types on dates", () => {
    expect(() =>
      defineRuleFields("expense", {
        amount: { type: "number", operators: ["contains"] },
      }),
    ).toThrow(/not a number operator/);
    expect(() =>
      defineRuleFields("expense", {
        due: { type: "date", columnType: "text" },
      }),
    ).toThrow(/columnType/);
    expect(() => defineRuleFields("Expense", {})).toThrow(/subject type/);
  });

  it("gives ReUI Filters fields and checks trees locally", () => {
    expect(ruleFilterFields(expenses.fields).map((field) => field.id)).toEqual([
      "status",
      "amount",
      "submitter.seniority",
    ]);
    expect(checkRuleConditions(conditions, expenses.fields)).toEqual([]);
    expect(
      checkRuleConditions(
        {
          id: "root",
          type: "group",
          combinator: "and",
          rules: [
            {
              id: "a",
              type: "rule",
              path: ["amount"],
              operator: "contains",
              value: "1",
            },
          ],
        },
        expenses.fields,
      ),
    ).not.toEqual([]);
  });

  it("evaluates a rule in memory", () => {
    const rule = { conditions };

    expect(
      evaluateRule(rule, { status: "submitted", amount: 900 }, expenses.fields),
    ).toEqual({ matched: true, results: { a: true, b: true, root: true } });
    expect(
      evaluateRule(rule, { status: "draft", amount: 900 }, expenses.fields)
        .matched,
    ).toBe(false);
  });
});

describe("createRules", () => {
  it("maps rules, versions and matches", async () => {
    const { calls, transport } = fakeTransport({
      rules_list: [ruleRow()],
      rule_get: null,
      save_rule: ruleRow({ version: 4 }),
      rule_versions_list: [
        {
          ruleId: "r1",
          version: 3,
          name: "Large expenses",
          conditions,
          actions: [],
          savedBy: null,
          savedAt: "2026-10-19T12:05:00Z",
        },
      ],
      matching_rules: [
        { rule: ruleRow(), results: { a: true, b: true, root: true } },
      ],
      rule_fields_list: fieldRows,
    });

    const rules = createRules({ transport });

    const [listed] = await rules
      .list("org-1", { trigger: "expense.submitted" })
      .orThrow();

    expect(listed).toMatchObject({ id: "r1", enabled: true, version: 3 });
    expect(listed?.createdAt.toString()).toBe("2026-10-19T12:00:00Z");
    expect(listed?.description).toBeUndefined();
    expect(await rules.get("missing").orThrow()).toBeUndefined();

    const saved = await rules
      .save("org-1", {
        id: "r1",
        version: 3,
        name: "Large",
      })
      .orThrow();

    expect(saved.version).toBe(4);
    expect((await rules.versions("r1").orThrow())[0]?.savedBy).toBeUndefined();

    const matches = await rules
      .matching("org-1", {
        subjectType: "expense",
        trigger: "expense.submitted",
        subject: { status: "submitted", amount: 900 },
      })
      .orThrow();

    expect(matches[0]?.results).toEqual({ a: true, b: true, root: true });
    expect((await rules.fields("expense").orThrow())[1]).toMatchObject({
      id: "amount",
      type: "number",
      nullable: false,
    });
    expect(calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "rules_list",
        {
          tenant: "org-1",
          subject_type: null,
          trigger: "expense.submitted",
          enabled: null,
        },
      ],
      ["rule_get", { id: "missing" }],
      [
        "save_rule",
        { tenant: "org-1", rule: { id: "r1", version: 3, name: "Large" } },
      ],
      ["rule_versions_list", { id: "r1" }],
      [
        "matching_rules",
        {
          tenant: "org-1",
          subject_type: "expense",
          trigger: "expense.submitted",
          subject: { status: "submitted", amount: 900 },
          time_zone: "UTC",
        },
      ],
      ["rule_fields_list", { subject_type: "expense" }],
    ]);
  });

  it("tests a rule locally and logs the test", async () => {
    const { calls, transport } = fakeTransport({
      rule_fields_list: fieldRows,
      record_rule_evaluation: {
        id: "1",
        organizationId: "org-1",
        ruleId: "r1",
        version: 3,
        subjectType: "expense",
        subjectId: null,
        trigger: "expense.submitted",
        matched: false,
        results: { a: false, b: true, root: false },
        mode: "test",
        evaluatedBy: "u1",
        evaluatedAt: "2026-10-19T12:06:00Z",
      },
    });

    const rules = createRules({ transport });

    const [rule] = await createRules({
      transport: fakeTransport({ rules_list: [ruleRow()] }).transport,
    })
      .list("org-1")
      .orThrow();

    const tested = await rules
      .test(rule!, { status: "draft", amount: 900 })
      .orThrow();

    expect(tested).toEqual({
      matched: false,
      results: { a: false, b: true, root: false },
    });
    expect(calls[1]).toEqual([
      "record_rule_evaluation",
      {
        rule: "r1",
        subject_id: null,
        matched: false,
        results: { a: false, b: true, root: false },
        mode: "test",
      },
    ]);
  });

  it("returns an unexpected row as an error, not a throw", async () => {
    const { transport } = fakeTransport({
      rule_get: { id: "r1", conditions: 1 },
    });

    const result = await createRules({ transport }).get("r1");

    expect(result.ok).toBe(false);
  });
});

describe("createRulesAdmin", () => {
  it("syncs the catalog and runs rules", async () => {
    const { calls, transport } = fakeTransport({
      sync_rule_fields: 3,
      run_rules: [],
    });

    const admin = createRulesAdmin({ transport });

    expect(await admin.syncFields(expenses).orThrow()).toBe(3);
    expect(
      await admin
        .run("org-1", {
          subjectType: "expense",
          trigger: "expense.submitted",
          subjectId: "e1",
          subject: {},
          timeZone: "Europe/Amsterdam",
        })
        .orThrow(),
    ).toEqual([]);
    expect(calls[0]?.[1]["fields"]).toEqual([
      {
        id: "status",
        label: "Status",
        type: "select",
        column: "status",
        columnType: "text",
        nullable: true,
        options: [
          { value: "draft", label: "Draft" },
          { value: "submitted", label: "Submitted" },
        ],
      },
      {
        id: "amount",
        label: "Amount",
        type: "number",
        column: "amount",
        columnType: "numeric",
        nullable: false,
      },
      {
        id: "submitter.seniority",
        label: "Submitter seniority",
        type: "select",
        column: "submitter.seniority",
        columnType: "text",
        nullable: true,
      },
    ]);
    expect(calls[1]?.[1]).toMatchObject({
      subject_id: "e1",
      time_zone: "Europe/Amsterdam",
    });
  });
});

describe("createRuleDispatcher", () => {
  const rule = (actions: Rule["actions"]): Rule => ({
    id: "r1",
    organizationId: "org-1",
    subjectType: "expense",
    trigger: "expense.submitted",
    name: "Large expenses",
    description: undefined,
    conditions,
    actions,
    enabled: true,
    stopProcessing: false,
    rank: "a0",
    version: 1,
    createdBy: undefined,
    updatedBy: undefined,
    createdAt: Temporal.Instant.from("2026-10-19T12:00:00Z"),
    updatedAt: Temporal.Instant.from("2026-10-19T12:00:00Z"),
  });

  it("runs each action and returns every outcome", async () => {
    const dispatcher = createRuleDispatcher<string>({
      handlers: {
        ok: ({ context }) => ok(context),
        fails: () => err(dbError("invalid_request", "no")),
        throws: () => {
          throw new Error("boom");
        },
      },
    });

    const outcomes = await dispatcher
      .dispatch(
        [
          {
            rule: rule([
              { kind: "ok" },
              { kind: "fails" },
              { kind: "throws" },
              { kind: "missing" },
            ]),
            results: {},
          },
        ],
        "ctx",
      )
      .orThrow();

    expect(
      outcomes.map((outcome) =>
        outcome.ok ? outcome.value : outcome.error.kind,
      ),
    ).toEqual(["ctx", "invalid_request", "unexpected", "invalid_request"]);
    expect(outcomes[3]).toMatchObject({
      ok: false,
      error: { hint: "RULE_ACTION_UNKNOWN" },
    });
  });

  it("starts approvals through approvalsAction", async () => {
    const requests: unknown[] = [];

    const handler = approvalsAction({
      request: (input) => {
        requests.push(input);

        return AsyncResult.ok({ id: "a1" });
      },
    });

    const dispatcher = createRuleDispatcher({
      handlers: { "approvals.request": handler },
    });

    const context = {
      organizationId: "org-1",
      subjectType: "expense",
      subjectId: "e1",
      payload: { amount: 900 },
    };

    const outcomes = await dispatcher
      .dispatch(
        [
          {
            rule: rule([
              { kind: "approvals.request", config: { action: "finance" } },
              { kind: "approvals.request" },
            ]),
            results: {},
          },
        ],
        context,
      )
      .orThrow();

    expect(requests).toEqual([
      {
        organizationId: "org-1",
        subjectType: "expense",
        subjectId: "e1",
        action: "finance",
        reason: "Rule: Large expenses",
        payload: { amount: 900 },
      },
    ]);
    expect(outcomes[1]).toMatchObject({
      ok: false,
      error: { hint: "RULE_ACTION_INVALID" },
    });
  });

  const context = {
    organizationId: "org-1",
    subjectType: "task",
    subjectId: "t1",
    eventId: "ev-1",
    payload: { assignee_id: "u2", title: "Ship" },
  };

  it("runs the built-in notify, set_field, webhook and workflow actions", async () => {
    const calls: unknown[] = [];

    const dispatcher = createRuleDispatcher({
      handlers: {
        notify: notifyAction({
          send: (type, input) => {
            calls.push(["notify", type, input]);

            return "sent";
          },
        }),
        set_field: setFieldAction((write) => {
          calls.push(["set_field", write]);

          return ok(true);
        }),
        webhook: webhookAction({
          dispatch: (input) => {
            calls.push(["webhook", input]);

            return AsyncResult.ok("d1");
          },
        }),
        workflow: workflowAction({
          run: (input) => {
            calls.push(["workflow", input]);

            return AsyncResult.ok("run-1");
          },
        }),
      },
    });

    const outcomes = await dispatcher
      .dispatch(
        [
          {
            rule: rule([
              {
                kind: "notify",
                config: {
                  type: "task.assigned",
                  recipients: ["u1"],
                  recipientField: "assignee_id",
                },
              },
              {
                kind: "set_field",
                config: { field: "status", value: "review" },
              },
              { kind: "webhook", config: { endpointId: "ep-1" } },
              { kind: "workflow", config: { definition: "wf-1" } },
            ]),
            results: {},
          },
        ],
        context,
      )
      .orThrow();

    expect(outcomes.every((outcome) => outcome.ok)).toBe(true);
    expect(calls).toEqual([
      [
        "notify",
        "task.assigned",
        {
          recipients: ["u1", "u2"],
          tenant: "org-1",
          key: "rule:r1:notify:ev-1",
          subject: { type: "task", id: "t1" },
          data: { assignee_id: "u2", title: "Ship", rule: "Large expenses" },
        },
      ],
      [
        "set_field",
        {
          organizationId: "org-1",
          subjectType: "task",
          subjectId: "t1",
          field: "status",
          value: "review",
        },
      ],
      [
        "webhook",
        {
          endpointId: "ep-1",
          type: "expense.submitted",
          data: {
            subjectType: "task",
            subjectId: "t1",
            assignee_id: "u2",
            title: "Ship",
          },
          eventId: "ev-1",
        },
      ],
      [
        "workflow",
        {
          definition: "wf-1",
          input: { assignee_id: "u2", title: "Ship" },
          idempotencyKey: "rule:r1:workflow:ev-1",
          subject: { type: "task", id: "t1" },
          tenant: "org-1",
        },
      ],
    ]);
  });

  it("refuses built-in actions without their config", async () => {
    const dispatcher = createRuleDispatcher({
      handlers: {
        notify: notifyAction({ send: () => undefined }),
        set_field: setFieldAction(() => ok(true)),
        webhook: webhookAction({ dispatch: () => AsyncResult.ok("d1") }),
        workflow: workflowAction({ run: () => AsyncResult.ok("run-1") }),
      },
    });

    const outcomes = await dispatcher
      .dispatch(
        [
          {
            rule: rule([
              { kind: "notify", config: { type: "task.assigned" } },
              { kind: "set_field", config: { field: "status" } },
              { kind: "webhook" },
              { kind: "workflow" },
            ]),
            results: {},
          },
        ],
        context,
      )
      .orThrow();

    expect(
      outcomes.map((outcome) => (outcome.ok ? "ok" : outcome.error.hint)),
    ).toEqual([
      "RULE_ACTION_INVALID",
      "RULE_ACTION_INVALID",
      "RULE_ACTION_INVALID",
      "RULE_ACTION_INVALID",
    ]);
  });

  it("runs the rules for an outbox event through createRuleSink", async () => {
    const runs: unknown[] = [];
    const seen: unknown[] = [];
    const match = { rule: rule([{ kind: "ok" }]), results: {} };

    const sink = createRuleSink({
      rules: {
        run: (organizationId, input) => {
          runs.push([organizationId, input]);

          return AsyncResult.ok(input.subjectId === "t1" ? [match] : []);
        },
      },
      dispatcher: createRuleDispatcher<string>({
        handlers: { ok: ({ context: value }) => ok(value) },
      }),
      load: (event) =>
        event.type === "task.skipped"
          ? undefined
          : {
              organizationId: "org-1",
              subjectType: "task",
              subjectId: (event.payload as { id: string }).id,
              subject: { status: "todo" },
              context: `ctx-${event.id}`,
            },
      onOutcomes: (event, outcomes) => seen.push([event.id, outcomes]),
    });

    await sink([
      { id: "e1", type: "task.created", payload: { id: "t1" } },
      { id: "e2", type: "task.skipped", payload: { id: "t2" } },
      { id: "e3", type: "task.updated", payload: { id: "t3" } },
    ]);

    expect(runs).toEqual([
      [
        "org-1",
        {
          subjectType: "task",
          trigger: "task.created",
          subject: { status: "todo" },
          subjectId: "t1",
        },
      ],
      [
        "org-1",
        {
          subjectType: "task",
          trigger: "task.updated",
          subject: { status: "todo" },
          subjectId: "t3",
        },
      ],
    ]);
    expect(seen).toEqual([
      ["e1", [{ ruleId: "r1", kind: "ok", ok: true, value: "ctx-e1" }]],
    ]);
  });

  it("throws from createRuleSink when the evaluation fails, so the outbox retries", async () => {
    const sink = createRuleSink({
      rules: { run: () => AsyncResult.err(dbError("unexpected", "down")) },
      dispatcher: createRuleDispatcher({ handlers: {} }),
      load: () => ({
        organizationId: "org-1",
        subjectType: "task",
        subject: {},
        context: undefined,
      }),
    });

    await expect(sink([{ id: "e1", type: "task.created" }])).rejects.toThrow(
      "down",
    );
  });
});

describe("rulesBlock", () => {
  it("names its SQL module and events", () => {
    expect(rulesBlock.name).toBe("rules");
    expect(rulesBlock.sql).toEqual(["rules"]);
    expect(rulesBlock.events.types).toContain("rule.matched");
  });
});
