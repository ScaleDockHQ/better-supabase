import "server-only";
import {
  type DurableChat,
  durableChat,
  type DurableChatContext,
} from "better-supabase/ai-sdk/workflow";
import { postgresStreamStore } from "better-supabase/streams";
import * as v from "valibot";

import {
  aiRuns,
  assistant,
  assistantContext,
  serviceTransport,
} from "../assistant-server";
import { assistantTurn, researchTurn } from "./durable-workflows";

/** `sql.modules["ai-chat"].api` and `streams.api`. */
const API_SCHEMA = "api";

/** The agents a durable chat can run; the client sends one as `agent`. */
export type DurableAgent = "assistant" | "research";

const instances = new Map<DurableAgent, DurableChat>();

/** One durable chat per agent and process. */
export function durable(agent: DurableAgent = "assistant"): DurableChat {
  let instance = instances.get(agent);
  if (instance === undefined) {
    instance = durableChat({
      assistant: assistant(),
      workflow: agent === "research" ? researchTurn : assistantTurn,
      streams: postgresStreamStore({
        transport: serviceTransport(),
        schema: API_SCHEMA,
        wake: "poll",
      }),
    });
    instances.set(agent, instance);
  }
  return instance;
}

const AgentBody = v.object({
  agent: v.optional(v.picklist(["assistant", "research"]), "assistant"),
});

/** The agent a POST body asks for; anything else is the plain assistant. */
export async function agentOf(request: Request): Promise<DurableAgent> {
  const body = v.safeParse(
    AgentBody,
    await request
      .clone()
      .json()
      .catch(() => null),
  );
  return body.success ? body.output.agent : "assistant";
}

type UserClient = Parameters<typeof assistantContext>[0];

/** The per-request context of a signed-in member of `organizationId`. */
export function durableContext(
  supabase: UserClient,
  userId: string,
  organizationId: string,
): DurableChatContext {
  return {
    ...assistantContext(supabase, userId, organizationId),
    runs: aiRuns(supabase),
  };
}
