import { describe, expect, it } from "vitest";

import {
  whatsappInteractive,
  whatsappInteractiveOf,
} from "../../src/chat-sdk/index.ts";

const body = (messages: unknown[]) => ({
  object: "whatsapp_business_account",
  entry: [
    {
      changes: [
        {
          value: {
            contacts: [{ wa_id: "3199", profile: { name: "Ada" } }],
            messages,
          },
        },
      ],
    },
  ],
});

const button = {
  from: "3199",
  id: "wamid.1",
  type: "interactive",
  context: { id: "wamid.0" },
  interactive: {
    type: "button_reply",
    button_reply: { id: "approve", title: "Approve" },
  },
};

const row = {
  from: "3199",
  id: "wamid.2",
  type: "interactive",
  interactive: {
    type: "list_reply",
    list_reply: { id: "r1", title: "Plan A", description: "monthly" },
  },
};

const quick = {
  from: "3199",
  id: "wamid.3",
  type: "button",
  button: { payload: "stop", text: "Stop" },
};

describe("whatsappInteractiveOf", () => {
  it("reads button replies, list replies and template quick replies", () => {
    expect(whatsappInteractiveOf(body([button, row, quick]))).toEqual([
      {
        kind: "button_reply",
        actionId: "approve",
        title: "Approve",
        from: "3199",
        name: "Ada",
        messageId: "wamid.1",
        contextMessageId: "wamid.0",
      },
      {
        kind: "list_reply",
        actionId: "r1",
        title: "Plan A",
        description: "monthly",
        from: "3199",
        name: "Ada",
        messageId: "wamid.2",
      },
      {
        kind: "quick_reply",
        actionId: "stop",
        title: "Stop",
        from: "3199",
        name: "Ada",
        messageId: "wamid.3",
      },
    ]);
  });

  it("accepts the raw body and skips text messages and other payloads", () => {
    const text = { from: "3199", id: "wamid.4", type: "text", text: {} };

    expect(
      whatsappInteractiveOf(JSON.stringify(body([text, button]))),
    ).toHaveLength(1);
    expect(whatsappInteractiveOf("not json")).toEqual([]);
    expect(whatsappInteractiveOf({ object: "page" })).toEqual([]);
    expect(whatsappInteractiveOf(body([]))).toEqual([]);
  });

  it("says when a body holds nothing but replies", () => {
    const text = { from: "3199", id: "wamid.4", type: "text", text: {} };

    expect(
      whatsappInteractive({ body: JSON.stringify(body([button])) })?.only,
    ).toBe(true);
    expect(
      whatsappInteractive({ body: JSON.stringify(body([button, text])) })?.only,
    ).toBe(false);
    expect(whatsappInteractive({ body: "{}" })).toBeNull();
  });
});
