import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { problems, validatorFor } from "./validator.ts";

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
      address: "bs:t:public.customers",
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
