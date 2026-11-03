import type { ToolSet } from "ai";

import { describe, expectTypeOf, it } from "vitest";

import type { AgentRuntimeOptions } from "../../../src/ai-sdk/agents/index.ts";
import type {
  WorkflowAgentRuntimeOptions,
  WorkflowOmittedOptions,
} from "../../../src/ai-sdk/workflow/index.ts";

import { createWorkflowAgentRuntime } from "../../../src/ai-sdk/workflow/index.ts";

describe("createWorkflowAgentRuntime types", () => {
  it("takes the agent runtime options and the approval secret", () => {
    expectTypeOf<WorkflowAgentRuntimeOptions>().toExtend<
      Omit<AgentRuntimeOptions, WorkflowOmittedOptions>
    >();

    expectTypeOf<
      WorkflowAgentRuntimeOptions["toolApprovalSecret"]
    >().toEqualTypeOf<{ readonly environmentVariable: string } | undefined>();
  });

  it("returns a WorkflowAgent over the tool set", () => {
    expectTypeOf(createWorkflowAgentRuntime).returns.toHaveProperty("stream");
    expectTypeOf(createWorkflowAgentRuntime).returns.toHaveProperty("tools");

    expectTypeOf<
      ReturnType<typeof createWorkflowAgentRuntime>["tools"]
    >().toEqualTypeOf<ToolSet>();
  });
});
