import { describe, expect, it } from "vitest";

import type { DeadlineRule } from "../../../src/blocks/deadlines/index.ts";

import {
  createDeadlines,
  evaluateRule,
  validateRules,
} from "../../../src/blocks/deadlines/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const RULE: DeadlineRule = {
  key: "file_notice",
  anchor: "first_day",
  offset: { amount: 90, unit: "days" },
  adjust: "next_business_day",
  requires: ["state"],
  citation: { reference: "Section 1" },
};

const DEADLINE = {
  id: "d1",
  organizationId: "org-1",
  subjectType: "case",
  subjectId: "c1",
  jurisdiction: "ca",
  kind: "notice",
  ruleKey: "file_notice",
  ruleVersionId: "v1",
  ruleVersion: 1,
  facts: { first_day: "2026-01-02", state: "ca" },
  result: "due",
  dueOn: "2026-04-02",
  missing: [],
  citation: { reference: "Section 1" },
  state: "pending",
  computedAt: "2026-01-03T00:00:00Z",
  createdAt: "2026-01-03T00:00:00Z",
};

describe("evaluateRule", () => {
  it("adds days and moves a weekend to the next business day", () => {
    expect(
      evaluateRule(RULE, { first_day: "2026-01-02", state: "ca" }),
    ).toEqual({ status: "due", dueOn: "2026-04-02" });
    expect(
      evaluateRule(RULE, { first_day: "2026-01-04", state: "ca" }),
    ).toEqual({ status: "due", dueOn: "2026-04-06" });
  });

  it("names the missing facts instead of guessing", () => {
    expect(evaluateRule(RULE, {})).toEqual({
      status: "unknown",
      missing: ["first_day", "state"],
    });
    expect(evaluateRule(RULE, { first_day: "nope", state: "ca" })).toEqual({
      status: "unknown",
      missing: ["first_day"],
    });
  });

  it("clamps months to the end of the month and counts business days", () => {
    const months: DeadlineRule = {
      ...RULE,
      offset: { amount: 1, unit: "months" },
      adjust: "none",
      requires: [],
    };

    expect(evaluateRule(months, { first_day: "2026-01-31" })).toEqual({
      status: "due",
      dueOn: "2026-02-28",
    });

    const business: DeadlineRule = {
      ...months,
      offset: { amount: 5, unit: "business_days" },
    };

    expect(evaluateRule(business, { first_day: "2026-01-02" })).toEqual({
      status: "due",
      dueOn: "2026-01-09",
    });
  });
});

describe("validateRules", () => {
  it("accepts a rule and names what is wrong with others", () => {
    expect(validateRules([RULE])).toEqual([]);
    expect(validateRules([])).not.toEqual([]);
    expect(validateRules([{ ...RULE, citation: {} }])).not.toEqual([]);
    expect(validateRules([RULE, RULE])).not.toEqual([]);
    expect(
      validateRules([{ ...RULE, offset: { amount: 99_999, unit: "days" } }]),
    ).not.toEqual([]);
  });
});

describe("createDeadlines", () => {
  it("computes a deadline and reads it back with a plain date", async () => {
    const t = fieldsTransport({ compute_deadline: () => DEADLINE });
    const deadlines = createDeadlines({ transport: t, tenant: "org-1" });
    const { PlainDate } = temporal();

    const deadline = await deadlines
      .compute({
        subjectType: "case",
        subjectId: "c1",
        jurisdiction: "ca",
        kind: "notice",
        ruleKey: "file_notice",
        facts: { first_day: "2026-01-02", state: "ca" },
        asOf: PlainDate.from("2026-01-03"),
      })
      .orThrow();

    expect(deadline.dueOn?.toString()).toBe("2026-04-02");
    expect(deadline.result).toBe("due");
    expect(t.calls[0]).toEqual([
      "compute_deadline",
      {
        tenant: "org-1",
        subject_type: "case",
        subject_id: "c1",
        jurisdiction: "ca",
        kind: "notice",
        rule_key: "file_notice",
        facts: { first_day: "2026-01-02", state: "ca" },
        as_of: "2026-01-03",
      },
    ]);
  });

  it("saves, approves and finds rules, and lists and satisfies deadlines", async () => {
    const version = {
      id: "v1",
      jurisdiction: "ca",
      kind: "notice",
      version: 1,
      status: "approved",
      rules: [RULE],
      contentHash: "a".repeat(64),
      effectiveFrom: "2020-01-01",
      createdAt: "2020-01-01T00:00:00Z",
    };

    const t = fieldsTransport({
      save_rule_version: () => ({ ...version, status: "draft" }),
      approve_rule_version: () => version,
      rule_version_at: () => version,
      recompute_deadlines: () => 2,
      list_deadlines: () => [DEADLINE],
      satisfy_deadline: () => ({
        ...DEADLINE,
        state: "satisfied",
        satisfiedAt: "2026-02-01T00:00:00Z",
        satisfiedAction: "filed",
      }),
    });

    const deadlines = createDeadlines({ transport: t, tenant: "org-1" });

    expect(
      (
        await deadlines
          .saveRules({ jurisdiction: "ca", kind: "notice", rules: [RULE] })
          .orThrow()
      ).status,
    ).toBe("draft");

    const approved = await deadlines
      .approveRules({ versionId: "v1", approvalId: "a1" })
      .orThrow();

    expect(approved.contentHash).toHaveLength(64);
    expect(approved.effectiveFrom?.toString()).toBe("2020-01-01");
    expect(
      (
        await deadlines
          .rulesAt({ jurisdiction: "ca", kind: "notice" })
          .orThrow()
      )?.rules,
    ).toHaveLength(1);
    expect(
      await deadlines
        .recompute({ subjectType: "case", subjectId: "c1", facts: { a: "b" } })
        .orThrow(),
    ).toBe(2);
    expect(
      await deadlines.list({ state: "pending", limit: 10 }).orThrow(),
    ).toHaveLength(1);
    expect(
      (await deadlines.satisfy({ deadlineId: "d1", action: "filed" }).orThrow())
        .satisfiedAction,
    ).toBe("filed");
    expect(t.calls.find(([fn]) => fn === "list_deadlines")?.[1]).toEqual({
      tenant: "org-1",
      filters: { state: "pending", limit: 10 },
    });
  });
});
