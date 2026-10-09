import { describe, expect, it } from "vitest";

import {
  AI_MESSAGE_PART_TYPES,
  AI_MESSAGE_SCHEMA_ID,
  aiMessageSchema,
  isAiMessage,
} from "../../../src/blocks/ai-chat/message.ts";

const validate = (value: unknown) =>
  aiMessageSchema["~standard"].validate(value);

describe("aiMessageSchema", () => {
  it("names the published JSON Schema and every part type", () => {
    expect(AI_MESSAGE_SCHEMA_ID).toBe(
      "https://unpkg.com/better-supabase/schemas/ai-message-v1.json",
    );
    expect(AI_MESSAGE_PART_TYPES).toHaveLength(9);
    expect(aiMessageSchema["~standard"]).toMatchObject({
      version: 1,
      vendor: "better-supabase",
    });
  });

  it("returns a valid message as it was given", () => {
    const message = {
      id: "m1",
      role: "assistant",
      metadata: { model: "openai/gpt-5" },
      parts: [
        { type: "step", boundary: "start" },
        { type: "text", text: "Hi", state: "done", providerMetadata: {} },
        { type: "tool-call", toolCallId: "t1", toolName: "x", input: null },
        { type: "tool-result", toolCallId: "t1", toolName: "x", output: 1 },
        { type: "data", name: "weather", data: { c: 20 }, id: undefined },
      ],
    };
    expect(validate(message)).toEqual({ value: message });
    expect(isAiMessage(message)).toBe(true);
  });

  it("reports each problem with its path", () => {
    expect(validate(null)).toEqual({
      issues: [{ message: "Expected a message object" }],
    });
    expect(
      validate({
        id: "",
        role: "bot",
        parts: [
          "text",
          { type: "nope" },
          { type: "text", text: 1, state: "later", extra: true },
          { type: "tool-approval", toolCallId: "t", approvalId: "a" },
          {
            type: "tool-call",
            toolCallId: "t",
            toolName: "x",
            input: 1,
            providerExecuted: "yes",
          },
          {
            type: "file",
            mediaType: "image/png",
            url: "x",
            providerMetadata: 1,
          },
        ],
        metadata: [],
        extra: 1,
      }),
    ).toEqual({
      issues: [
        { message: "Unknown message field", path: ["extra"] },
        { message: "Expected a non-empty id", path: ["id"] },
        { message: "Expected system, user, assistant or tool", path: ["role"] },
        { message: "Expected a part object", path: ["parts", 0] },
        {
          message: `Expected a part type: ${AI_MESSAGE_PART_TYPES.join(", ")}`,
          path: ["parts", 1, "type"],
        },
        { message: "Expected a string", path: ["parts", 2, "text"] },
        {
          message: "Expected one of streaming, done",
          path: ["parts", 2, "state"],
        },
        { message: "Unknown text part field", path: ["parts", 2, "extra"] },
        { message: "Required", path: ["parts", 3, "state"] },
        {
          message: "Expected a boolean",
          path: ["parts", 4, "providerExecuted"],
        },
        {
          message: "Expected an object",
          path: ["parts", 5, "providerMetadata"],
        },
        { message: "Expected an object", path: ["metadata"] },
      ],
    });
    expect(validate({ id: "m", role: "user", parts: {} })).toEqual({
      issues: [{ message: "Expected a parts array", path: ["parts"] }],
    });
    expect(isAiMessage({ id: "m", role: "user" })).toBe(false);
  });
});
