import type { DynamicToolUIPart, UIMessage } from "ai";

import { describe, expectTypeOf, it } from "vitest";

import type { UIMessageSchemas } from "../../src/ai-sdk/index.ts";
import type { AiMessage } from "../../src/blocks/ai-chat/index.ts";

import {
  fromUIMessage,
  toUIMessage,
  toUIMessages,
  validUIMessages,
} from "../../src/ai-sdk/index.ts";

type Chat = UIMessage<
  { turn: number },
  { weather: { temp: number } },
  { search: { input: { q: string }; output: { hits: number } } }
>;

describe("ai-sdk messages types", () => {
  it("defaults to UIMessage and follows the app's UI_MESSAGE", () => {
    expectTypeOf(toUIMessage).returns.toEqualTypeOf<UIMessage>();
    expectTypeOf(toUIMessage<Chat>).returns.toEqualTypeOf<Chat>();
    expectTypeOf(toUIMessages<Chat>).returns.toEqualTypeOf<Chat[]>();
    expectTypeOf(fromUIMessage<Chat>)
      .parameter(0)
      .toEqualTypeOf<Chat>();
    expectTypeOf(fromUIMessage<Chat>).returns.toEqualTypeOf<AiMessage>();
  });

  it("types the schemas from the app's message", () => {
    expectTypeOf(validUIMessages<Chat>).returns.not.toBeAny();
    expectTypeOf<
      NonNullable<UIMessageSchemas<Chat>["dataSchemas"]>
    >().toHaveProperty("weather");
  });

  it("carries the AI SDK 7 tool fields on the canonical parts", () => {
    type Call = Extract<AiMessage["parts"][number], { type: "tool-call" }>;

    type Approval = Extract<
      AiMessage["parts"][number],
      { type: "tool-approval" }
    >;

    type Result = Extract<AiMessage["parts"][number], { type: "tool-result" }>;

    expectTypeOf<Call>().toHaveProperty("dynamic");
    expectTypeOf<Call>().toHaveProperty("toolMetadata");
    expectTypeOf<Call>().toHaveProperty("inputEncoding");
    expectTypeOf<Approval>().toHaveProperty("signature");
    expectTypeOf<Approval>().toHaveProperty("isAutomatic");
    expectTypeOf<Result>().toHaveProperty("preliminary");
    expectTypeOf<DynamicToolUIPart["toolMetadata"]>().not.toBeNever();
  });
});
