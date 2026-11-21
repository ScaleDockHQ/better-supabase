import type { ToolSet } from "ai";

import { WorkflowAgent } from "@ai-sdk/workflow";
import { isStepCount } from "ai";

import type { AgentRuntimeOptions } from "../agents/agents.ts";
import type { AgentRunContext } from "../agents/authorization.ts";

import { agentRuntimeParts } from "../agents/agents.ts";

/** The `createAgentRuntime` options a `WorkflowAgent` has no setting for. */
export type WorkflowOmittedOptions =
  | "compact"
  | "prepareCall"
  | "prepareStep"
  | "settings"
  | "telemetry"
  | "toolApprovalSecret";

export interface WorkflowAgentRuntimeOptions extends Omit<
  AgentRuntimeOptions,
  WorkflowOmittedOptions
> {
  /**
   * The environment variable that holds the HMAC secret for tool approvals
   * (`experimental_toolApprovalSecret`). Only the name crosses workflow
   * boundaries.
   */
  readonly toolApprovalSecret?: { readonly environmentVariable: string };
}

/**
 * A `WorkflowAgent` from an agent row, with the same tools, instructions,
 * runtime context, gateway attribution and model check as `createAgentRuntime`.
 * The tenant's `ask` tools and high-risk operations wait for the user through
 * the agent's `toolApproval` setting, which runs in workflow context, and
 * `toolApprovalSecret` signs the requests. A denied call becomes an
 * `execution-denied` tool result that the model sees, not a thrown error.
 */
export function createWorkflowAgentRuntime(
  options: WorkflowAgentRuntimeOptions,
): WorkflowAgent<ToolSet, AgentRunContext> {
  const { toolApprovalSecret, ...shared } = options;
  const { agent } = shared;
  const parts = agentRuntimeParts({ ...shared, agent });

  return new WorkflowAgent<ToolSet, AgentRunContext>({
    id: agent.id,
    model: options.model(agent.model),
    tools: parts.tools,
    toolApproval: parts.toolApproval,
    ...(parts.instructions === "" ? {} : { instructions: parts.instructions }),
    stopWhen: options.stopWhen ?? isStepCount(20),
    runtimeContext: parts.run,
    ...(toolApprovalSecret === undefined
      ? {}
      : { experimental_toolApprovalSecret: toolApprovalSecret }),
    prepareCall: (call) => {
      const providerOptions = parts.withGateway(call.providerOptions);

      return providerOptions === undefined ? {} : { providerOptions };
    },
    prepareStep: async ({ model }) => {
      await parts.checkModel(model);

      return {};
    },
  });
}
