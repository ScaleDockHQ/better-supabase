import { describe, expect, it, vi } from "vitest";

import type {
  Rule,
  RuleInput,
} from "../../../src/blocks/automations/automations.ts";
import type { RuleField } from "../../../src/blocks/automations/fields.ts";
import type { AsyncResult } from "../../../src/core/result.ts";
import type { FilterQuery } from "../../../src/list/filter-query.ts";

import { createRuleBuilderController } from "../../../src/blocks/automations/client.ts";
import {
  failed,
  fakeAuth,
  flush,
  held,
  mount,
  resolved,
} from "../../fixtures/ports.ts";

const field = (id: string, type: RuleField["type"]): RuleField => ({
  subjectType: "expense",
  id,
  label: id,
  description: undefined,
  type,
  column: id,
  columnType: type === "number" ? "numeric" : "text",
  nullable: false,
  options: undefined,
  operators: undefined,
});

const FIELDS = [field("amount", "number"), field("note", "text")];

const conditions: FilterQuery = {
  id: "root",
  type: "group",
  combinator: "and",
  rules: [
    { id: "r1", type: "rule", path: ["amount"], operator: "gt", value: 100 },
  ],
};

// SAFETY: the controller reads only these fields.
const stored = (extra: Partial<Rule> = {}) =>
  ({
    id: "rule-1",
    version: 1,
    name: "Large expenses",
    conditions,
    actions: [{ kind: "approvals.request" }],
    stopProcessing: false,
    ...extra,
  }) as unknown as Rule;

function setup(
  options: {
    readonly rule?: string | null;
    readonly locked?: readonly string[];
    readonly initial?: FilterQuery;
    readonly save?: (org: string, input: RuleInput) => AsyncResult<Rule>;
    readonly fields?: AsyncResult<readonly RuleField[]>;
  } = {},
) {
  let next = 0;
  const fields = vi.fn(() => options.fields ?? resolved(FIELDS));
  const get = vi.fn(() => resolved(stored()));

  const save = vi.fn(
    (org: string, input: RuleInput): AsyncResult<Rule> =>
      options.save?.(org, input) ??
      resolved(stored({ version: 2, name: input.name ?? "" })),
  );

  const controller = createRuleBuilderController({
    client: { fields, get, upsert: save },
    auth: fakeAuth(),
    organizationId: "org-1",
    rule: options.rule === undefined ? "rule-1" : options.rule,
    subjectType: "expense",
    trigger: "expense.submitted",
    newId: () => {
      next += 1;

      return `n${next}`;
    },
    ...(options.locked === undefined ? {} : { locked: options.locked }),
    ...(options.initial === undefined ? {} : { initial: options.initial }),
  });

  return { controller, fields, get, save, ...mount(controller) };
}

describe("createRuleBuilderController", () => {
  it("loads the fields and the rule", async () => {
    const { view, fields, get, unmount } = setup();

    expect(view().loading).toBe(true);
    await flush();
    expect(fields).toHaveBeenCalledWith("expense");
    expect(get).toHaveBeenCalledWith("rule-1");
    expect(view()).toMatchObject({
      loading: false,
      name: "Large expenses",
      conditions,
      dirty: false,
      issues: [],
      error: undefined,
    });
    expect(view().fields).toHaveLength(2);
    unmount();
  });

  it("starts a new rule from the initial tree", async () => {
    const { view, get, unmount } = setup({ rule: null, initial: conditions });

    await flush();
    expect(get).not.toHaveBeenCalled();
    expect(view().rule).toBeUndefined();
    expect(view().conditions).toBe(conditions);
    expect(view().dirty).toBe(false);
    unmount();
  });

  it("edits the tree and tracks dirty state and issues", async () => {
    const { view, unmount } = setup();
    await flush();

    const group = view().addGroup(undefined, "or");
    const added = view().addRule(group, "note");
    expect([group, added]).toEqual(["n1", "n2"]);
    expect(view().dirty).toBe(true);
    expect(view().conditions.rules[1]).toMatchObject({
      id: "n1",
      combinator: "or",
      rules: [{ id: "n2", path: ["note"], operator: "contains" }],
    });

    view().setValue("n2", "taxi");
    view().setOperator("n2", "starts_with");
    view().setNegated("n2", true);
    expect(view().conditions.rules[1]).toMatchObject({
      rules: [{ operator: "starts_with", value: "taxi", negated: true }],
    });

    view().setField("n2", "amount");
    expect(view().conditions.rules[1]).toMatchObject({
      rules: [{ path: ["amount"], operator: "eq" }],
    });
    view().setField("n2", "missing");
    view().setCombinator(group, "and");
    view().move("n2", "root", 0);
    expect(view().conditions.rules.map((node) => node.id)).toEqual([
      "n2",
      "r1",
      "n1",
    ]);

    view().addRule(undefined, "unknown");
    expect(view().issues.length).toBeGreaterThan(0);

    view().reset();
    expect(view()).toMatchObject({ conditions, dirty: false, issues: [] });

    view().setName("Renamed");
    view().setStopProcessing(true);
    view().setActions([]);
    expect(view().dirty).toBe(true);
    view().setName("Large expenses");
    view().setStopProcessing(false);
    view().setActions([{ kind: "approvals.request" }]);
    expect(view().dirty).toBe(false);
    unmount();
  });

  it("refuses edits to locked nodes and the groups that hold them", async () => {
    const { view, unmount } = setup({ locked: ["r1"] });
    await flush();

    view().setValue("r1", 5);
    view().remove("r1");
    view().remove("root");
    view().move("r1", "root", 1);
    expect(view().conditions).toBe(conditions);

    view().unlock("r1");
    view().lock("root");
    view().lock("root");
    expect(view().locked).toEqual(["root"]);
    view().setCombinator("root", "or");
    expect(view().conditions.combinator).toBe("and");
    view().remove("r1");
    expect(view().conditions.rules).toEqual([]);

    view().unlock("root");
    view().setCombinator("root", "or");
    expect(view().conditions.combinator).toBe("or");
    unmount();
  });

  it("saves an existing rule with its version", async () => {
    const { view, save, unmount } = setup();
    await flush();

    view().setName("Huge expenses");
    const saved = await view().save({ enabled: true });

    expect(save).toHaveBeenCalledWith("org-1", {
      id: "rule-1",
      version: 1,
      name: "Huge expenses",
      conditions,
      actions: [{ kind: "approvals.request" }],
      stopProcessing: false,
      enabled: true,
    });
    expect(saved?.version).toBe(2);
    expect(view()).toMatchObject({ saving: false, dirty: false });
    expect(view().rule?.version).toBe(2);
    unmount();
  });

  it("saves a new rule with its subject type and trigger", async () => {
    const { view, save, unmount } = setup({ rule: null });
    await flush();

    await view().save();
    expect(save).toHaveBeenCalledWith(
      "org-1",
      expect.objectContaining({
        subjectType: "expense",
        trigger: "expense.submitted",
      }),
    );
    expect(save.mock.calls[0]?.[1]).not.toHaveProperty("id");
    unmount();
  });

  it("keeps the edits when a save fails", async () => {
    const { view, unmount } = setup({ save: () => failed("conflict") });
    await flush();

    view().setName("Huge expenses");
    expect(await view().save()).toBeUndefined();
    expect(view()).toMatchObject({
      saving: false,
      dirty: true,
      name: "Huge expenses",
    });
    expect(view().error?.message).toBe("conflict");
    unmount();
  });

  it("reports load errors and drops stale answers", async () => {
    const { view, fields, get, unmount } = setup();
    await flush();

    get.mockReturnValue(failed("gone"));
    await view().refresh();
    expect(view().error?.message).toBe("gone");
    expect(view().name).toBe("Large expenses");

    fields.mockReturnValue(failed("no fields"));
    await view().refresh();
    expect(view().error?.message).toBe("no fields");
    expect(view().fields).toHaveLength(2);
    unmount();

    const answer = held(FIELDS);
    const late = setup({ fields: answer.result });
    await flush();
    late.unmount();
    answer.release();
    await flush();
    expect(late.controller.getSnapshot().fields).toBeUndefined();
  });
});
