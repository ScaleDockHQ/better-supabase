import { describe, expect, it } from "vitest";

import { asyncapiFormat } from "../../src/asyncapi/format.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { defineApi } from "../../src/spec/api.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { problems, validatorFor } from "./validator.ts";

const events = defineApi(defineSupabase(schema), {
  info: { title: "CRM events", version: "1.0.0" },
  realtimeUrl: "wss://abc.supabase.co/realtime/v1/websocket",
  resources: { customers: {} },
  events: {
    tables: true,
    topics: {
      room: {
        template: "room:{id}",
        private: true,
        presence: true,
        send: true,
        events: { typing: true },
      },
    },
    cloudEvents: { source: "/crm", rows: ["customers"] },
  },
});

/** A Realtime topic as an AsyncAPI 3 channel, with a receive operation. */
const minimal = (asyncapi: string) => ({
  asyncapi,
  info: { title: "CRM realtime", version: "1.0.0" },
  servers: {
    realtime: {
      host: "abc.supabase.co",
      pathname: "/realtime/v1/websocket",
      protocol: "wss",
    },
  },
  channels: {
    customers: {
      address: "bsb:t:public.customers",
      messages: {
        change: {
          payload: {
            type: "object",
            properties: {
              schema: { type: "string" },
              table: { type: "string" },
              operation: { type: "string" },
            },
          },
        },
      },
    },
  },
  operations: {
    onCustomerChange: {
      action: "receive",
      channel: { $ref: "#/channels/customers" },
    },
  },
});

describe.each([
  [SPEC_PINS.asyncapi30, "asyncapi-3.0.0.json", SPEC_PINS.asyncapi31],
  [SPEC_PINS.asyncapi31, "asyncapi-3.1.0.json", SPEC_PINS.asyncapi30],
] as const)("AsyncAPI %s", (pin, file, other) => {
  it("the pin is the version the vendored schema accepts", () => {
    expect(problems(validatorFor(file), minimal(pin))).toEqual([]);
    expect(problems(validatorFor(file), minimal(other))).not.toEqual([]);
  });

  it("asyncapiFormat renders a document the vendored schema accepts", () => {
    const version = pin === SPEC_PINS.asyncapi30 ? "3.0" : "3.1";

    const { document, diagnostics } = events.render(asyncapiFormat, {
      version,
    });

    expect(diagnostics.filter((d) => d.severity === "error")).toEqual([]);
    expect(document.asyncapi).toBe(pin);
    expect(Object.keys(document.channels).length).toBeGreaterThan(0);
    expect(problems(validatorFor(file), document)).toEqual([]);
  });

  it("the schema rejects an operation with an unknown action", () => {
    const document = minimal(pin);
    expect(
      problems(validatorFor(file), {
        ...document,
        operations: {
          onCustomerChange: {
            ...document.operations.onCustomerChange,
            action: "subscribe",
          },
        },
      }),
    ).not.toEqual([]);
  });
});
