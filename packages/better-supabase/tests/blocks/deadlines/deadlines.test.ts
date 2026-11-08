import { describe, expect, it } from "vitest";

import type { RuleVersionContent } from "../../../src/blocks/deadlines/index.ts";

import {
  createDeadlines,
  evaluateVersion,
  validateRuleVersion,
} from "../../../src/blocks/deadlines/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const CITATION = { reference: "Section 1" };

const CONTENT: RuleVersionContent = {
  groups: [
    { key: "notice", citation: CITATION },
    { key: "lien", citation: CITATION, requires: ["notice"] },
  ],
  rules: [
    {
      key: "notice_owner",
      group: "notice",
      applies: { occupancy: ["owner"] },
      exceptions: [
        {
          name: "small_house",
          when: { units: ["1"] },
          result: "barred",
          citation: CITATION,
        },
      ],
      deadline: { from: "start", n: 20, unit: "days" },
      citation: CITATION,
    },
    {
      key: "lien",
      group: "lien",
      deadline: {
        first_of: [
          { from: "completion_notice", n: 60, unit: "days" },
          { from: "end", n: 120, unit: "days" },
        ],
      },
      citation: CITATION,
    },
  ],
  counting: {
    roll_to: "next_business_day",
    roll_when: ["saturday", "sunday"],
    status: "approved",
  },
};

const DEADLINE = {
  id: "d1",
  organizationId: "org-1",
  subjectType: "case",
  subjectId: "c1",
  jurisdiction: "ca",
  kind: "notice",
  groupKey: "notice",
  ruleKey: "notice_owner",
  period: null,
  ruleVersionId: "v1",
  ruleVersion: 1,
  facts: { start: "2026-01-02", occupancy: "owner", units: "3" },
  result: "due",
  dueOn: "2026-01-22",
  provisional: false,
  missing: [],
  exception: null,
  review: [{ kind: "rule", status: "draft" }],
  basis: { anchor: { fact: "start", date: "2026-01-02" }, without: [] },
  deadline: { from: "start", n: 20, unit: "days" },
  citation: CITATION,
  asOf: "2026-01-03",
  state: "pending",
  computedAt: "2026-01-03T00:00:00Z",
  createdAt: "2026-01-03T00:00:00Z",
};

describe("evaluateVersion", () => {
  it("dates each group, rolls off a weekend and counts without an event that has not happened", () => {
    const [notice, lien] = evaluateVersion(
      CONTENT,
      {
        occupancy: "owner",
        units: "3",
        start: "2026-01-03",
        end: "2026-01-10",
        completion_notice: null,
      },
      "2026-01-03",
    );

    expect(notice).toMatchObject({ result: "due", dueOn: "2026-01-23" });
    expect(lien).toMatchObject({
      result: "due",
      dueOn: "2026-05-11",
      basis: {
        anchor: { fact: "end", date: "2026-01-10" },
        without: ["completion_notice"],
      },
    });
  });

  it("asks what it needs, and bars what requires a barred group", () => {
    expect(
      evaluateVersion(CONTENT, { start: "2026-01-03" }, "2026-01-03").map(
        (result) => [result.result, result.missing],
      ),
    ).toEqual([
      ["unknown", ["occupancy"]],
      ["unknown", ["completion_notice", "end"]],
    ]);
    expect(
      evaluateVersion(
        CONTENT,
        { occupancy: "owner", units: "1", end: "2026-01-10" },
        temporal().PlainDate.from("2026-01-03"),
      ).map((result) => [result.result, result.exception?.note ?? null]),
    ).toEqual([
      ["barred", null],
      ["barred", "falls with notice"],
    ]);
    expect(
      evaluateVersion(
        CONTENT,
        { occupancy: "tenant" },
        "2026-01-03",
        "notice",
      ).map((result) => result.result),
    ).toEqual(["not_covered"]);
    expect(() => evaluateVersion(CONTENT, {}, "soon")).toThrow(RangeError);
  });
});

describe("validateRuleVersion", () => {
  it("accepts a version and names what is wrong with others", () => {
    expect(validateRuleVersion(CONTENT)).toEqual([]);
    expect(validateRuleVersion({ rules: [], groups: [] })).toEqual([
      "a rule set version needs a non-empty list of rules",
      "a rule set version needs a non-empty list of groups",
    ]);
    expect(
      validateRuleVersion({
        ...CONTENT,
        groups: [
          { key: "notice", citation: CITATION, requires: ["lien"] },
          { key: "lien", citation: CITATION, requires: ["notice"] },
        ],
      }),
    ).toEqual([
      "group 1 requires itself through lien",
      "group 2 requires itself through notice",
    ]);
    expect(
      validateRuleVersion({
        ...CONTENT,
        rules: [
          {
            key: "lien",
            group: "lien",
            adjust: "next_business_day",
            deadline: {
              first_of: [
                { before: "recorded", n: 1, unit: "days" },
                { from: "end", n: 2, unit: "days" },
              ],
            },
            citation: CITATION,
          },
        ],
      }),
    ).toContain("rule 1 adjust next_business_day never follows a before count");
  });
});

describe("createDeadlines", () => {
  it("computes a subject's deadlines and reads them back with plain dates", async () => {
    const t = fieldsTransport({ compute_deadlines: () => [DEADLINE] });
    const deadlines = createDeadlines({ transport: t, tenant: "org-1" });
    const { PlainDate } = temporal();

    const [deadline] = await deadlines
      .compute({
        subjectType: "case",
        subjectId: "c1",
        jurisdiction: "ca",
        kind: "notice",
        facts: { start: "2026-01-02" },
        asOf: PlainDate.from("2026-01-03"),
        group: "notice",
      })
      .orThrow();

    expect(deadline?.dueOn?.toString()).toBe("2026-01-22");
    expect(deadline?.asOf.toString()).toBe("2026-01-03");
    expect(deadline).toMatchObject({
      groupKey: "notice",
      ruleKey: "notice_owner",
      result: "due",
      provisional: false,
      review: [{ kind: "rule", status: "draft" }],
      basis: { anchor: { fact: "start", date: "2026-01-02" }, without: [] },
      deadline: { from: "start", n: 20, unit: "days" },
    });
    expect(deadline?.period).toBeUndefined();
    expect(deadline?.exception).toBeUndefined();
    expect(t.calls[0]).toEqual([
      "compute_deadlines",
      {
        tenant: "org-1",
        subject_type: "case",
        subject_id: "c1",
        jurisdiction: "ca",
        kind: "notice",
        facts: { start: "2026-01-02" },
        as_of: "2026-01-03",
        group_key: "notice",
      },
    ]);
  });

  it("saves, approves and finds versions, and lists and satisfies deadlines", async () => {
    const version = {
      id: "v1",
      jurisdiction: "ca",
      kind: "notice",
      version: 1,
      status: "approved",
      rules: CONTENT.rules,
      groups: CONTENT.groups,
      counting: CONTENT.counting,
      meta: { source: "cut" },
      contentHash: "a".repeat(64),
      effectiveFrom: "2020-01-01",
      createdAt: "2020-01-01T00:00:00Z",
    };

    const t = fieldsTransport({
      save_rule_version: () => ({
        ...version,
        status: "draft",
        counting: null,
        meta: null,
      }),
      approve_rule_version: () => version,
      rule_version_at: () => version,
      recompute_deadlines: () => 2,
      list_deadlines: () => [
        {
          ...DEADLINE,
          groupKey: "lien",
          ruleKey: null,
          period: "2026-01",
          result: "barred",
          dueOn: null,
          exception: { name: "small_house", citation: CITATION },
          deadline: "none",
        },
      ],
      satisfy_deadline: () => ({
        ...DEADLINE,
        state: "satisfied",
        satisfiedAt: "2026-02-01T00:00:00Z",
        satisfiedAction: "filed",
      }),
    });

    const deadlines = createDeadlines({ transport: t, tenant: "org-1" });

    const draft = await deadlines
      .saveRules({ jurisdiction: "ca", kind: "notice", content: CONTENT })
      .orThrow();

    expect(draft.status).toBe("draft");
    expect(draft.counting).toBeUndefined();
    expect(t.calls[0]?.[1]).toEqual({
      jurisdiction: "ca",
      kind: "notice",
      content: CONTENT,
    });

    const approved = await deadlines
      .approveRules({ versionId: "v1", approvalId: "a1" })
      .orThrow();

    expect(approved.contentHash).toHaveLength(64);
    expect(approved.effectiveFrom?.toString()).toBe("2020-01-01");
    expect(approved.meta).toEqual({ source: "cut" });

    const found = await deadlines
      .rulesAt({ jurisdiction: "ca", kind: "notice" })
      .orThrow();

    expect([found?.rules.length, found?.groups.length]).toEqual([2, 2]);
    expect(found?.counting?.roll_when).toEqual(["saturday", "sunday"]);
    expect(
      await deadlines
        .recompute({ subjectType: "case", subjectId: "c1", facts: { a: "b" } })
        .orThrow(),
    ).toBe(2);

    const [listed] = await deadlines
      .list({
        state: "pending",
        groupKey: "lien",
        provisional: false,
        limit: 10,
      })
      .orThrow();

    expect(listed).toMatchObject({
      period: "2026-01",
      result: "barred",
      exception: { name: "small_house" },
      deadline: "none",
    });
    expect(listed?.ruleKey).toBeUndefined();
    expect(
      (await deadlines.satisfy({ deadlineId: "d1", action: "filed" }).orThrow())
        .satisfiedAction,
    ).toBe("filed");
    expect(t.calls.find(([fn]) => fn === "list_deadlines")?.[1]).toEqual({
      tenant: "org-1",
      filters: {
        state: "pending",
        groupKey: "lien",
        provisional: false,
        limit: 10,
      },
    });
  });
});
