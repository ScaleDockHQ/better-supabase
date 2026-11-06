import type { ChatTransport, UIMessage } from "ai";

import { describe, expectTypeOf, it } from "vitest";

import type {
  DurableTransportOptions,
  UseDurableAssistantOptions,
} from "../../../src/ai-sdk/workflow-react/index.ts";

import {
  durableTransport,
  useDurableAssistant,
} from "../../../src/ai-sdk/workflow-react/index.ts";

type Chat = UIMessage<{ model: string }, { note: { text: string } }>;

declare const config: Parameters<typeof durableTransport>[0];

describe("durable client types", () => {
  it("carries the app's UI message type through the transport", () => {
    const transport = durableTransport<Chat>(config, {
      prepareSendMessagesRequest: (request) => {
        expectTypeOf(request.messages).toEqualTypeOf<Chat[]>();

        return { body: {} };
      },
    });

    expectTypeOf(transport).toEqualTypeOf<ChatTransport<Chat>>();
  });

  it("takes every Workflow SDK transport option except api", () => {
    expectTypeOf<DurableTransportOptions>().not.toHaveProperty("api");
    expectTypeOf<DurableTransportOptions>().toHaveProperty("fetch");
    expectTypeOf<DurableTransportOptions>().toHaveProperty("onChatEnd");
    expectTypeOf<DurableTransportOptions>().toHaveProperty("initialStartIndex");

    expectTypeOf<DurableTransportOptions>().toHaveProperty(
      "prepareReconnectToStreamRequest",
    );
  });

  it("types the hook by the UI message", () => {
    expectTypeOf<
      UseDurableAssistantOptions<Chat>["transportOptions"]
    >().toEqualTypeOf<DurableTransportOptions<Chat> | undefined>();

    expectTypeOf(useDurableAssistant<Chat>).returns.toHaveProperty("messages");
  });
});
