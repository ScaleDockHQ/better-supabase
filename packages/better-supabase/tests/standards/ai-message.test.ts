import Ajv2020 from "ajv/dist/2020.js";
import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import {
  AI_MESSAGE_PART_TYPES,
  AI_MESSAGE_SCHEMA_ID,
  aiMessageSchema,
  isAiMessage,
} from "../../src/blocks/ai-chat/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { validate } from "../../src/core/standard.ts";

const schema = JSON.parse(
  await readFile(
    new URL("../../schemas/ai-message-v1.json", import.meta.url),
    "utf8",
  ),
) as Record<string, unknown>;
const ajv = new Ajv2020({ strict: true, allErrors: true });
const jsonSchema = ajv.compile(schema);

const message = (parts: unknown[], extra: object = {}) => ({
  id: "m1",
  role: "assistant",
  parts,
  ...extra,
});

const VALID: readonly unknown[] = [
  message([{ type: "text", text: "Hello", state: "done" }], {
    metadata: { model: "gpt" },
  }),
  message([{ type: "reasoning", text: "...", providerMetadata: { a: 1 } }]),
  message([{ type: "file", mediaType: "image/png", url: "https://x/a.png" }]),
  message([
    { type: "step", boundary: "start", stepId: "s1" },
    {
      type: "tool-call",
      toolCallId: "c1",
      toolName: "weather",
      input: { city: "Utrecht" },
    },
    {
      type: "tool-approval",
      toolCallId: "c1",
      approvalId: "a1",
      state: "approved",
    },
    {
      type: "tool-result",
      toolCallId: "c1",
      toolName: "weather",
      output: null,
      isError: false,
    },
    { type: "step", boundary: "finish" },
  ]),
  message([{ type: "source", sourceType: "url", id: "s", url: "https://x" }]),
  message([{ type: "data", name: "weather", data: [1, 2] }]),
  { id: "u1", role: "user", parts: [] },
];

const INVALID: readonly unknown[] = [
  "text",
  { id: "", role: "user", parts: [] },
  { id: "m", role: "robot", parts: [] },
  { id: "m", role: "user" },
  { id: "m", role: "user", parts: [], extra: true },
  { id: "m", role: "user", parts: [], metadata: [] },
  message([{ type: "image", url: "x" }]),
  message([{ type: "text" }]),
  message([{ type: "text", text: 1 }]),
  message([{ type: "text", text: "x", state: "half" }]),
  message([{ type: "text", text: "x", colour: "red" }]),
  message([{ type: "text", text: "x", providerMetadata: "x" }]),
  message([{ type: "tool-call", toolCallId: "c", toolName: "t" }]),
  message([
    {
      type: "tool-result",
      toolCallId: "c",
      toolName: "t",
      isError: 1,
      output: 1,
    },
  ]),
  message([
    { type: "tool-approval", toolCallId: "c", approvalId: "a", state: "maybe" },
  ]),
  message([{ type: "source", sourceType: "page", id: "s" }]),
  message([{ type: "data", name: "x" }]),
  message([{ type: "step", boundary: "middle" }]),
  message(["text"]),
];

describe("AI message v1", () => {
  it("is the pinned version", () => {
    expect(SPEC_PINS.aiMessage).toBe("1");
    expect(schema["$id"]).toBe(AI_MESSAGE_SCHEMA_ID);
    expect(AI_MESSAGE_SCHEMA_ID).toContain(
      `ai-message-v${SPEC_PINS.aiMessage}.json`,
    );
  });

  it("lists every part type in the JSON Schema", () => {
    const defs = schema["$defs"] as Record<
      string,
      { properties?: { type?: { const?: string } } }
    >;
    const types = Object.values(defs).flatMap((def) =>
      def.properties?.type?.const === undefined
        ? []
        : [def.properties.type.const],
    );
    expect(types.toSorted()).toEqual([...AI_MESSAGE_PART_TYPES].toSorted());
  });

  it.each(VALID.map((value, index) => [index, value] as const))(
    "accepts valid message %i in both validators",
    async (_index, value) => {
      expect(jsonSchema(value)).toBe(true);
      expect(isAiMessage(value)).toBe(true);
      expect((await validate(aiMessageSchema, value)).ok).toBe(true);
    },
  );

  it.each(INVALID.map((value, index) => [index, value] as const))(
    "refuses invalid message %i in both validators",
    async (_index, value) => {
      expect(jsonSchema(value)).toBe(false);
      expect(isAiMessage(value)).toBe(false);
      const result = await validate(aiMessageSchema, value, "message");
      expect(result.ok ? undefined : result.error.kind).toBe("validation");
    },
  );

  it("points at the failing field", async () => {
    const result = await validate(
      aiMessageSchema,
      message([
        { type: "text", text: "a" },
        { type: "data", name: "x" },
      ]),
    );
    expect(
      result.ok || result.error.kind !== "validation"
        ? undefined
        : result.error.issues,
    ).toEqual([{ message: "Required", path: ["parts", 1, "data"] }]);
  });
});
