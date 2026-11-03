import type { WorkflowAgent } from "@ai-sdk/workflow";
import type { ToolSet } from "ai";

import { describe, expectTypeOf, it } from "vitest";

import type { AgentRuntimeOptions } from "../../../src/ai-sdk/agents/index.ts";
import type { WorkflowAgentRuntimeOptions } from "../../../src/ai-sdk/workflow/index.ts";

import { createWorkflowAgentRuntime } from "../../../src/ai-sdk/workflow/index.ts";

describe("createWorkflowAgentRuntime types", () => {
  it("takes the agent runtime options and the approval secret", () => {
    expectTypeOf<WorkflowAgentRuntimeOptions>().toExtend<AgentRuntimeOptions>();

    expectTypeOf<
      WorkflowAgentRuntimeOptions["toolApprovalSecret"]
    >().toEqualTypeOf<{ readonly environmentVariable: string } | undefined>();
  });

  it("returns a WorkflowAgent over the tool set", () => {
    expectTypeOf(createWorkflowAgentRuntime).returns.toExtend<WorkflowAgent>();
  });
});
