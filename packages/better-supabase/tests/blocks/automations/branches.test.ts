import { describe, expect, it } from "vitest";

import type {
  BlockTransport,
  RuleField,
  RuleMatch,
} from "../../../src/blocks/automations/index.ts";

import { conditionsOf } from "../../../src/blocks/automations/automations.ts";
import {
  createAutomations,
  createAutomationsAdmin,
  createActionRegistry,
  createRuleDispatcher,
  automationSink,
  defineAction,
  eventTarget,
  ruleOf,
} from "../../../src/blocks/automations/index.ts";
import { AsyncResult, ok } from "../../../src/core/result.ts";

const tree = {
  id: "root",
  type: "group",
  combinator: "or",
  rules: [
    { id: "a", type: "rule", path: ["status"], operator: "is", value: "x" },
    { id: "g", type: "group", combinator: "and", rules: [] },
  ],
};

const row = (overrides: Record<string, unknown> = {}) => ({
  id: "r1",
  organizationId: "org-1",
  subjectType: "expense",
  trigger: "expense.submitted",
  name: "Rule",
  description: "why",
  conditions: tree,
  actions: [
    { kind: "a", config: { x: 1 } },
    { kind: "b", config: "no" },
    "junk",
  ],
  enabled: false,
  stopProcessing: true,
  rank: "a0",
  version: "2",
  createdAt: "2026-10-19T12:00:00Z",
  updatedAt: "2026-10-19T12:05:00Z",
  defaultKey: "dk",
  ...overrides,
});

function fake(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  const transport: BlockTransport = {
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);

      const result = results[fn];

      return Promise.resolve(
        typeof result === "function"
          ? (result as (a: Record<string, unknown>) => unknown)({ ...args })
          : result,
      );
    },
  };

  return { calls, transport };
}

const statusFields: readonly RuleField[] = [
  {
    subjectType: "expense",
    id: "status",
    label: "Status",
    description: undefined,
    type: "date",
    column: "status",
    columnType: "date",
    nullable: true,
    options: undefined,
    operators: undefined,
  },
];

describe("conditionsOf", () => {
  it("accepts nested groups and rejects malformed trees", () => {
    expect(conditionsOf(tree)).toBe(tree);
    expect(() => conditionsOf(null)).toThrow(TypeError);
    expect(() => conditionsOf({ type: "group" })).toThrow(TypeError);
    expect(() => conditionsOf({ id: "r", type: "rule", path: ["a"] })).toThrow(
      TypeError,
    );
    expect(() => conditionsOf({ id: "r", type: "rule", path: "a" })).toThrow(
      TypeError,
    );
    expect(() =>
      conditionsOf({ id: "g", type: "group", combinator: "xor", rules: [] }),
    ).toThrow(TypeError);
    expect(() =>
      conditionsOf({ id: "g", type: "group", combinator: "and", rules: [1] }),
    ).toThrow(TypeError);
    expect(() => conditionsOf({ id: "g", type: "other" })).toThrow(TypeError);
  });
});

describe("ruleOf", () => {
  it("maps optional columns and drops malformed actions", () => {
    const rule = ruleOf(row());

    expect(rule).toMatchObject({
      description: "why",
      enabled: false,
      stopProcessing: true,
      version: 2,
      defaultKey: "dk",
      actions: [{ kind: "a", config: { x: 1 } }, { kind: "b" }],
    });
    expect(rule.actions[1]).not.toHaveProperty("config");
    expect(ruleOf(row({ actions: "none" })).actions).toEqual([]);
  });
});

describe("createAutomations", () => {
  it("lists with filters and defaults the missing ones to null", async () => {
    const { transport, calls } = fake({ rules_list: [row()] });
    const automations = createAutomations({ transport });

    await automations
      .list({
        organizationId: "o",
        subjectType: "expense",
        trigger: "t",
        enabled: false,
      })
      .orThrow();
    await automations.list({ organizationId: "o" }).orThrow();

    expect(calls[0]?.[1]).toEqual({
      tenant: "o",
      subject_type: "expense",
      trigger: "t",
      enabled: false,
    });
    expect(calls[1]?.[1]).toEqual({
      tenant: "o",
      subject_type: null,
      trigger: null,
      enabled: null,
    });
  });

  it("gets, toggles, moves, removes and resets rules", async () => {
    const { transport, calls } = fake({
      rule_get: (args: Record<string, unknown>) =>
        args["id"] === "r1" ? row() : null,
      set_rule_enabled: row(),
      rank_rule: row(),
      remove_rule: true,
      reset_default_rule: row(),
      save_rule: row(),
    });

    const automations = createAutomations({
      transport,
      logger: { debug() {}, info() {}, warn() {}, error() {} },
    });

    expect((await automations.get("r1").orThrow())?.id).toBe("r1");
    await expect(automations.get("none").orThrow()).resolves.toBeUndefined();
    await automations.setEnabled({ id: "r1", enabled: true }).orThrow();
    await automations.move({ id: "r1", rank: "b0" }).orThrow();
    await expect(automations.remove("r1").orThrow()).resolves.toBe(true);
    await automations.resetDefault("r1").orThrow();

    await automations
      .upsert({ organizationId: "o", input: { name: "n", enabled: true } })
      .orThrow();

    expect(calls.at(-1)?.[1]).toEqual({
      tenant: "o",
      rule: { name: "n", enabled: true },
    });
  });

  it("maps versions and evaluation history", async () => {
    const { transport, calls } = fake({
      rule_versions_list: [
        {
          ruleId: "r1",
          version: 1,
          name: "n",
          conditions: tree,
          actions: [{ kind: "a" }],
          savedBy: "u",
          savedAt: "2026-10-19T12:00:00Z",
        },
      ],
      rule_evaluations_list: [
        {
          id: "e1",
          organizationId: "o",
          ruleId: "r1",
          version: 1,
          subjectType: "expense",
          trigger: "t",
          matched: true,
          results: { a: true, b: "x", c: null },
          mode: "test",
          evaluatedAt: "2026-10-19T12:00:00Z",
        },
        {
          id: "e2",
          organizationId: "o",
          ruleId: "r1",
          version: 1,
          subjectType: "expense",
          trigger: "t",
          results: "nope",
          evaluatedAt: "2026-10-19T12:00:00Z",
        },
      ],
    });

    const automations = createAutomations({ transport });
    const versions = await automations.versions("r1").orThrow();

    expect(versions[0]).toMatchObject({ savedBy: "u", version: 1 });

    const evaluations = await automations.evaluations({ id: "r1" }).orThrow();

    expect(evaluations[0]).toMatchObject({
      mode: "test",
      matched: true,
      results: { a: true, b: null, c: null },
    });
    expect(evaluations[1]).toMatchObject({
      mode: "live",
      matched: false,
      results: {},
      subjectId: undefined,
    });
    expect(calls[1]?.[1]).toEqual({ rule: "r1", before: null, page_size: 50 });

    await automations
      .evaluations({
        id: "r1",
        before: Temporal.Instant.from("2026-10-19T12:00:00Z"),
        pageSize: 5,
      })
      .orThrow();

    expect(calls[2]?.[1]["page_size"]).toBe(5);
    expect(calls[2]?.[1]["before"]).not.toBeNull();
  });

  it("reads the field catalog and matching rules", async () => {
    const { transport, calls } = fake({
      rule_fields_list: [
        {
          subjectType: "expense",
          id: "status",
          label: "Status",
          description: "d",
          type: "select",
          column: "status",
          columnType: "text",
          nullable: false,
          options: [{ value: "a" }, { value: "b", label: "B" }, "junk"],
          operators: ["is"],
        },
        {
          subjectType: "expense",
          id: "amount",
          label: "Amount",
          type: "number",
          column: "amount",
          columnType: "numeric",
        },
      ],
      matching_rules: [{ rule: row(), results: { a: true } }],
    });

    const automations = createAutomations({ transport });
    const fields = await automations.fields().orThrow();

    expect(fields[0]).toMatchObject({
      nullable: false,
      options: [
        { value: "a", label: "a" },
        { value: "b", label: "B" },
      ],
      operators: ["is"],
    });
    expect(fields[1]).toMatchObject({
      nullable: true,
      options: undefined,
      operators: undefined,
    });
    expect(calls[0]?.[1]).toEqual({ subject_type: null });

    await automations.fields("expense").orThrow();
    expect(calls[1]?.[1]).toEqual({ subject_type: "expense" });

    const matches = await automations
      .matching({
        organizationId: "o",
        input: { subjectType: "expense", trigger: "t", subject: {} },
      })
      .orThrow();

    expect(matches[0]?.results).toEqual({ a: true });
    expect(calls[2]?.[1]["time_zone"]).toBe("UTC");

    await automations
      .matching({
        organizationId: "o",
        input: {
          subjectType: "expense",
          trigger: "t",
          subject: {},
          timeZone: "Europe/Amsterdam",
        },
      })
      .orThrow();
    expect(calls[3]?.[1]["time_zone"]).toBe("Europe/Amsterdam");
  });

  it("rejects an unknown field type", async () => {
    const { transport } = fake({
      rule_fields_list: [{ id: "x", type: "bogus" }],
    });

    await expect(
      createAutomations({ transport }).fields().orThrow(),
    ).rejects.toThrow(/./);
  });

  it("tests a rule with a loaded catalog, or reports an invalid rule", async () => {
    const { transport, calls } = fake({
      rule_fields_list: [
        {
          subjectType: "expense",
          id: "status",
          label: "Status",
          type: "select",
          column: "status",
          columnType: "text",
        },
      ],
      record_rule_evaluation: {
        id: "e1",
        organizationId: "o",
        ruleId: "r1",
        version: 1,
        subjectType: "expense",
        trigger: "t",
        matched: false,
        results: {},
        mode: "test",
        evaluatedAt: "2026-10-19T12:00:00Z",
      },
    });

    const automations = createAutomations({ transport });
    const rule = ruleOf(row({ conditions: { ...tree, combinator: "and" } }));

    const evaluation = await automations
      .test({ rule, subject: { status: "x" }, subjectId: "s1" })
      .orThrow();

    expect(evaluation.matched).toBe(true);
    expect(calls.map(([fn]) => fn)).toEqual([
      "rule_fields_list",
      "record_rule_evaluation",
    ]);
    expect(calls[1]?.[1]["subject_id"]).toBe("s1");

    const unknown = await automations.test({
      rule: ruleOf(
        row({
          conditions: {
            id: "g",
            type: "group",
            combinator: "and",
            rules: [
              {
                id: "z",
                type: "rule",
                path: ["status"],
                operator: "bogus",
                value: "2026-01-01",
              },
            ],
          },
        }),
      ),
      subject: { status: "2026-01-01" },
      fields: statusFields,
    });

    expect(unknown.ok).toBe(false);
    expect(calls).toHaveLength(2);
  });

  it("returns the log error when the evaluation cannot be recorded", async () => {
    const transport: BlockTransport = {
      call: (_schema, fn) =>
        fn === "record_rule_evaluation"
          ? Promise.reject(new Error("down"))
          : Promise.resolve([]),
    };

    const result = await createAutomations({ transport }).test({
      rule: ruleOf(row({ conditions: { ...tree, rules: [] } })),
      subject: {},
      fields: [],
    });

    expect(result.ok).toBe(false);
  });
});

describe("createAutomationsAdmin", () => {
  it("syncs fields with their optional parts and runs rules", async () => {
    const { transport, calls } = fake({
      install_default_rules: "4",
      sync_rule_fields: 2,
      run_rules: [{ rule: row(), results: {} }],
    });

    const admin = createAutomationsAdmin({ transport });

    await expect(
      admin.installDefaults({ organizationId: "o" }).orThrow(),
    ).resolves.toBe(4);

    await admin
      .syncFields({
        subjectType: "expense",
        fields: [
          {
            subjectType: "expense",
            id: "a",
            label: "A",
            type: "select",
            column: "a",
            columnType: "text",
            nullable: true,
            description: "d",
            options: [{ value: "x", label: "X" }],
            operators: ["is"],
          },
          {
            subjectType: "expense",
            id: "b",
            label: "B",
            description: undefined,
            type: "number",
            column: "b",
            columnType: "numeric",
            nullable: true,
            options: undefined,
            operators: undefined,
          },
        ],
      })
      .orThrow();

    const sent = calls[1]?.[1]["fields"] as Record<string, unknown>[];

    expect(sent[0]).toMatchObject({ description: "d", operators: ["is"] });
    expect(sent[1]).not.toHaveProperty("description");
    expect(sent[1]).not.toHaveProperty("options");
    expect(sent[1]).not.toHaveProperty("operators");

    await admin
      .run({
        organizationId: "o",
        input: {
          subjectType: null,
          trigger: "t",
          subject: {},
          subjectId: "s",
          timeZone: "Asia/Tokyo",
        },
      })
      .orThrow();
    await admin
      .run({
        organizationId: "o",
        input: { subjectType: null, trigger: "t", subject: {} },
      })
      .orThrow();

    expect(calls[2]?.[1]).toMatchObject({
      subject_id: "s",
      time_zone: "Asia/Tokyo",
    });
    expect(calls[3]?.[1]).toMatchObject({ subject_id: null, time_zone: "UTC" });
  });
});

describe("dispatcher and sink", () => {
  const rule = (kinds: string[]) =>
    ruleOf(row({ actions: kinds.map((kind) => ({ kind })) }));

  const dispatcher = createRuleDispatcher({
    actions: createActionRegistry([
      defineAction({
        kind: "echo",
        title: "Echo",
        run: ({ context }) => ok(context.subjectType),
      }),
    ]),
  });

  it("takes the rule's subject type when the context has none", async () => {
    const match: RuleMatch = { rule: rule(["echo", "missing"]), results: {} };

    const outcomes = await dispatcher
      .dispatch({
        matches: [match],
        context: {
          organizationId: "o",
          subjectType: "",
          subjectId: "s",
          payload: {},
          eventId: "e",
        },
      })
      .orThrow();

    expect(outcomes[0]).toMatchObject({ ok: true, value: "expense" });
    expect(outcomes[1]).toMatchObject({ ok: false });
  });

  it("derives the target from the event itself", () => {
    expect(eventTarget({ id: "e", type: "t", payload: {} })).toBeUndefined();
    expect(
      eventTarget({ id: "e", type: "t", payload: { organizationId: "" } }),
    ).toBeUndefined();
    expect(eventTarget({ id: "e", type: "t", tenant: "org" })).toEqual({
      organizationId: "org",
      subject: {},
    });
    expect(
      eventTarget({
        id: "e",
        type: "t",
        subject: "conversations/c1",
        tenant: "org",
        payload: { id: "p1" },
      }),
    ).toMatchObject({ subjectId: "c1" });
    expect(
      eventTarget({
        id: "e",
        type: "t",
        subject: "nosep",
        payload: { organizationId: "org2", id: "p2" },
      }),
    ).toMatchObject({ organizationId: "org2", subjectId: "p2" });
    expect(
      eventTarget({
        id: "e",
        type: "t",
        payload: { organizationId: "org2", id: "" },
      }),
    ).not.toHaveProperty("subjectId");
  });

  it("runs the event trigger, passes the time zone and skips unmatched events", async () => {
    const runs: Record<string, unknown>[] = [];
    const seen: unknown[] = [];
    const match: RuleMatch = { rule: rule(["echo"]), results: {} };

    const sink = automationSink({
      rules: {
        run: ({ input }) => {
          runs.push({ ...input });

          return AsyncResult.ok(
            input.trigger === "agent.created" ? [match] : [],
          );
        },
      },
      dispatcher,
      load: () => ({
        organizationId: "org",
        subject: { a: 1 },
        timeZone: "Europe/Paris",
      }),
      onOutcomes: (_event, outcomes) => seen.push(outcomes),
    });

    await sink([
      { id: "e1", type: "agent.created", payload: {} },
      { id: "e2", type: "widget.created", payload: {} },
    ]);

    expect(runs.map((input) => input["trigger"])).toEqual([
      "agent.created",
      "widget.created",
    ]);
    expect(runs[0]).toMatchObject({
      subjectType: null,
      timeZone: "Europe/Paris",
    });
    expect(runs[0]).not.toHaveProperty("subjectId");
    expect(seen).toHaveLength(1);
  });

  it("falls back to the event target without a loader", async () => {
    const runs: unknown[] = [];

    const sink = automationSink({
      rules: {
        run: ({ organizationId, input }) => {
          runs.push([organizationId, input.subjectId]);

          return AsyncResult.ok([]);
        },
      },
      dispatcher,
    });

    await sink([
      { id: "e2", type: "widget.created", tenant: "org", payload: { id: "x" } },
      { id: "e3", type: "widget.created", payload: {} },
    ]);

    expect(runs).toEqual([["org", "x"]]);
  });
});
