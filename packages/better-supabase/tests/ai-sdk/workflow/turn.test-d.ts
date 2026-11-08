import type { UIMessage } from "ai";

import { describe, expectTypeOf, it } from "vitest";

import type {
  DurableTurnAgentOptions,
  DurableTurnAgentResult,
  DurableChatOptions,
  DurableTurnDeps,
  DurableTurnInput,
} from "../../../src/ai-sdk/workflow/index.ts";

interface Settings {
  readonly projectId: string;
}

type Chat = UIMessage<{ model: string }>;

describe("durable turn types", () => {
  it("carries the context from the input to the agent", () => {
    expectTypeOf<DurableTurnInput<Settings>["context"]>().toEqualTypeOf<
      Settings | undefined
    >();

    expectTypeOf<DurableTurnAgentOptions<Settings>["context"]>().toEqualTypeOf<
      Settings | undefined
    >();

    expectTypeOf<DurableTurnDeps<Settings>["agent"]>()
      .parameter(0)
      .toEqualTypeOf<DurableTurnAgentOptions<Settings>>();
  });

  it("gives the agent the user and the tenant", () => {
    expectTypeOf<DurableTurnAgentOptions["userId"]>().toEqualTypeOf<string>();
    expectTypeOf<DurableTurnAgentOptions["organizationId"]>().toEqualTypeOf<
      string | undefined
    >();
  });

  it("accepts an error on the agent result", () => {
    expectTypeOf<DurableTurnAgentResult["error"]>().toEqualTypeOf<unknown>();
  });

  it("builds the context from the turn of the app's UI message type", () => {
    type Build = NonNullable<DurableChatOptions<Chat, Settings>["context"]>;

    expectTypeOf<Parameters<Build>[1]["uiMessages"]>().toEqualTypeOf<Chat[]>();
  });
});
