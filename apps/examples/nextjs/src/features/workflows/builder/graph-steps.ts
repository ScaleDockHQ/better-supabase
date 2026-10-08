import {
  createBuilder,
  type GraphStepCall,
  rpcTransport,
} from "better-supabase/blocks/workflow-builder";
import { createWorkflows } from "better-supabase/blocks/workflows";
import { vaultCredentials } from "better-supabase/credentials";
import { nodeRunReporter } from "better-supabase/workflow-sdk/builder";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";
import { getWorkflowMetadata } from "workflow";

import { serviceNotifications, serviceSupabase } from "../workflow-steps";
import { stepLibrary } from "./step-library";

/** The service-role builder steps record node status and resolve credentials with. */
function stepBuilder() {
  const transport = rpcTransport(serviceSupabase(), { schema: "api" });
  return createBuilder({
    transport,
    schema: "api",
    steps: stepLibrary,
    credentials: vaultCredentials({ transport, schema: "api" }),
    temporal: Temporal,
  });
}

const report = <T>(call: GraphStepCall, run: () => Promise<T>) =>
  nodeRunReporter(stepBuilder().nodeRuns)(call, run);

const Text = v.fallback(v.string(), "");
const SummaryInput = v.fallback(v.object({ text: v.string() }), { text: "" });

/** A config field as text; anything that isn't a string reads as empty. */
const text = (config: GraphStepCall["config"], key: string): string =>
  v.parse(Text, config[key]);

/** The run's tenant and actor, from the registry: graph steps get no request context. */
async function runOwner() {
  const { workflowRunId } = getWorkflowMetadata();
  const run = await createWorkflows({
    transport: rpcTransport(serviceSupabase(), { schema: "api" }),
    schema: "api",
    temporal: Temporal,
  })
    .runs.get(workflowRunId)
    .orThrow();
  return { tenant: run?.tenant, actor: run?.actor };
}

export async function notifyMember(call: GraphStepCall): Promise<boolean> {
  "use step";
  return report(call, async () => {
    const { tenant, actor } = await runOwner();
    if (tenant === undefined || actor === undefined) return false;
    await serviceNotifications()
      .send("workflow.message", {
        tenant,
        recipients: [actor],
        includeActor: true,
        data: { title: text(call.config, "title").slice(0, 200) },
      })
      .orThrow();
    return true;
  });
}

export async function summarizeText(call: GraphStepCall) {
  "use step";
  return report(call, () => {
    const trimmed = v.parse(SummaryInput, call.input).text.trim();
    return Promise.resolve({
      words: trimmed === "" ? 0 : trimmed.split(/\s+/u).length,
      sentences: trimmed.split(/[.!?]+/u).filter((part) => part.trim() !== "")
        .length,
    });
  });
}

/** Posts to Slack's API only, so a graph can't point the server at another host. */
export async function postToSlack(call: GraphStepCall): Promise<boolean> {
  "use step";
  return report(call, async () => {
    const token = await stepBuilder()
      .credentials.resolve(text(call.config, "credential"))
      .orThrow();
    const response = await fetch("https://slack.com/api/chat.postMessage", {
      method: "POST",
      headers: { ...token.headers, "content-type": "application/json" },
      body: JSON.stringify({
        channel: text(call.config, "channel"),
        text: text(call.config, "text"),
      }),
    });
    if (!response.ok) throw new Error(`Slack answered ${response.status}`);
    return true;
  });
}

/** The library's step functions by step name. */
export const graphSteps = {
  "notify.member": notifyMember,
  "text.summarize": summarizeText,
  "slack.post": postToSlack,
};
