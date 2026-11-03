import type { StateAdapter } from "chat";

import { describe, expectTypeOf, it } from "vitest";

import type {
  ChatInboundStore,
  ChatWebhookSink,
  InboxAdapter,
  SupabaseState,
} from "../../src/chat-sdk/index.ts";

import { createSupabaseState } from "../../src/chat-sdk/index.ts";

describe("chat-sdk types", () => {
  it("builds a Chat SDK StateAdapter", () => {
    expectTypeOf(createSupabaseState).returns.toExtend<StateAdapter>();
    expectTypeOf<SupabaseState>().toExtend<StateAdapter>();
  });

  it("keeps the inbound store contract at version 1", () => {
    expectTypeOf<ChatInboundStore["apiVersion"]>().toEqualTypeOf<1>();
    expectTypeOf<ChatInboundStore["lastInboundAt"]>().returns.toEqualTypeOf<
      Promise<Temporal.Instant | null>
    >();
  });

  it("takes any sink with a store method", () => {
    expectTypeOf<ChatWebhookSink["store"]>().returns.toEqualTypeOf<
      PromiseLike<unknown>
    >();
  });

  it("gives the inbox adapter action and reaction dispatch", () => {
    expectTypeOf<InboxAdapter["dispatchAction"]>().returns.toEqualTypeOf<
      Promise<void>
    >();
    expectTypeOf<InboxAdapter["dispatchReaction"]>().returns.toEqualTypeOf<
      Promise<void>
    >();
  });
});
