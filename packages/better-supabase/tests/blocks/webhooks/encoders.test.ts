import { describe, expect, it } from "vitest";

import type { CloudEvent } from "../../../src/events/index.ts";

import { encoderRegistry } from "../../../src/blocks/webhooks/encoders.ts";
import {
  cloudEvents,
  otlpLogs,
  securityEvents,
  splunkHec,
  standardEnvelope,
  type WebhookEncoder,
  type WebhookResponse,
} from "../../../src/blocks/webhooks/index.ts";

const event = (overrides: Partial<CloudEvent> = {}): CloudEvent => ({
  specversion: "1.0",
  id: "del-1",
  source: "https://app.example.com/webhooks",
  type: "invoice.paid",
  subject: "invoices/7",
  time: "2026-10-03T10:00:00Z",
  datacontenttype: "application/json",
  data: { id: 7, total: 12.5, paid: true, lines: ["a"], note: null },
  ...overrides,
});

const target = {
  url: "https://collector.example.com",
  batch: false,
  tenant: null,
};

const token = { token: "tok-1", headers: { authorization: "Bearer tok-1" } };

describe("cloudEvents", () => {
  it("writes a structured event, or a batch for a batch endpoint", async () => {
    const encoder = cloudEvents();
    expect(encoder.signed).toBe(true);
    const one = await encoder.encode([event()], target);
    expect(one.headers["content-type"]).toBe("application/cloudevents+json");
    expect(JSON.parse(one.body)).toMatchObject({ id: "del-1" });

    const many = await encoder.encode([event(), event({ id: "del-2" })], {
      ...target,
      batch: true,
    });

    expect(many.headers["content-type"]).toBe(
      "application/cloudevents-batch+json",
    );
    expect(JSON.parse(many.body)).toHaveLength(2);
  });
});

describe("standardEnvelope", () => {
  it("writes the 0.8 body, or an array of them for a batch endpoint", async () => {
    const encoder = standardEnvelope();
    expect(encoder.signed).toBe(true);
    const one = await encoder.encode([event()], target);
    expect(one.headers["content-type"]).toBe("application/json");
    expect(JSON.parse(one.body)).toEqual({
      type: "invoice.paid",
      timestamp: "2026-10-03T10:00:00Z",
      data: { id: 7, total: 12.5, paid: true, lines: ["a"], note: null },
    });

    const many = await encoder.encode(
      [event(), event({ id: "del-2", data: { id: 8 } })],
      { ...target, batch: true },
    );

    expect(JSON.parse(many.body)).toEqual([
      expect.objectContaining({ type: "invoice.paid" }),
      {
        type: "invoice.paid",
        timestamp: "2026-10-03T10:00:00Z",
        data: { id: 8 },
      },
    ]);
  });
});

describe("otlpLogs", () => {
  it("writes an ExportLogsServiceRequest with a record per event", async () => {
    const encoder = otlpLogs({
      serviceName: "billing",
      resource: { "deployment.environment.name": "production" },
      severity: (e) => (e.type === "invoice.failed" ? 17 : 9),
    });

    expect(encoder.signed).toBe(false);

    const encoded = await encoder.encode(
      [
        event(),
        {
          specversion: "1.0",
          id: "del-2",
          source: "urn:test",
          type: "invoice.failed",
          data: 10n,
        },
      ],
      target,
    );

    expect(encoded.headers["content-type"]).toBe("application/json");
    const request = JSON.parse(encoded.body);
    const [resourceLogs] = request.resourceLogs;
    expect(resourceLogs.resource.attributes).toEqual([
      { key: "service.name", value: { stringValue: "billing" } },
      {
        key: "deployment.environment.name",
        value: { stringValue: "production" },
      },
    ]);
    const [first, second] = resourceLogs.scopeLogs[0].logRecords;
    expect(first).toMatchObject({
      timeUnixNano: "1791021600000000000",
      severityNumber: 9,
      severityText: "INFO",
      eventName: "invoice.paid",
      body: {
        kvlistValue: {
          values: [
            { key: "id", value: { intValue: "7" } },
            { key: "total", value: { doubleValue: 12.5 } },
            { key: "paid", value: { boolValue: true } },
            {
              key: "lines",
              value: { arrayValue: { values: [{ stringValue: "a" }] } },
            },
            { key: "note", value: {} },
          ],
        },
      },
    });
    expect(first.attributes).toContainEqual({
      key: "cloudevents.event_subject",
      value: { stringValue: "invoices/7" },
    });
    expect(second.severityText).toBe("ERROR");
    expect(second.body).toEqual({ intValue: "10" });
    expect(
      second.attributes.some(
        (a: { key: string }) => a.key === "cloudevents.event_subject",
      ),
    ).toBe(false);
    expect(BigInt(second.timeUnixNano)).toBeGreaterThan(0n);
  });

  it("maps strings and other values, and clamps the severity text", async () => {
    const encoded = await otlpLogs({ severity: () => 0 }).encode(
      [event({ data: "plain" }), event({ data: Symbol.for("x") })],
      target,
    );

    const records = JSON.parse(encoded.body).resourceLogs[0].scopeLogs[0]
      .logRecords;

    expect(records[0].body).toEqual({ stringValue: "plain" });
    expect(records[0].severityText).toBe("TRACE");
    expect(records[1].body).toEqual({ stringValue: "Symbol(x)" });
    const defaults = await otlpLogs().encode([event()], target);
    expect(
      JSON.parse(defaults.body).resourceLogs[0].resource.attributes,
    ).toEqual([
      { key: "service.name", value: { stringValue: "better-supabase" } },
    ]);
  });

  it("retries only 429, 502, 503 and 504 and reports a partial success", () => {
    const encoder = otlpLogs();

    const classify = (response: WebhookResponse) =>
      encoder.classify?.(response);

    expect(classify({ status: 503, body: "" })).toEqual({
      outcome: "retry",
      error: "HTTP 503",
    });
    expect(classify({ status: 500, body: "" })).toEqual({
      outcome: "dead",
      error: "HTTP 500",
    });
    expect(classify({ status: 199, body: "" })?.outcome).toBe("dead");
    expect(classify({ status: 200, body: "{}" })).toBeUndefined();
    expect(classify({ status: 200, body: "not json" })).toBeUndefined();
    expect(
      classify({ status: 200, body: '{"partialSuccess":{}}' }),
    ).toBeUndefined();
    expect(
      classify({
        status: 200,
        body: '{"partialSuccess":{"rejectedLogRecords":"2","errorMessage":"too big"}}',
      }),
    ).toEqual({
      outcome: "succeeded",
      error: "The collector rejected 2 log records: too big",
    });
    expect(
      classify({
        status: 200,
        body: '{"partialSuccess":{"rejectedLogRecords":1}}',
      }),
    ).toEqual({
      outcome: "succeeded",
      error: "The collector rejected 1 log records",
    });
  });
});

describe("splunkHec", () => {
  it("writes one HEC event per CloudEvent and authorizes with a Splunk token", async () => {
    const encoder = splunkHec({
      index: "security",
      sourcetype: "cloudevents",
      source: "app",
      host: "web-1",
    });

    expect(encoder.signed).toBe(false);
    expect(encoder.authorize?.(token)).toEqual({
      authorization: "Splunk tok-1",
    });

    const encoded = await encoder.encode(
      [
        event(),
        { specversion: "1.0", id: "del-2", source: "urn:test", type: "x" },
      ],
      target,
    );

    const [first, second] = encoded.body
      .split("\n")
      .map((line) => JSON.parse(line));

    expect(first).toEqual({
      time: 1_791_021_600,
      host: "web-1",
      source: "app",
      sourcetype: "cloudevents",
      index: "security",
      event: event(),
    });
    expect(second.time).toBeGreaterThan(0);
    const defaults = await splunkHec().encode([event()], target);
    expect(JSON.parse(defaults.body)).toMatchObject({
      source: "https://app.example.com/webhooks",
      sourcetype: "_json",
    });
    expect(JSON.parse(defaults.body)).not.toHaveProperty("index");
  });

  it("reads HEC codes, inside a 200 too", () => {
    const encoder = splunkHec();

    const classify = (response: WebhookResponse) =>
      encoder.classify?.(response);

    expect(
      classify({ status: 200, body: '{"text":"Success","code":0}' }),
    ).toEqual({ outcome: "succeeded" });
    expect(classify({ status: 400, body: '{"code":0}' })).toBeUndefined();
    expect(classify({ status: 200, body: "ok" })).toBeUndefined();
    expect(
      classify({ status: 200, body: '{"text":"Server is busy","code":9}' }),
    ).toEqual({ outcome: "retry", error: "HEC 9: Server is busy" });
    expect(classify({ status: 403, body: '{"code":4}' })).toEqual({
      outcome: "dead",
      error: "HEC 4",
    });
  });
});

describe("securityEvents", () => {
  it("sends data.set as an RFC 8935 body, unsigned", async () => {
    const encoder = securityEvents();
    expect(encoder).toMatchObject({ name: "set", signed: false });

    const encoded = await encoder.encode(
      [event({ type: "ssf.set", data: { set: "a.b.c" } })],
      target,
    );

    expect(encoded).toEqual({
      body: "a.b.c",
      headers: {
        "content-type": "application/secevent+jwt",
        accept: "application/json",
      },
    });
    expect(() => encoder.encode([event()], target)).toThrow(TypeError);
  });

  it("retries invalid_key and gives up on other RFC 8935 errors", () => {
    const encoder = securityEvents();

    const classify = (response: WebhookResponse) =>
      encoder.classify?.(response);

    expect(classify({ status: 202, body: "" })).toEqual({
      outcome: "succeeded",
    });
    expect(
      classify({
        status: 400,
        body: '{"err":"invalid_key","description":"kid"}',
      }),
    ).toEqual({ outcome: "retry", error: "SET rejected (invalid_key): kid" });
    expect(
      classify({ status: 400, body: '{"err":"invalid_audience"}' }),
    ).toEqual({ outcome: "dead", error: "SET rejected (invalid_audience)" });
    expect(classify({ status: 400, body: "nope" })).toEqual({
      outcome: "dead",
      error: "SET rejected (HTTP 400)",
    });
    expect(classify({ status: 503, body: "" })).toBeUndefined();
  });
});

describe("encoderRegistry", () => {
  it("holds the built-ins and lets an encoder replace one by name", () => {
    const custom: WebhookEncoder = {
      apiVersion: 1,
      name: "otlp-logs",
      signed: true,
      encode: () => ({ body: "", headers: {} }),
    };

    const registry = encoderRegistry([custom]);
    expect([...registry.keys()]).toEqual([
      "cloudevents",
      "standard",
      "otlp-logs",
      "splunk-hec",
      "set",
    ]);
    expect(registry.get("otlp-logs")).toBe(custom);
  });

  it("refuses a name an endpoint format can't hold", () => {
    expect(() =>
      encoderRegistry([{ ...cloudEvents(), name: "Bad Name" }]),
    ).toThrow(/encoder name "Bad Name"/);
  });
});
