import { describe, expectTypeOf, it } from "vitest";

import type { AgentRuntimeOptions } from "../../../src/ai-sdk/agents/index.ts";
import type { ConnectToolsOptions } from "../../../src/ai-sdk/mcp/index.ts";

describe("agent runtime options", () => {
  it("takes the AI SDK 7 settings", () => {
    expectTypeOf<AgentRuntimeOptions["toolApprovalSecret"]>().toEqualTypeOf<
      string | Uint8Array | undefined
    >();
    expectTypeOf<AgentRuntimeOptions>().toHaveProperty("prepareCall");
    expectTypeOf<AgentRuntimeOptions>().toHaveProperty("prepareStep");
    expectTypeOf<AgentRuntimeOptions>().toHaveProperty("compact");
    expectTypeOf<
      NonNullable<AgentRuntimeOptions["settings"]>["toolCallConcurrency"]
    >().toEqualTypeOf<number | undefined>();
  });

  it("takes MCP retries and the approval switch", () => {
    expectTypeOf<ConnectToolsOptions["maxRetries"]>().toEqualTypeOf<
      number | undefined
    >();
    expectTypeOf<ConnectToolsOptions["askUnlessReadOnly"]>().toEqualTypeOf<
      boolean | undefined
    >();
  });
});
