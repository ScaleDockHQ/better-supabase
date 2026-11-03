import type { ToolSet } from "ai";

import { WorkflowAgent } from "@ai-sdk/workflow";
import { isStepCount } from "ai";

import type {
  AgentRuntimeOptions,
  AgentRuntimeParts,
} from "../agents/agents.ts";
import type { AgentRunContext } from "../agents/authorization.ts";

import { agentRuntimeParts } from "../agents/agents.ts";

export interface WorkflowAgentRuntimeOptions extends AgentRuntimeOptions {
  /**
   * The environment variable that holds the HMAC secret for tool approvals
   * (`experimental_toolApprovalSecret`). Only the name crosses workflow
   * boundaries.
   */
  readonly toolApprovalSecret?: { readonly environmentVariable: string };
}

type ApprovalCheck = (
  name: string,
  input: unknown,
) => Promise<"approved" | "user-approval" | "not-applicable">;

/**
 * `WorkflowAgent` has no `toolApproval` setting, so the policy runs inside each
 * tool: `needsApproval` asks the user for the `ask` tools and for any call the
 * app's check turns into `user-approval`, and a denied call throws.
 */
function approvalCheck(parts: AgentRuntimeParts): ApprovalCheck | undefined {
  const { toolApproval } = parts;

  if (typeof toolApproval !== "function") {
    return undefined;
  }

  return async (name, input) => {
    // SAFETY: the composed check reads only the tool name and the input.
    const status = await toolApproval({
      toolCall: { toolName: name, input },
    } as never);

    const type = typeof status === "string" ? status : status?.type;

    if (type === "denied") {
      const reason =
        typeof status === "object" && status.type === "denied"
          ? status.reason
          : undefined;

      throw new Error(reason ?? "The tool call was denied");
    }

    return type === "user-approval" ? "user-approval" : "not-applicable";
  };
}

/** The agent's tools with its approval policy as each tool's `needsApproval`. */
function guardedTools(parts: AgentRuntimeParts): ToolSet {
  const check = approvalCheck(parts);
  const tools: ToolSet = {};

  for (const [name, tool] of Object.entries(parts.tools)) {
    const asked = parts.ask[name] !== undefined;

    tools[name] = {
      ...tool,
      // WorkflowAgent has no toolApproval setting; needsApproval is its only hook.
      // oxlint-disable-next-line typescript/no-deprecated
      needsApproval:
        check === undefined
          ? asked
          : async (input: unknown) =>
              (await check(name, input)) === "user-approval",
    };
  }

  return tools;
}

/**
 * A `WorkflowAgent` from an agent row, with the same tools, instructions,
 * runtime context, gateway attribution and model check as `createAgentRuntime`.
 * The tenant's `ask` tools and high-risk operations wait for the user, and
 * `toolApprovalSecret` signs the requests.
 */
export function createWorkflowAgentRuntime(
  options: WorkflowAgentRuntimeOptions,
): WorkflowAgent<ToolSet, AgentRunContext> {
  const { agent } = options;
  const parts = agentRuntimeParts(options);

  return new WorkflowAgent<ToolSet, AgentRunContext>({
    id: agent.id,
    model: options.model(agent.model),
    tools: guardedTools(parts),
    ...(parts.instructions === "" ? {} : { instructions: parts.instructions }),
    stopWhen: options.stopWhen ?? isStepCount(20),
    runtimeContext: parts.run,
    ...(options.toolApprovalSecret === undefined
      ? {}
      : { experimental_toolApprovalSecret: options.toolApprovalSecret }),
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
