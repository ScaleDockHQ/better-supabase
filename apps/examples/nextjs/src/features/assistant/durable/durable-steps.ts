import { generateText } from "ai";
import {
  type DurableStepInput,
  type DurableStepName,
  type DurableStepOutput,
  runDurableStep,
} from "better-supabase/ai-sdk/workflow";
import {
  type AiRunStepInput,
  createAiChat,
} from "better-supabase/blocks/ai-chat";
import { rpcTransport } from "better-supabase/blocks/organizations";
import { Temporal } from "temporal-polyfill";

import {
  serviceNotifications,
  serviceSupabase,
} from "../../workflows/workflow-steps";

/** `sql.modules["ai-chat"].api`. */
const API_SCHEMA = "api";

/**
 * Steps run in the workflow's step route, outside any request, so the chat
 * block acts through the service role. The step bundle doesn't load
 * `@/lib/supabase`, so it passes Temporal itself.
 */
function serviceOptions() {
  return {
    transport: rpcTransport(serviceSupabase(), { schema: API_SCHEMA }),
    schema: API_SCHEMA,
    temporal: Temporal,
  };
}

/** The durable turn's one step function: save, approvals, decisions and release. */
export async function chatStep<K extends DurableStepName>(
  name: K,
  input: DurableStepInput<K>,
): Promise<DurableStepOutput<K>> {
  "use step";
  return runDurableStep(createAiChat(serviceOptions()), name, input);
}

/** Records one step of a research run in `ai_run_steps`, for the activity console. */
export async function recordRunStep(
  runId: string,
  step: AiRunStepInput,
): Promise<void> {
  "use step";
  await createAiChat(serviceOptions()).runs.steps.record(runId, step).orThrow();
}

/** The research agent's subagent: answers one question on its own. */
export async function answerQuestion(
  model: string,
  question: string,
): Promise<string> {
  "use step";
  const { text } = await generateText({
    model,
    instructions:
      "Answer the question in at most five sentences. Say when you are unsure.",
    prompt: question,
  });
  return text;
}

/** Sends the research report's title to the chat's owner as a notification. */
export async function deliverReport(
  organizationId: string,
  userId: string,
  title: string,
): Promise<void> {
  "use step";
  await serviceNotifications()
    .send("workflow.message", {
      tenant: organizationId,
      recipients: [userId],
      includeActor: true,
      data: { title },
    })
    .orThrow();
}
