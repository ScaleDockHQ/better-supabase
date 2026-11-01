import type { CareDecisionContext } from "better-supabase/blocks/clinical-decision-support";

import { testClinicalDecisionSupport } from "better-supabase/testing";
import { describe, expect, it } from "vitest";

import { createDecisionSupport } from "../src/clinical-decision-support.ts";
import { fakeFetch, OPTIONS } from "./fake-fetch.ts";

const context = {
  organizationId: "org-1",
  subject: { type: "client", id: "c1" },
  medications: [
    {
      orderId: "o1",
      medicationId: "m1",
      name: "Warfarin 5 mg",
      codeSystem: "atc",
      code: "B01AA03",
      dose: 5,
      doseUnit: "mg",
      asNeeded: false,
      maxPerDay: null,
      schedule: null,
      startsOn: "2026-11-01",
      endsOn: null,
    },
  ],
  observations: [],
  consents: [],
  carePlan: null,
} satisfies CareDecisionContext;

const engine = createDecisionSupport({
  ...OPTIONS,
  fetch: fakeFetch(() => ({
    json: {
      alerts: [
        {
          id: "w-n",
          severity: "critical",
          message: "Bleeding risk",
          orderIds: ["o1"],
        },
      ],
    },
  })).fetch,
});

describe("clinical decision support engine", () => {
  it("passes the better-supabase conformance kit", async () => {
    await expect(
      testClinicalDecisionSupport(engine, { context }),
    ).resolves.toBeDefined();
  });

  it("maps the service alerts and keeps their fingerprint", async () => {
    const alerts = await engine.evaluate(context, {});

    expect(alerts).toEqual([
      {
        kind: "interaction",
        severity: "critical",
        message: "Bleeding risk",
        fingerprint: "w-n",
        orderIds: ["o1"],
      },
    ]);
  });

  it("does not call the service without medications", async () => {
    const { fetch, calls } = fakeFetch(() => ({ json: { alerts: [] } }));

    await createDecisionSupport({ ...OPTIONS, fetch }).evaluate(
      { ...context, medications: [] },
      {},
    );
    expect(calls).toHaveLength(0);
  });
});
