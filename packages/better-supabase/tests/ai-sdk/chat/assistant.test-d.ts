import type { UIMessage } from "ai";

import { describe, expectTypeOf, it } from "vitest";

import type {
  Assistant,
  AssistantRunOptions,
  AssistantTurn,
} from "../../../src/ai-sdk/chat/index.ts";

import { createAssistant } from "../../../src/ai-sdk/chat/index.ts";

type Chat = UIMessage<{ model: string }, { note: { text: string } }>;

declare const streams: Parameters<typeof createAssistant>[0]["streams"];

describe("createAssistant types", () => {
  it("carries the app's UI message type to run, onFinish and the turn", () => {
    const assistant = createAssistant<Chat>({
      streams,
      defaultModel: "openai/gpt-5",
      toolApprovalSecret: "secret",
      run: (args) => {
        expectTypeOf(args).toEqualTypeOf<AssistantRunOptions<Chat>>();
        expectTypeOf(args.uiMessages).toEqualTypeOf<Chat[]>();
        expectTypeOf(args.toolApprovalSecret).toEqualTypeOf<
          string | Uint8Array | undefined
        >();
        expectTypeOf(args.continuationOf).toEqualTypeOf<string | undefined>();

        return {};
      },
      onFinish: (finish) => {
        expectTypeOf(finish.message).toEqualTypeOf<Chat>();
      },
    });

    expectTypeOf(assistant).toEqualTypeOf<Assistant<Chat>>();
    expectTypeOf<AssistantTurn<Chat>["uiMessages"]>().toEqualTypeOf<Chat[]>();
    expectTypeOf<AssistantTurn["continuationOf"]>().toEqualTypeOf<
      string | undefined
    >();
  });

  it("is not the app type without a generic", () => {
    expectTypeOf<Assistant>().not.toEqualTypeOf<Assistant<Chat>>();
  });
});
