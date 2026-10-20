import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/vercel-marketplace/index.ts";

import { createVercelMarketplace } from "../../../src/blocks/vercel-marketplace/index.ts";

const SECRET = "client-secret";
const encoder = new TextEncoder();

async function sign(body: string, secret = SECRET): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );

  const signed = await crypto.subtle.sign("HMAC", key, encoder.encode(body));

  return Array.from(new Uint8Array(signed), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

function fakeTransport(results: Record<string, unknown> = {}) {
  const calls: [string, Record<string, unknown>][] = [];

  const transport: BlockTransport = {
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);

      return Promise.resolve(results[fn] ?? null);
    },
  };

  return { calls, transport };
}

const webhook = async (body: string, secret = SECRET) =>
  new Request("https://app.test/webhooks/vercel", {
    method: "POST",
    headers: { "x-vercel-signature": await sign(body, secret) },
    body,
  });

describe("createVercelMarketplace", () => {
  it("verifies the HMAC-SHA1 signature of the raw body", async () => {
    const { transport } = fakeTransport();

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
    });

    const body = '{"type":"x"}';

    expect(await marketplace.verifyWebhook(body, await sign(body))).toBe(true);
    expect(
      await marketplace.verifyWebhook(body, await sign(body, "other")),
    ).toBe(false);
    expect(await marketplace.verifyWebhook(body, null)).toBe(false);
  });

  it("refuses a webhook with a bad signature without touching the database", async () => {
    const { calls, transport } = fakeTransport();

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
    });

    const result = await marketplace.handleWebhook(
      await webhook('{"type":"integration-configuration.removed"}', "other"),
    );

    expect(result.ok).toBe(false);
    expect(calls).toEqual([]);
  });

  it("removes an installation on integration-configuration.removed", async () => {
    const { calls, transport } = fakeTransport();

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
    });

    const result = await marketplace.handleWebhook(
      await webhook(
        JSON.stringify({
          type: "integration-configuration.removed",
          payload: { configuration: { id: "icfg_1" } },
        }),
      ),
    );

    expect(result.data).toEqual({
      type: "integration-configuration.removed",
      handled: true,
    });
    expect(calls).toEqual([
      ["remove_marketplace_installation", { configuration_id: "icfg_1" }],
    ]);
  });

  it("records an invoice state with the event time", async () => {
    const { calls, transport } = fakeTransport();

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
    });

    const result = await marketplace.handleWebhook(
      await webhook(
        JSON.stringify({
          type: "marketplace.invoice.paid",
          createdAt: Date.parse("2026-10-19T12:00:00Z"),
          payload: { installationId: "icfg_1", invoiceId: "inv_1" },
        }),
      ),
    );

    expect(result.ok).toBe(true);
    expect(calls[0]).toEqual([
      "record_marketplace_invoice",
      {
        configuration_id: "icfg_1",
        external_id: "inv_1",
        state: "paid",
        event_at: "2026-10-19T12:00:00.000Z",
      },
    ]);
  });

  it("ignores an event type it does not handle", async () => {
    const { calls, transport } = fakeTransport();

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
    });

    const result = await marketplace.handleWebhook(
      await webhook(
        JSON.stringify({
          type: "deployment.created",
          payload: { installationId: "icfg_1" },
        }),
      ),
    );

    expect(result.data).toEqual({ type: "deployment.created", handled: false });
    expect(calls).toEqual([]);
  });

  it("stores meter quantities and sends the unreported ones, then marks them", async () => {
    const report = {
      id: "r1",
      installation_id: "i1",
      resource_external_id: "",
      meter_id: "requests",
      quantity: 12,
      reported_at: null,
    };

    const { calls, transport } = fakeTransport({
      record_marketplace_meter_report: report,
      unreported_marketplace_meter_reports: [report],
    });

    const requests: { url: string; body: unknown }[] = [];

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
      accessToken: () => Promise.resolve("tok"),
      fetch: (input, init) => {
        requests.push({
          url: String(input),
          body: JSON.parse(String(init?.body)),
        });

        return Promise.resolve(new Response("{}", { status: 200 }));
      },
    });

    const result = await marketplace.reportUsage({
      configurationId: "icfg_1",
      periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
      periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      meters: [{ meterId: "requests", quantity: 12 }],
    });

    expect(result.data?.[0]?.reported).toBe(true);
    expect(requests[0]?.url).toBe(
      "https://api.vercel.com/v1/installations/icfg_1/billing",
    );
    expect(calls.map(([name]) => name)).toEqual([
      "record_marketplace_meter_report",
      "unreported_marketplace_meter_reports",
      "mark_marketplace_meter_reported",
    ]);
  });

  it("keeps quantities stored when Vercel refuses them", async () => {
    const { calls, transport } = fakeTransport({
      record_marketplace_meter_report: {
        id: "r1",
        installation_id: "i1",
        resource_external_id: "",
        meter_id: "requests",
        quantity: 1,
        reported_at: null,
      },
      unreported_marketplace_meter_reports: [
        {
          id: "r1",
          installation_id: "i1",
          resource_external_id: "",
          meter_id: "requests",
          quantity: 1,
          reported_at: null,
        },
      ],
    });

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
      accessToken: () => Promise.resolve("tok"),
      fetch: () => Promise.resolve(new Response("no", { status: 500 })),
    });

    const result = await marketplace.reportUsage({
      configurationId: "icfg_1",
      periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
      periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      meters: [{ meterId: "requests", quantity: 1 }],
    });

    expect(result.ok).toBe(false);
    expect(calls.map(([name]) => name)).not.toContain(
      "mark_marketplace_meter_reported",
    );
  });
});
