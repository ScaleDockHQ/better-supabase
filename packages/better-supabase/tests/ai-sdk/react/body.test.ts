import type { UIMessage } from "ai";

import { describe, expect, it } from "vitest";

import { assistantBody } from "../../../src/ai-sdk/react/body.ts";

const message = (id: string, role: UIMessage["role"]): UIMessage => ({
  id,
  role,
  parts: [{ type: "text", text: id }],
});

describe("assistantBody", () => {
  it("sends the newest user message with the request's fields over the config's", () => {
    expect(
      assistantBody(
        {
          api: "/api/chat",
          model: "openai/gpt-5",
          body: { organizationId: "org-1", trigger: "ignored" },
          headers: undefined,
        },
        {
          id: "c1",
          messages: [
            message("u1", "user"),
            message("u2", "user"),
            message("a1", "assistant"),
          ],
          body: { organizationId: "org-2" },
          trigger: "submit-message",
          messageId: "u2",
        },
      ),
    ).toEqual({
      organizationId: "org-2",
      id: "c1",
      message: message("u2", "user"),
      trigger: "submit-message",
      messageId: "u2",
      model: "openai/gpt-5",
    });
  });

  it("leaves out the model, message id and message when there are none", () => {
    expect(
      assistantBody(
        { api: "/api/chat", model: undefined, body: undefined, headers: {} },
        {
          id: "c1",
          messages: [message("a1", "assistant")],
          trigger: "regenerate-message",
        },
      ),
    ).toEqual({
      id: "c1",
      message: undefined,
      trigger: "regenerate-message",
    });
  });
});
