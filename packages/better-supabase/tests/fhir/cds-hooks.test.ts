import { describe, expect, it } from "vitest";

import type { CdsService } from "../../src/fhir/cds-hooks.ts";

import {
  cdsCardOfAlert,
  cdsServiceOf,
  createCdsHooksServer,
} from "../../src/fhir/cds-hooks.ts";

const service: CdsService = {
  apiVersion: 1,
  id: "medication-alerts",
  hook: "order-sign",
  title: "Medication alerts",
  description: "Warns about duplicate therapy",
  prefetch: { patient: "Patient/{{context.patientId}}" },
  handle: async (request) => ({
    cards: [
      cdsCardOfAlert(
        {
          id: "a-1",
          severity: "high",
          message: `For ${String(request.context["patientId"])}`,
        },
        { label: "better-supabase" },
      ),
    ],
  }),
};

const post = (path: string, body: unknown): Request =>
  new Request(`https://cds.example${path}`, {
    method: "POST",
    body: JSON.stringify(body),
  });

describe("CDS Hooks server", () => {
  const handle = createCdsHooksServer({ services: [service] });

  it("lists services for discovery", async () => {
    const response = await handle(
      new Request("https://cds.example/cds-services"),
    );

    const body = (await response.json()) as {
      services: { id: string; hook: string }[];
    };

    expect(body.services).toEqual([
      {
        id: "medication-alerts",
        hook: "order-sign",
        title: "Medication alerts",
        description: "Warns about duplicate therapy",
        prefetch: { patient: "Patient/{{context.patientId}}" },
      },
    ]);
  });

  it("runs a service and returns cards", async () => {
    const response = await handle(
      post("/cds-services/medication-alerts", {
        hook: "order-sign",
        hookInstance: "9b2e1d0e-8f6c-4f8e-9a3f-111111111111",
        context: { patientId: "p-1" },
      }),
    );

    const body = (await response.json()) as {
      cards: { indicator: string; summary: string }[];
    };

    expect(response.status).toBe(200);
    expect(body.cards[0]).toMatchObject({
      indicator: "critical",
      summary: "For p-1",
    });
  });

  it.each([
    ["wrong hook", { hook: "patient-view", hookInstance: "i", context: {} }],
    ["no context", { hook: "order-sign", hookInstance: "i" }],
  ])("answers 400 for %s", async (_name, body) => {
    const response = await handle(
      post("/cds-services/medication-alerts", body),
    );

    expect(response.status).toBe(400);
  });

  it("answers 404, 405 and 401", async () => {
    expect((await handle(post("/cds-services/none", {}))).status).toBe(404);
    expect(
      (
        await handle(
          new Request("https://cds.example/cds-services/medication-alerts"),
        )
      ).status,
    ).toBe(405);

    const closed = createCdsHooksServer({
      services: [service],
      authorize: async () => false,
    });

    expect(
      (await closed(new Request("https://cds.example/cds-services"))).status,
    ).toBe(401);
  });

  it("hides a failing service's message", async () => {
    const broken = createCdsHooksServer({
      services: [
        {
          ...service,
          handle: async () => {
            throw new Error("secret");
          },
        },
      ],
    });

    const response = await broken(
      post("/cds-services/medication-alerts", {
        hook: "order-sign",
        hookInstance: "i",
        context: {},
      }),
    );

    expect(response.status).toBe(500);
    expect(await response.text()).not.toContain("secret");
  });

  it("truncates long summaries into the detail and maps unknown severities to info", () => {
    const card = cdsCardOfAlert(
      { id: "x", severity: "other", message: "m".repeat(200) },
      { label: "s" },
    );

    expect(card.summary).toHaveLength(140);
    expect(card.detail).toHaveLength(200);
    expect(card.indicator).toBe("info");
  });

  it("rejects a service of another API version", () => {
    expect(() =>
      cdsServiceOf({ ...service, apiVersion: 2 } as unknown as CdsService),
    ).toThrow(/supports 1/);
  });
});
