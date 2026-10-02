import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import {
  fromHttp,
  isCloudEvent,
  toCloudEvents,
  toHttp,
} from "../../src/events/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { problems, validatorFor } from "./validator.ts";

const events = toCloudEvents(
  {
    table: "customers",
    kind: "insert",
    rows: [
      { id: "c1", name: "Acme" },
      { id: "c 2", name: "Beta" },
    ],
    context: { tenant: "org-1", actor: { id: "u1", kind: "user" } },
  },
  { source: "https://crm.test/events", meta: schema.meta },
);

describe("CloudEvents 1.0", () => {
  it("specversion is the major.minor of SPEC_PINS.cloudevents", () => {
    expect(SPEC_PINS.cloudevents).toMatch(/^1\.0\.\d+$/);
    for (const event of events)
      expect(event.specversion).toBe(
        SPEC_PINS.cloudevents.split(".").slice(0, 2).join("."),
      );
  });

  it("every event validates against the official JSON format schema", () => {
    const validate = validatorFor("cloudevents-1.0.2.json");
    for (const event of events) expect(problems(validate, event)).toEqual([]);
  });

  it("has the REQUIRED context attributes (spec section 3.1) and unique ids", () => {
    for (const event of events) {
      expect(event.id).toMatch(/\S/);
      expect(event.source).toMatch(/\S/);
      expect(event.type).toMatch(/^[a-z0-9.-]+$/);
    }
    expect(new Set(events.map((event) => event.id)).size).toBe(events.length);
  });

  it("extension attribute names are lower-case a-z0-9 at most 20 characters (section 3.1.1)", () => {
    const core = new Set([
      "specversion",
      "id",
      "source",
      "type",
      "subject",
      "time",
      "datacontenttype",
      "dataschema",
      "data",
      "data_base64",
    ]);
    for (const event of events)
      for (const name of Object.keys(event).filter((key) => !core.has(key)))
        expect(name).toMatch(/^[a-z0-9]{1,20}$/);
  });

  it("time is RFC 3339 (section 3.1.1 OPTIONAL attributes)", () => {
    for (const event of events)
      expect(new Date(event.time!).toISOString()).toBe(event.time);
  });

  it("structured mode uses application/cloudevents+json and round-trips (HTTP binding 3.2)", async () => {
    const [message] = toHttp(events[0]!);
    expect(message!.headers["content-type"]).toBe(
      "application/cloudevents+json",
    );
    const parsed = await fromHttp(
      new Request("https://sink.test", {
        method: "POST",
        headers: message!.headers,
        body: message!.body,
      }),
    );
    expect(parsed).toEqual([events[0]]);
  });

  it("batch mode uses application/cloudevents-batch+json and round-trips (HTTP binding 3.3)", async () => {
    const [message] = toHttp(events, "batch");
    expect(message!.headers["content-type"]).toBe(
      "application/cloudevents-batch+json",
    );
    const parsed = await fromHttp(
      new Request("https://sink.test", {
        method: "POST",
        headers: message!.headers,
        body: message!.body,
      }),
    );
    expect(parsed).toEqual(events);
  });

  it("binary mode maps attributes to ce- headers, percent-encoded, data in the body (HTTP binding 3.1)", async () => {
    const [message] = toHttp(events[1]!, "binary");
    expect(message!.headers["content-type"]).toBe("application/json");
    expect(message!.headers["ce-specversion"]).toBe("1.0");
    expect(message!.headers["ce-subject"]).toBe("customers%2Fc%25202");
    expect(message!.headers).not.toHaveProperty("ce-data");
    expect(message!.headers).not.toHaveProperty("ce-datacontenttype");
    expect(JSON.parse(message!.body)).toEqual(events[1]!.data);
    const [parsed] = await fromHttp(
      new Request("https://sink.test", {
        method: "POST",
        headers: message!.headers,
        body: message!.body,
      }),
    );
    expect(parsed).toMatchObject({ ...events[1], data: events[1]!.data });
  });

  it("isCloudEvent rejects envelopes without the required attributes", () => {
    const { type: _type, ...missing } = events[0]!;
    expect(isCloudEvent(events[0])).toBe(true);
    expect(isCloudEvent(missing)).toBe(false);
    expect(
      isCloudEvent({
        ...events[0],
        specversion: "0.3",
      }),
    ).toBe(false);
  });
});
