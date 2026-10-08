import { describe, expect, it } from "vitest";

import {
  DELIVERY_PARSERS,
  messengerDeliveries,
  twilioDeliveries,
  whatsappDeliveries,
} from "../../src/chat-sdk/index.ts";

const event = (body: unknown, type = "application/json") => ({
  body: typeof body === "string" ? body : JSON.stringify(body),
  headers: { "content-type": type },
});

const whatsapp = (value: Record<string, unknown>) => ({
  object: "whatsapp_business_account",
  entry: [{ changes: [{ value }, "junk"] }],
});

describe("whatsappDeliveries", () => {
  it("reads statuses and their first error", () => {
    const parsed = whatsappDeliveries(
      event(
        whatsapp({
          statuses: [
            { id: "w1", status: "delivered" },
            {
              id: "w2",
              status: "failed",
              errors: [{ title: "Re-engagement" }],
            },
            { id: "w3", status: "failed", errors: [{ message: "boom" }] },
            { id: "w4", status: "warning" },
            { status: "read" },
            "junk",
          ],
        }),
      ),
    );
    expect(parsed).toEqual({
      only: true,
      updates: [
        { externalId: "w1", status: "delivered" },
        { externalId: "w2", status: "failed", error: "Re-engagement" },
        { externalId: "w3", status: "failed", error: "boom" },
      ],
    });
  });

  it("says when the body also carries messages", () => {
    const parsed = whatsappDeliveries(
      event(
        whatsapp({
          messages: [{ id: "in" }],
          statuses: [{ id: "w1", status: "sent" }],
        }),
      ),
    );
    expect(parsed?.only).toBe(false);
    expect(whatsappDeliveries(event(whatsapp({ messages: [{}] })))).toEqual({
      updates: [],
      only: false,
    });
  });

  it("ignores other bodies", () => {
    expect(whatsappDeliveries(event("not json"))).toBeNull();
    expect(whatsappDeliveries(event({ object: "page" }))).toBeNull();
  });
});

describe("messengerDeliveries", () => {
  it("reads delivery mids and skips read receipts", () => {
    const parsed = messengerDeliveries(
      event({
        object: "page",
        entry: [
          {
            messaging: [
              { delivery: { mids: ["m1", 2, "m2"] } },
              { read: { watermark: 1 } },
            ],
          },
          "junk",
        ],
      }),
    );
    expect(parsed).toEqual({
      only: true,
      updates: [
        { externalId: "m1", status: "delivered" },
        { externalId: "m2", status: "delivered" },
      ],
    });
  });

  it("is not only receipts when messages arrive too", () => {
    const parsed = messengerDeliveries(
      event({
        object: "instagram",
        entry: [{ messaging: [{ message: { text: "hi" } }, { read: {} }] }],
      }),
    );
    expect(parsed).toEqual({ updates: [], only: false });
    expect(messengerDeliveries(event({ object: "x" }))).toBeNull();
  });
});

describe("twilioDeliveries", () => {
  const form = "application/x-www-form-urlencoded";

  it("reads a status callback", () => {
    expect(
      twilioDeliveries(
        event("MessageSid=SM1&MessageStatus=undelivered&ErrorCode=30003", form),
      ),
    ).toEqual({
      only: true,
      updates: [{ externalId: "SM1", status: "failed", error: "30003" }],
    });
    expect(twilioDeliveries(event("SmsSid=SM2&SmsStatus=sent", form))).toEqual({
      only: true,
      updates: [{ externalId: "SM2", status: "sent" }],
    });
  });

  it("ignores messages and other bodies", () => {
    expect(
      twilioDeliveries(
        event("MessageSid=SM1&MessageStatus=received&Body=hi", form),
      ),
    ).toBeNull();
    expect(
      twilioDeliveries(event("MessageSid=SM1&MessageStatus=what", form)),
    ).toBeNull();
    expect(twilioDeliveries(event("{}"))).toBeNull();
    expect(twilioDeliveries({ body: "", headers: {} })).toBeNull();
  });
});

it("maps adapters to parsers", () => {
  expect(DELIVERY_PARSERS["instagram"]).toBe(messengerDeliveries);
  expect(DELIVERY_PARSERS["sms"]).toBe(twilioDeliveries);
});
