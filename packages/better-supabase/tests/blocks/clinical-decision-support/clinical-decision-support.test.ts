import { describe, expect, it } from "vitest";

import type {
  CareDecisionContext,
  ClinicalDecisionSupport,
} from "../../../src/blocks/clinical-decision-support/index.ts";

import {
  careRuleInputSchema,
  clinicalDecisionSupportBlock,
  createClinicalDecisionSupport,
} from "../../../src/blocks/clinical-decision-support/index.ts";
import {
  ConformanceError,
  testClinicalDecisionSupport,
} from "../../../src/testing/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const RULE = {
  id: "r1",
  organizationId: "org-1",
  kind: "dose_range",
  medicationIds: ["m1"],
  maxDose: 1000,
  maxPerDay: 4000,
  severity: "critical",
  active: true,
  createdAt: AT,
  updatedAt: AT,
};

const ALERT = {
  id: "a1",
  organizationId: "org-1",
  subjectType: "client",
  subjectId: "c1",
  kind: "dose_range",
  severity: "critical",
  source: "built-in",
  orderIds: ["o1"],
  message: "Too much",
  fingerprint: "f1",
  status: "open",
  createdAt: AT,
  updatedAt: AT,
};

const CONTEXT = {
  organizationId: "org-1",
  subjectType: "client",
  subjectId: "c1",
  medications: [],
  observations: [],
  consents: [],
  carePlan: null,
};

const SUBJECT = { type: "client", id: "c1" };

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createClinicalDecisionSupport", () => {
  it("saves, lists and deletes rules", async () => {
    const t = fieldsTransport({
      save_care_rule: () => RULE,
      list_care_rules: () => [RULE],
      delete_care_rule: () => RULE,
    });

    const cds = createClinicalDecisionSupport({
      transport: t,
      tenant: "org-1",
    });

    const saved = await cds
      .saveRule({ kind: "dose_range", medicationIds: ["m1"], maxDose: 1000 })
      .orThrow();

    const listed = await cds.rules().orThrow();
    const deleted = await cds.deleteRule("r1").orThrow();

    expect(saved).toMatchObject({ kind: "dose_range", maxPerDay: 4000 });
    expect(listed).toHaveLength(1);
    expect(deleted.id).toBe("r1");
  });

  it("evaluates the built-in rules, then the engines, and lists the alerts", async () => {
    const seen: CareDecisionContext[] = [];
    const recorded: unknown[] = [];

    const t = fieldsTransport({
      evaluate_care_rules: () => [],
      care_decision_context: () => CONTEXT,
      record_care_alerts: (args) => {
        recorded.push(args);

        return [];
      },
      list_care_alerts: () => [ALERT],
    });

    const engine: ClinicalDecisionSupport = {
      key: "drug-db",
      evaluate: (context) => {
        seen.push(context);

        return [{ message: "Allergy", kind: "allergy", severity: "critical" }];
      },
    };

    const cds = createClinicalDecisionSupport({
      transport: t,
      tenant: "org-1",
      engines: [engine],
    });

    const alerts = await cds.evaluate({ subject: SUBJECT }).orThrow();

    expect(alerts).toHaveLength(1);
    expect(alerts[0]).toMatchObject({ source: "built-in", subject: SUBJECT });
    expect(seen[0]?.subject).toEqual(SUBJECT);
    expect(recorded).toHaveLength(1);
    expect(recorded[0]).toMatchObject({ source: "drug-db" });
  });

  it("returns CARE_ENGINE_FAILED when an engine throws", async () => {
    const t = fieldsTransport({
      evaluate_care_rules: () => [],
      care_decision_context: () => CONTEXT,
      list_care_alerts: () => [],
    });

    const cds = createClinicalDecisionSupport({
      transport: t,
      tenant: "org-1",
      engines: [
        {
          key: "broken",
          evaluate: () => {
            throw new Error("down");
          },
        },
      ],
    });

    const result = await cds.evaluate({ subject: SUBJECT });

    expect(result.ok).toBe(false);
    expect(result.error).toMatchObject({ hint: "CARE_ENGINE_FAILED" });
  });

  it("refuses an engine with the reserved key or another API version", () => {
    const options = { transport: fieldsTransport({}), tenant: "org-1" };

    expect(() =>
      createClinicalDecisionSupport({
        ...options,
        engines: [{ key: "built-in", evaluate: () => [] }],
      }),
    ).toThrow(/built-in/);

    expect(() =>
      createClinicalDecisionSupport({
        ...options,
        engines: [
          {
            // SAFETY: a future version the port doesn't know, to prove the check.
            apiVersion: 2 as unknown as 1,
            key: "x",
            evaluate: () => [],
          },
        ],
      }),
    ).toThrow(/API 2/);
  });

  it("decides an alert with a reason", async () => {
    const calls: unknown[] = [];

    const t = fieldsTransport({
      decide_care_alert: (args) => {
        calls.push(args);

        return { ...ALERT, status: "overridden", decisionReason: "Benefit" };
      },
    });

    const cds = createClinicalDecisionSupport({
      transport: t,
      tenant: "org-1",
    });

    const decided = await cds
      .decide({ alertId: "a1", decision: "overridden", reason: "Benefit" })
      .orThrow();

    expect(decided).toMatchObject({
      status: "overridden",
      decisionReason: "Benefit",
    });
    expect(calls[0]).toMatchObject({
      decision: "overridden",
      reason: "Benefit",
    });
  });

  it("reads optional fields, a care plan and a decided alert", async () => {
    const full = {
      ...ALERT,
      ruleId: "r1",
      details: { dose: 2000 },
      decidedBy: "u1",
      decidedAt: AT,
      decisionReason: "Benefit",
      status: "overridden",
    };

    const t = fieldsTransport({
      evaluate_care_rules: () => [],
      care_decision_context: () => ({
        ...CONTEXT,
        carePlan: {
          id: "p1",
          title: "Plan",
          version: 2,
          reviewOn: "2026-12-01",
        },
      }),
      record_care_alerts: () => [],
      list_care_alerts: () => [full],
      list_care_rules: () => [
        RULE,
        {
          ...RULE,
          id: "r2",
          kind: "interaction",
          maxDose: null,
          message: "Mix",
        },
      ],
    });

    const seen: CareDecisionContext[] = [];

    const cds = createClinicalDecisionSupport({
      transport: t,
      tenant: "org-1",
      engines: [
        {
          key: "e",
          evaluate: (context) => {
            seen.push(context);

            return [];
          },
        },
      ],
    });

    const alerts = await cds.evaluate({ subject: SUBJECT }).orThrow();
    const rules = await cds.rules().orThrow();

    expect(alerts[0]).toMatchObject({
      ruleId: "r1",
      decidedBy: "u1",
      decisionReason: "Benefit",
      details: { dose: 2000 },
    });
    expect(seen[0]?.carePlan).toMatchObject({
      id: "p1",
      reviewOn: "2026-12-01",
    });
    expect(rules).toHaveLength(2);
  });

  it("describes the block and validates a rule", () => {
    expect(clinicalDecisionSupportBlock.name).toBe("clinical-decision-support");
    expect(
      validate(careRuleInputSchema, {
        kind: "interaction",
        medicationIds: ["00000000-0000-4000-8000-000000000001"],
      }).issues,
    ).toBeUndefined();
    expect(
      validate(careRuleInputSchema, { kind: "nope" }).issues,
    ).toBeDefined();
  });
});

describe("testClinicalDecisionSupport", () => {
  const context = {
    organizationId: "org-1",
    subject: SUBJECT,
    medications: [],
    observations: [],
    consents: [],
    carePlan: null,
  } satisfies CareDecisionContext;

  it("passes a conforming engine and fails a drifting one", async () => {
    const engine: ClinicalDecisionSupport = {
      apiVersion: 1,
      key: "good",
      evaluate: () => [{ message: "Check", fingerprint: "a" }],
    };

    await expect(
      testClinicalDecisionSupport(engine, { context }),
    ).resolves.toBeDefined();

    let calls = 0;

    const drifting: ClinicalDecisionSupport = {
      key: "built-in",
      evaluate: () => {
        calls += 1;

        return [{ message: "", fingerprint: String(calls) }];
      },
    };

    await expect(
      testClinicalDecisionSupport(drifting, { context }),
    ).rejects.toBeInstanceOf(ConformanceError);
  });

  it("fails unknown kinds, severities and long fingerprints", async () => {
    for (const alert of [
      { message: "x", kind: "nope" },
      { message: "x", severity: "dire" },
      { message: "x", fingerprint: "f".repeat(201) },
    ] as const) {
      await expect(
        testClinicalDecisionSupport(
          // @ts-expect-error The drift is the point of the test.
          { key: "e", evaluate: () => [alert] },
          { context },
        ),
      ).rejects.toBeInstanceOf(ConformanceError);
    }
  });
});
