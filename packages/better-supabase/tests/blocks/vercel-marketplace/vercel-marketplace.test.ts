import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/vercel-marketplace/index.ts";
import type { Jwks } from "../../../src/core/jws.ts";

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

  const meterRow = (extra: Record<string, unknown> = {}) => ({
    id: "r1",
    installation_id: "i1",
    resource_external_id: "",
    meter_id: "requests",
    period_start: "2026-10-01T00:00:00Z",
    period_end: "2026-11-01T00:00:00Z",
    quantity: 12,
    reported_quantity: 0,
    reported_at: null,
    ...extra,
  });

  it("stores meter quantities and sends the unreported ones, then marks them", async () => {
    const report = meterRow();

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

    expect(result.data?.[0]).toMatchObject({
      reported: true,
      reportedQuantity: 12,
    });
    expect(requests[0]?.url).toBe(
      "https://api.vercel.com/v1/installations/icfg_1/billing",
    );
    expect(calls.map(([name]) => name)).toEqual([
      "record_marketplace_meter_report",
      "unreported_marketplace_meter_reports",
      "mark_marketplace_meter_sent",
    ]);
    expect(calls[2]?.[1]).toEqual({ reports: [{ id: "r1", quantity: 12 }] });
  });

  it("sends one request per period with the total and the part not reported before", async () => {
    const october = meterRow({ quantity: 30, reported_quantity: 12 });

    const september = meterRow({
      id: "r0",
      period_start: "2026-09-01T00:00:00Z",
      period_end: "2026-10-01T00:00:00Z",
      quantity: 50,
      reported_quantity: 40,
    });

    const { calls, transport } = fakeTransport({
      record_marketplace_meter_report: october,
      unreported_marketplace_meter_reports: [september, october],
    });

    const bodies: Record<string, unknown>[] = [];

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
      accessToken: () => Promise.resolve("tok"),
      fetch: (_input, init) => {
        bodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>);

        return Promise.resolve(new Response("{}", { status: 200 }));
      },
    });

    await marketplace.reportUsage({
      configurationId: "icfg_1",
      periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
      periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      meters: [{ meterId: "requests", quantity: 30 }],
    });

    expect(bodies).toMatchObject([
      {
        period: { start: "2026-09-01T00:00:00Z", end: "2026-10-01T00:00:00Z" },
        usage: [{ name: "requests", dayValue: 10, periodValue: 50 }],
      },
      {
        period: { start: "2026-10-01T00:00:00Z", end: "2026-11-01T00:00:00Z" },
        usage: [{ name: "requests", dayValue: 18, periodValue: 30 }],
      },
    ]);
    expect(bodies[0]?.["usage"]).toEqual([
      expect.not.objectContaining({ planValue: expect.anything() }),
    ]);
    expect(
      calls.filter(([name]) => name === "mark_marketplace_meter_sent").length,
    ).toBe(2);
  });

  it("uses the access token sealed at installation when no accessToken is passed", async () => {
    const report = meterRow();

    const { calls, transport } = fakeTransport({
      record_marketplace_meter_report: report,
      unreported_marketplace_meter_reports: [report],
      marketplace_access_token: "vat_sealed",
    });

    const headers: (string | null)[] = [];

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
      fetch: (_input, init) => {
        headers.push(new Headers(init?.headers).get("authorization"));

        return Promise.resolve(new Response("{}", { status: 200 }));
      },
    });

    const result = await marketplace.reportUsage({
      configurationId: "icfg_1",
      periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
      periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      meters: [{ meterId: "requests", quantity: 12 }],
    });

    expect(result.ok).toBe(true);
    expect(headers).toEqual(["Bearer vat_sealed"]);
    expect(calls.map(([name]) => name)).toContain("marketplace_access_token");
  });

  it("maps the tenant and installation helpers to their functions", async () => {
    const { calls, transport } = fakeTransport({
      link_marketplace_tenant: {
        id: "i1",
        configuration_id: "icfg_1",
        tenant: "org_1",
        tenant_created: true,
      },
      marketplace_resource: {
        id: "r1",
        installation_id: "i1",
        external_id: "res",
        name: "db",
        tenant: "org_1",
        tenant_created: true,
        secret_refs: ["key_1", 2],
      },
      marketplace_resources: [],
    });

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
    });

    expect(
      (
        await marketplace.linkTenant({
          configurationId: "icfg_1",
          tenant: "org_1",
          created: true,
        })
      ).data,
    ).toMatchObject({ tenant: "org_1", tenantCreated: true });
    expect((await marketplace.resource("icfg_1", "res")).data).toMatchObject({
      tenant: "org_1",
      tenantCreated: true,
      secretRefs: ["key_1"],
    });
    expect((await marketplace.resources("icfg_1")).data).toEqual([]);
    expect((await marketplace.deleteResource("icfg_1", "res")).data).toBe(
      undefined,
    );
    expect((await marketplace.removeInstallation("icfg_1")).data).toBe(
      undefined,
    );
    expect((await marketplace.sealAccessToken("icfg_1", "vat")).ok).toBe(true);
    expect(calls.map(([name]) => name)).toEqual([
      "link_marketplace_tenant",
      "marketplace_resource",
      "marketplace_resources",
      "delete_marketplace_resource",
      "remove_marketplace_installation",
      "seal_marketplace_access_token",
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
      "mark_marketplace_meter_sent",
    );
  });

  const make = (
    results: Record<string, unknown> = {},
    extra: Partial<Parameters<typeof createVercelMarketplace>[0]> = {},
  ) => {
    const fake = fakeTransport(results);

    return {
      ...fake,
      marketplace: createVercelMarketplace({
        transport: fake.transport,
        clientId: "oac_1",
        clientSecret: SECRET,
        ...extra,
      }),
    };
  };

  it("rejects a webhook that is not JSON, has no type or no invoice id", async () => {
    const { marketplace } = make();

    for (const body of [
      "not json",
      "[]",
      JSON.stringify({
        type: "marketplace.invoice.paid",
        payload: { installationId: "icfg_1" },
      }),
    ]) {
      const result = await marketplace.handleWebhook(await webhook(body));

      expect(result.ok).toBe(false);
    }
  });

  it("reads the installation from the configuration object and ignores events without one", async () => {
    const { calls, marketplace } = make();

    const unhandled = await marketplace.handleWebhook(
      await webhook(JSON.stringify({ type: "marketplace.invoice.paid" })),
    );

    expect(unhandled.data).toEqual({
      type: "marketplace.invoice.paid",
      handled: false,
    });

    const handled = await marketplace.handleWebhook(
      await webhook(
        JSON.stringify({
          type: "marketplace.invoice.notpaid",
          payload: { configurationId: "icfg_2", invoiceId: "inv_2" },
        }),
      ),
    );

    expect(handled.data?.handled).toBe(true);
    expect(calls[0]?.[1]).toMatchObject({
      configuration_id: "icfg_2",
      state: "notpaid",
    });
  });

  it("maps rows from the installation, plan and resource functions", async () => {
    const { calls, marketplace } = make({
      upsert_marketplace_installation: {
        id: "i1",
        configuration_id: "icfg_1",
        team_id: "team",
        status: "suspended",
        metadata: { a: 1 },
      },
      marketplace_installation: { id: "i1", configuration_id: "icfg_1" },
      upsert_marketplace_resource: {
        id: "r1",
        installation_id: "i1",
        external_id: "ext",
        name: "db",
        plan_id: "p1",
        status: "pending",
      },
    });

    const installation = await marketplace.upsertInstallation({
      configurationId: "icfg_1",
      teamId: "team",
    });

    expect(installation.data).toMatchObject({
      configurationId: "icfg_1",
      teamId: "team",
      status: "suspended",
      metadata: { a: 1 },
    });

    expect((await marketplace.installation("icfg_1")).data).toMatchObject({
      status: "active",
      metadata: {},
    });

    expect((await marketplace.upsertPlan({ id: "p1", name: "Pro" })).ok).toBe(
      true,
    );

    const resource = await marketplace.upsertResource({
      configurationId: "icfg_1",
      externalId: "ext",
      name: "db",
      planId: "p1",
    });

    expect(resource.data).toMatchObject({ status: "pending", planId: "p1" });
    expect(calls.map(([name]) => name)).toEqual([
      "upsert_marketplace_installation",
      "marketplace_installation",
      "upsert_marketplace_plan",
      "upsert_marketplace_resource",
    ]);
  });

  it("submits an invoice, and refuses without an access token", async () => {
    const sent: { url: string; body: Record<string, unknown> }[] = [];

    const { marketplace } = make(
      {},
      {
        accessToken: () => Promise.resolve("tok"),
        fetch: (input, init) => {
          sent.push({
            url: String(input),
            body: JSON.parse(String(init?.body)) as Record<string, unknown>,
          });

          return Promise.resolve(
            Response.json({ invoiceId: "inv_9" }, { status: 200 }),
          );
        },
      },
    );

    const input = {
      configurationId: "icfg_1",
      invoiceDate: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
      periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      items: [],
      test: true,
    };

    const result = await marketplace.submitInvoice(input);

    expect(result.data).toEqual({ id: "inv_9" });
    expect(sent[0]?.url).toBe(
      "https://api.vercel.com/v1/installations/icfg_1/billing/invoices",
    );
    expect(sent[0]?.body["test"]).toBe(true);

    const { marketplace: bare } = make();

    expect((await bare.submitInvoice(input)).ok).toBe(false);
  });

  it("turns a thrown fetch into a network error", async () => {
    const { marketplace } = make(
      {},
      {
        accessToken: () => Promise.resolve("tok"),
        fetch: () => Promise.reject(new Error("offline")),
      },
    );

    const result = await marketplace.submitInvoice({
      configurationId: "icfg_1",
      invoiceDate: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
      periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      items: [],
    });

    expect(result.ok).toBe(false);
  });

  it("returns the database error from every operation when a call fails", async () => {
    const transport: BlockTransport = {
      call: () => Promise.reject(new Error("db down")),
    };

    const marketplace = createVercelMarketplace({
      transport,
      clientId: "oac_1",
      clientSecret: SECRET,
      accessToken: () => Promise.resolve("tok"),
      fetch: () => Promise.resolve(new Response("{}", { status: 200 })),
    });

    const results = [
      await marketplace.upsertInstallation({ configurationId: "c" }),
      await marketplace.installation("c"),
      await marketplace.upsertPlan({ id: "p", name: "Pro" }),
      await marketplace.upsertResource({
        configurationId: "c",
        externalId: "e",
        name: "n",
        planId: "p",
      }),
      await marketplace.reportUsage({
        configurationId: "c",
        periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
        periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
        meters: [{ meterId: "m", quantity: 1 }],
      }),
      await marketplace.handleWebhook(
        await webhook(
          JSON.stringify({
            type: "integration-configuration.removed",
            payload: { configuration: { id: "c" } },
          }),
        ),
      ),
    ];

    for (const result of results) {
      expect(result.ok).toBe(false);
    }
  });

  it("stops reporting usage at the database call that fails", async () => {
    const report = {
      id: "r1",
      installation_id: "i1",
      resource_external_id: "",
      meter_id: "m",
      quantity: 1,
      reported_at: null,
    };

    for (const failing of [
      "record_marketplace_meter_report",
      "unreported_marketplace_meter_reports",
      "mark_marketplace_meter_sent",
    ]) {
      const transport: BlockTransport = {
        call: (_schema, fn) =>
          fn === failing
            ? Promise.reject(new Error("db down"))
            : Promise.resolve(
                fn === "unreported_marketplace_meter_reports"
                  ? [report]
                  : report,
              ),
      };

      const marketplace = createVercelMarketplace({
        transport,
        clientId: "oac_1",
        clientSecret: SECRET,
        accessToken: () => Promise.resolve("tok"),
        fetch: () => Promise.resolve(new Response("{}", { status: 200 })),
      });

      const result = await marketplace.reportUsage({
        configurationId: "c",
        periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
        periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
        meters: [{ meterId: "m", quantity: 1 }],
      });

      expect(result.ok).toBe(false);
    }
  });

  it("reports why it has no access token: the lookup failed, none is sealed, or the callback threw", async () => {
    const input = {
      configurationId: "icfg_1",
      invoiceDate: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
      periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      items: [],
    };

    const down = createVercelMarketplace({
      transport: { call: () => Promise.reject(new Error("db down")) },
      clientId: "oac_1",
      clientSecret: SECRET,
    });

    const throwing = make(
      {},
      { accessToken: () => Promise.reject(new Error("vault down")) },
    );

    expect((await down.submitInvoice(input)).error?.message).toContain(
      "db down",
    );
    expect((await make().marketplace.submitInvoice(input)).error?.hint).toBe(
      "MARKETPLACE_NO_TOKEN",
    );
    expect(
      (await throwing.marketplace.submitInvoice(input)).error?.message,
    ).toBe("vault down");
  });

  describe("usageRoute", () => {
    const period = {
      periodStart: Temporal.Instant.from("2026-10-01T00:00:00Z"),
      periodEnd: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      meters: [{ meterId: "requests", quantity: 12 }],
    };

    const cron = (secret = "cron") =>
      new Request("https://app.test/api/cron/usage", {
        headers: { authorization: `Bearer ${secret}` },
      });

    it("reports every installation and names the ones that failed", async () => {
      const errors: string[] = [];

      const { marketplace } = make(
        {
          record_marketplace_meter_report: meterRow(),
          unreported_marketplace_meter_reports: [meterRow()],
        },
        {
          accessToken: (id) =>
            id === "icfg_bad"
              ? Promise.reject(new Error("no token"))
              : Promise.resolve("tok"),
          fetch: () => Promise.resolve(new Response("{}", { status: 200 })),
        },
      );

      const route = marketplace.usageRoute({
        secret: "cron",
        usage: () =>
          Promise.resolve([
            { configurationId: "icfg_1", ...period },
            { configurationId: "icfg_bad", ...period },
          ]),
        onError: (_error, id) => errors.push(id),
      });

      const response = await route(cron());

      expect(response.status).toBe(502);
      expect(await response.json()).toEqual({
        reported: ["icfg_1"],
        failed: ["icfg_bad"],
      });
      expect(errors).toEqual(["icfg_bad"]);
    });

    it("answers 200 when every report went out, 401 without the secret and 500 when usage throws", async () => {
      const { marketplace } = make();

      const empty = marketplace.usageRoute({
        secret: "cron",
        usage: () => Promise.resolve([]),
      });

      const broken = marketplace.usageRoute({
        secret: "cron",
        usage: () => Promise.reject(new Error("usage down")),
      });

      expect((await empty(cron())).status).toBe(200);
      expect((await empty(cron("wrong"))).status).toBe(401);
      expect((await broken(cron())).status).toBe(500);
    });
  });

  describe("exchangeSso", () => {
    const b64 = (value: string | Uint8Array): string =>
      Buffer.from(value).toString("base64url");

    async function idToken(
      claims: Record<string, unknown>,
    ): Promise<{ token: string; jwks: Jwks }> {
      const pair = await crypto.subtle.generateKey(
        {
          name: "RSASSA-PKCS1-v1_5",
          modulusLength: 2048,
          publicExponent: new Uint8Array([1, 0, 1]),
          hash: "SHA-256",
        },
        true,
        ["sign", "verify"],
      );

      const header = b64(JSON.stringify({ alg: "RS256", kid: "k1" }));
      const body = b64(JSON.stringify(claims));

      const signature = await crypto.subtle.sign(
        "RSASSA-PKCS1-v1_5",
        pair.privateKey,
        encoder.encode(`${header}.${body}`),
      );

      const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey);

      return {
        token: `${header}.${body}.${b64(new Uint8Array(signature))}`,
        jwks: {
          keys: [
            {
              kty: "RSA",
              n: jwk.n ?? "",
              e: jwk.e ?? "",
              kid: "k1",
              alg: "RS256",
              use: "sig",
            },
          ],
        },
      };
    }

    const respond =
      (token: string | undefined, status = 200) =>
      () =>
        Promise.resolve(
          Response.json(token === undefined ? {} : { id_token: token }, {
            status,
          }),
        );

    const claims = (extra: Record<string, unknown> = {}) => ({
      iss: "https://marketplace.vercel.com",
      aud: "oac_1",
      exp: Math.floor(Date.now() / 1000) + 600,
      installation_id: "icfg_1",
      account_id: "team_1",
      user_id: "user_1",
      user_email: "a@b.test",
      resource_id: "res",
      path: "/dash",
      ...extra,
    });

    it("returns the error when the keys cannot be loaded", async () => {
      const { token } = await idToken(claims());

      const down = make(
        {},
        {
          jwks: () => Promise.reject(new Error("jwks down")),
          fetch: respond(token),
        },
      );

      expect((await down.marketplace.exchangeSso({ code: "c" })).ok).toBe(
        false,
      );
    });

    it("returns the database error when storing the installation fails", async () => {
      const { token, jwks } = await idToken(claims());

      const marketplace = createVercelMarketplace({
        transport: { call: () => Promise.reject(new Error("db down")) },
        clientId: "oac_1",
        clientSecret: SECRET,
        jwks,
        fetch: respond(token),
      });

      expect((await marketplace.exchangeSso({ code: "c" })).ok).toBe(false);
    });

    it("verifies the id_token and stores the installation", async () => {
      const { token, jwks } = await idToken(claims());

      const { calls, marketplace } = make(
        {
          upsert_marketplace_installation: {
            id: "i1",
            configuration_id: "icfg_1",
          },
        },
        { jwks, fetch: respond(token) },
      );

      const result = await marketplace.exchangeSso({ code: "c", state: "s" });

      expect(result.data).toMatchObject({
        configurationId: "icfg_1",
        teamId: "team_1",
        userEmail: "a@b.test",
        path: "/dash",
      });
      expect(calls[0]?.[0]).toBe("upsert_marketplace_installation");
    });

    it("refuses a wrong audience, an expired token and a missing installation", async () => {
      for (const extra of [
        { aud: "other" },
        { exp: 1 },
        { installation_id: "" },
        { iss: "https://evil.test" },
      ]) {
        const { token, jwks } = await idToken(claims(extra));

        const { marketplace } = make({}, { jwks, fetch: respond(token) });

        expect((await marketplace.exchangeSso({ code: "c" })).ok).toBe(false);
      }
    });

    it("stores an installation without account or user claims", async () => {
      const { token, jwks } = await idToken(
        claims({ account_id: undefined, user_id: undefined }),
      );

      const { calls, marketplace } = make(
        {
          upsert_marketplace_installation: {
            id: "i1",
            configuration_id: "icfg_1",
          },
        },
        { jwks, fetch: respond(token) },
      );

      const result = await marketplace.exchangeSso({ code: "c" });

      expect(result.data).toMatchObject({
        teamId: undefined,
        userId: undefined,
      });
      expect(calls[0]?.[0]).toBe("upsert_marketplace_installation");
    });

    it("retries with refreshed keys for a kid it does not know, then refuses", async () => {
      const { token, jwks } = await idToken(claims());

      const renamed = { keys: jwks.keys.map((key) => ({ ...key, kid: "k2" })) };

      const { marketplace } = make(
        {},
        { jwks: renamed, fetch: respond(token) },
      );

      const result = await marketplace.exchangeSso({ code: "c" });

      expect(result.error?.kind).toBe("unauthorized");
      expect(result.error?.hint).toBe("MARKETPLACE_TOKEN");
    });

    it("refuses a refused code, a response without a token and a key it does not know", async () => {
      const { token } = await idToken(claims());
      const other = await idToken(claims());

      for (const fetchImpl of [
        respond(undefined, 400),
        respond(undefined),
        respond(token),
      ]) {
        const { marketplace } = make(
          {},
          { jwks: other.jwks, fetch: fetchImpl },
        );

        expect((await marketplace.exchangeSso({ code: "c" })).ok).toBe(false);
      }
    });
  });
});
