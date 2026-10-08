import { WorkflowAgent } from "@ai-sdk/workflow";
import { jsonSchema, tool } from "ai";
import {
  type DurableAgentArgs,
  durableTurn,
  type DurableTurnDeps,
  type DurableTurnInput,
  type DurableTurnResult,
} from "better-supabase/ai-sdk/workflow";
import { createHook, getWorkflowMetadata, getWritable } from "workflow";

import {
  answerQuestion,
  chatStep,
  deliverReport,
  recordRunStep,
} from "./durable-steps";

/** `durableTurn` on the Workflow SDK's functions and the app's step. */
function turn(
  input: DurableTurnInput,
  agent: DurableTurnDeps["agent"],
): Promise<DurableTurnResult> {
  return durableTurn(input, {
    runId: getWorkflowMetadata().workflowRunId,
    createHook,
    getWritable,
    agent,
    step: chatStep,
  });
}

/** One durable answer of the plain assistant. */
export async function assistantTurn(
  input: DurableTurnInput,
): Promise<DurableTurnResult> {
  "use workflow";
  return turn(input, (args) =>
    new WorkflowAgent({
      model: args.model,
      instructions: "You are a concise assistant inside a CRM sample app.",
    }).stream(args),
  );
}

/**
 * The research agent: it outlines sub-questions, answers each with a
 * subagent step and records its progress in `ai_run_steps`. Sending the
 * report needs the user's approval, which can wait for hours.
 */
export async function researchTurn(
  input: DurableTurnInput,
): Promise<DurableTurnResult> {
  "use workflow";
  return turn(input, (args) => researchAgent(input, args).stream(args));
}

function researchAgent(input: DurableTurnInput, args: DurableAgentArgs) {
  return new WorkflowAgent({
    model: args.model,
    instructions: [
      "You research a question for a CRM user.",
      "First call outline with three to five sub-questions, then call research once per sub-question,",
      "then write the report and offer to send it with sendReport.",
    ].join(" "),
    tools: {
      outline: tool({
        description: "Saves the sub-questions the research will answer.",
        inputSchema: jsonSchema<{ questions: string[] }>({
          type: "object",
          properties: {
            questions: { type: "array", items: { type: "string" } },
          },
          required: ["questions"],
        }),
        execute: async ({ questions }) => {
          await recordRunStep(args.runId, {
            key: "outline",
            label: "Outline",
            status: "done",
            detail: { questions },
          });
          return { saved: questions.length };
        },
      }),
      research: tool({
        description: "Answers one sub-question.",
        inputSchema: jsonSchema<{ question: string }>({
          type: "object",
          properties: { question: { type: "string" } },
          required: ["question"],
        }),
        execute: async ({ question }, { toolCallId }) => {
          await recordRunStep(args.runId, { key: toolCallId, label: question });
          const answer = await answerQuestion(args.model, question);
          await recordRunStep(args.runId, {
            key: toolCallId,
            status: "done",
            detail: { answer: answer.slice(0, 500) },
          });
          return answer;
        },
      }),
      sendReport: tool({
        description: "Sends the finished report's title to the user.",
        inputSchema: jsonSchema<{ title: string }>({
          type: "object",
          properties: { title: { type: "string" } },
          required: ["title"],
        }),
        // oxlint-disable-next-line typescript/no-deprecated -- WorkflowAgent reads approvals only from the tool, not from stream options.
        needsApproval: true,
        execute: async ({ title }) => {
          await deliverReport(input.organizationId, input.userId, title);
          await recordRunStep(args.runId, {
            key: "report",
            label: "Report sent",
            status: "done",
            detail: { title },
          });
          return { sent: true };
        },
      }),
    },
  });
}
