import { describe, expect, it } from "vitest";

import {
  createIncomingWebhooks,
  signWebhook,
} from "../../../src/blocks/webhooks/index.ts";
import { fakeSql, pgError } from "../../fixtures/fake-sql.ts";

const endpoint = (overrides: Record<string, unknown> = {}) => ({
  id: "e1",
  tenant: "t1",
  enabled: true,
  verify: "none",
  secret: null,
  signature_header: null,
  max_body_bytes: 10,
  ...overrides,
});

const post = (body: string, headers: Record<string, string> = {}) =>
  new Request("https://api.test/hooks/tok", { method: "POST", headers, body });

describe("createIncomingWebhooks", () => {
  it("refuses other methods and bad schema names", async () => {
    const hooks = createIncomingWebhooks(fakeSql().sql);
    expect(
      (await hooks.receive(new Request("https://api.test/hooks/tok"), "tok"))
        .status,
    ).toBe(405);
    expect(() =>
      createIncomingWebhooks(fakeSql().sql, { schema: "x; drop" }),
    ).toThrow(/not a schema name/);
  });

  it("refuses bodies over the endpoint's limit and records the status", async () => {
    const fake = fakeSql([["incoming_webhook_by_token", [endpoint()]]]);
    const hooks = createIncomingWebhooks(fake.sql);
    const declared = await hooks.receive(
      post("{}", { "content-length": "999" }),
      "tok",
    );
    expect(declared.status).toBe(413);
    expect(await declared.json()).toMatchObject({ code: "WEBHOOK_TOO_LARGE" });
    expect((await hooks.receive(post('{"a":"long body"}'), "tok")).status).toBe(
      413,
    );
    expect(
      fake.calls
        .filter((call) => call.text.includes("record_incoming_webhook"))
        .map((call) => call.values),
    ).toEqual([
      ["e1", 413],
      ["e1", 413],
    ]);
  });

  it("stores non-JSON bodies, keeps headers and skips disabled endpoints", async () => {
    const fake = fakeSql([
      ["incoming_webhook_by_token", [endpoint({ max_body_bytes: 100 })]],
      ["receive_webhook", [{ id: 4, duplicate: false }]],
    ]);
    const hooks = createIncomingWebhooks(fake.sql, {
      keepHeaders: ["X-Request-Id", "x-missing"],
    });
    const response = await hooks.receive(
      post("hello", { "x-request-id": "r1" }),
      "tok",
    );
    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ id: 4, duplicate: false });
    const stored = fake.calls.find((call) =>
      call.text.includes("receive_webhook"),
    )!;
    expect(stored.values[0]).toBe("webhook-in");
    expect(stored.values[2]).toBeNull();
    expect(stored.values[3]).toBe('{"body":"hello"}');
    expect(JSON.parse(String(stored.values[4]))).toEqual({
      "x-request-id": "r1",
      "x-bs-endpoint-id": "e1",
    });
    expect(stored.values[5]).toBe("t1");
    await hooks.receive(post(""), "tok");
    expect(
      fake.calls.filter((call) => call.text.includes("receive_webhook"))[1]!
        .values[3],
    ).toBe("{}");
    const disabled = fakeSql([
      ["incoming_webhook_by_token", [endpoint({ enabled: false })]],
    ]);
    expect(
      (await createIncomingWebhooks(disabled.sql).receive(post("{}"), "tok"))
        .status,
    ).toBe(404);
    expect(disabled.calls.some((call) => call.text.includes("record_"))).toBe(
      false,
    );
  });

  it("answers a problem when the database fails", async () => {
    const fake = fakeSql([
      ["incoming_webhook_by_token", { throws: pgError("42501", "denied") }],
    ]);
    expect(
      (await createIncomingWebhooks(fake.sql).receive(post("{}"), "tok"))
        .status,
    ).toBe(403);
  });

  it("limits deliveries per endpoint with string periods", async () => {
    const fake = fakeSql([
      ["incoming_webhook_by_token", [endpoint({ max_body_bytes: 100 })]],
      ["hit_rate_limit", [{ allowed: true, retry_after: 0 }]],
      ["receive_webhook", [{ id: 1, duplicate: true }]],
    ]);
    const hooks = createIncomingWebhooks(fake.sql, {
      source: "forms",
      rateLimit: { max: 5, period: "1 hour" },
    });
    expect((await hooks.receive(post("{}"), "tok")).status).toBe(200);
    expect(
      fake.calls.find((call) => call.text.includes("hit_rate_limit"))!.values,
    ).toEqual(["forms:endpoint", "e1", 5, "1 hour"]);
  });

  it("ties endpoints to a subject and lists them", async () => {
    const fake = fakeSql([
      [
        "create_incoming_webhook",
        [
          {
            value: {
              id: "e1",
              tenant: "t",
              name: "Form",
              verify: "none",
              token: "abc",
              secret: null,
              signatureHeader: null,
              subjectType: "workflow",
              subjectId: "w1",
            },
          },
        ],
      ],
      [
        "list_incoming_webhooks",
        [
          {
            value: [
              {
                id: "e1",
                tenant: "t",
                name: "Form",
                verify: "none",
                signature_header: null,
                enabled: true,
                max_body_bytes: 1024,
                receive_count: 3,
                last_received_at: null,
                last_status: 202,
                metadata: null,
                subject_type: "workflow",
                subject_id: "w1",
                created_by: null,
                created_at: "2026-10-06T12:00:00Z",
              },
            ],
          },
        ],
      ],
    ]);
    const hooks = createIncomingWebhooks(fake.sql);
    const created = await hooks
      .create({
        tenant: "t",
        name: "Form",
        subject: { type: "workflow", id: "w1" },
      })
      .orThrow();
    expect(created.subject).toEqual({ type: "workflow", id: "w1" });
    expect(created).not.toHaveProperty("subjectType");
    expect(fake.calls[0]!.values.slice(5)).toEqual(["workflow", "w1"]);
    const listed = await hooks.list("t", { type: "workflow" }).orThrow();
    expect(listed[0]).toMatchObject({
      subject: { type: "workflow", id: "w1" },
      receiveCount: 3,
      lastStatus: 202,
      metadata: {},
    });
    expect(fake.calls[1]!.values).toEqual(["t", "workflow", null]);
  });

  it("manages endpoints through the module's functions", async () => {
    const fake = fakeSql([
      [
        "create_incoming_webhook",
        [
          {
            value: {
              id: "e1",
              tenant: 7,
              name: "Form",
              verify: "none",
              token: "abc",
              secret: null,
              signatureHeader: null,
            },
          },
        ],
      ],
      ["rotate_incoming_webhook", [{ value: { token: "def", secret: "s" } }]],
      ["set_incoming_webhook_enabled", [{ value: true }]],
      ["delete_incoming_webhook", [{ value: false }]],
    ]);
    const hooks = createIncomingWebhooks(fake.sql);
    expect(
      await hooks.create({ tenant: "7", name: "Form" }).orThrow(),
    ).toMatchObject({ tenant: "7", token: "abc" });
    expect(await hooks.rotate("e1", { rotateSecret: true }).orThrow()).toEqual({
      token: "def",
      secret: "s",
    });
    await hooks.rotate("e1").orThrow();
    expect(await hooks.setEnabled("e1", false).orThrow()).toBe(true);
    expect(await hooks.remove("e1").orThrow()).toBe(false);
    expect(fake.calls[0]!.values).toEqual([
      "7",
      "Form",
      "none",
      "{}",
      null,
      null,
      null,
    ]);
    expect(fake.calls[2]!.values).toEqual(["e1", false]);
    const failing = fakeSql([
      ["create_incoming_webhook", { throws: pgError("42501", "denied") }],
      ["rotate_incoming_webhook", { throws: new Error("boom") }],
    ]);
    const broken = createIncomingWebhooks(failing.sql);
    expect(await broken.create({ tenant: "7", name: "x" })).toMatchObject({
      ok: false,
      error: { kind: "forbidden" },
    });
    expect(await broken.rotate("e1")).toMatchObject({ ok: false });
  });

  it("verifies Standard Webhooks and HMAC signatures", async () => {
    const secret = `whsec_${btoa("incoming-unit-secret")}`;
    const body = '{"type":"x"}';
    const fake = fakeSql([
      [
        "incoming_webhook_by_token",
        (call) => [
          call.values[0] === "std"
            ? endpoint({
                verify: "standard-webhooks",
                secret,
                max_body_bytes: 99,
              })
            : endpoint({
                verify: "hmac-sha256",
                secret: "k",
                signature_header: "x-hub",
                max_body_bytes: 99,
              }),
        ],
      ],
      ["receive_webhook", [{ id: 1, duplicate: false }]],
    ]);
    const hooks = createIncomingWebhooks(fake.sql);
    const headers = await signWebhook(secret, { id: "w1", body });
    expect((await hooks.receive(post(body, headers), "std")).status).toBe(202);
    expect(
      fake.calls.find((call) => call.text.includes("receive_webhook"))!
        .values[1],
    ).toBe("e1:w1");
    expect((await hooks.receive(post(body), "std")).status).toBe(401);
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode("k"),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const hex = Array.from(
      new Uint8Array(
        await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)),
      ),
      (byte) => byte.toString(16).padStart(2, "0"),
    ).join("");
    expect(
      (await hooks.receive(post(body, { "x-hub": hex }), "mac")).status,
    ).toBe(202);
    expect((await hooks.receive(post(body), "mac")).status).toBe(401);
  });
});
