import type {
  GraphApprovalCall,
  GraphNodeCall,
  GraphStepCall,
} from "better-supabase/blocks/workflow-editor";
import type { NodeRunReportOptions } from "better-supabase/workflow-sdk/builder";

import { generateText } from "ai";
import { createApprovals } from "better-supabase/blocks/approvals";
import {
  createWorkflowEditor,
  rpcTransport,
} from "better-supabase/blocks/workflow-editor";
import { createWorkflows } from "better-supabase/blocks/workflows";
import { vaultCredentials } from "better-supabase/credentials";
import { nodeRunReporter } from "better-supabase/workflow-sdk/builder";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";
import { getWorkflowMetadata } from "workflow";

import { env } from "@/env";

import { serviceNotifications, serviceSupabase } from "../workflow-steps";
import {
  JsonObjectSchema,
  JsonSchema,
  readTemplatePath,
  resolveTemplates,
} from "./config-templates";
import { stepLibrary } from "./step-library";

/**
 * The service-role builder steps record node status and resolve credentials
 * with.
 */
function stepBuilder() {
  const transport = rpcTransport(serviceSupabase(), { schema: "api" });

  return createWorkflowEditor({
    transport,
    schema: "api",
    steps: stepLibrary,
    credentials: vaultCredentials({ transport, schema: "api" }),
    temporal: Temporal,
  });
}

const report = <T>(call: GraphStepCall, run: () => Promise<T>) =>
  nodeRunReporter(stepBuilder().nodeRuns)(call, run);

/**
 * Reports a node of the deployment's own kind under its node id. A waiting
 * node's first call (`waits`) records `waiting`; its resumed call records
 * `completed`.
 */
export const reportNode = <T>(
  call: GraphNodeCall,
  run: () => Promise<T>,
  options?: NodeRunReportOptions,
) =>
  nodeRunReporter(stepBuilder().nodeRuns)(
    { ...call, step: call.kind },
    run,
    options,
  );

const Text = v.fallback(v.string(), "");
const SummaryInput = v.fallback(v.object({ text: v.string() }), { text: "" });
const Config = v.fallback(v.record(v.string(), v.unknown()), {});

/** A config field as text; anything that isn't a string reads as empty. */
export const text = (config: GraphStepCall["config"], key: string): string =>
  v.parse(Text, config[key]);

/**
 * The call with the `{{ path }}` markers of its config filled in from the run's
 * data, so a node's inputs can come from the nodes before it.
 */
export function withConfig<Call extends GraphStepCall | GraphNodeCall>(
  call: Call,
): Call {
  const input = v.safeParse(JsonSchema, call.input);
  const results = v.safeParse(JsonObjectSchema, call.results);

  const scope = {
    input: input.success ? input.output : null,
    results: results.success ? results.output : {},
  };

  const config = v.parse(JsonObjectSchema, v.parse(Config, call.config));

  return { ...call, config: v.parse(Config, resolveTemplates(config, scope)) };
}

/**
 * The run's tenant and actor, from the registry: graph steps get no request
 * context.
 */
export async function runOwner() {
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

async function notifyMemberWork(call: GraphStepCall): Promise<boolean> {
  const { tenant, actor } = await runOwner();

  if (tenant === undefined || actor === undefined) {
    return false;
  }

  await serviceNotifications()
    .send({
      type: "workflow.message",
      input: {
        tenant,
        recipients: [actor],
        includeActor: true,
        data: { title: text(call.config, "title").slice(0, 200) },
      },
    })
    .orThrow();

  return true;
}

// oxlint-disable-next-line typescript/require-await -- every library step shares one async signature.
async function summarizeTextWork(call: GraphStepCall) {
  const trimmed = v.parse(SummaryInput, call.input).text.trim();

  return {
    words: trimmed === "" ? 0 : trimmed.split(/\s+/u).length,
    sentences: trimmed.split(/[.!?]+/u).filter((part) => part.trim() !== "")
      .length,
  };
}

// oxlint-disable-next-line typescript/require-await -- every library step shares one async signature.
async function formatTextWork(call: GraphStepCall) {
  return { text: text(call.config, "text") };
}

/** Posts to Slack's API only, so a graph can't point the server at another host. */
async function postToSlackWork(call: GraphStepCall): Promise<boolean> {
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

  if (!response.ok) {
    throw new Error(`Slack answered ${response.status}`);
  }

  return true;
}

/** The work of a library step by name, for the nodes that run steps inside them. */
function libraryStep(name: string) {
  switch (name) {
    case "notify.member": {
      return notifyMemberWork;
    }

    case "text.summarize": {
      return summarizeTextWork;
    }

    case "text.format": {
      return formatTextWork;
    }

    case "slack.post": {
      return postToSlackWork;
    }

    default: {
      throw new Error(`Unknown step ${name}`);
    }
  }
}

async function notifyMember(call: GraphStepCall): Promise<boolean> {
  "use step";

  return report(call, () => notifyMemberWork(withConfig(call)));
}

async function summarizeText(call: GraphStepCall) {
  "use step";

  return report(call, () => summarizeTextWork(withConfig(call)));
}

async function formatText(call: GraphStepCall) {
  "use step";

  return report(call, () => formatTextWork(withConfig(call)));
}

async function postToSlack(call: GraphStepCall): Promise<boolean> {
  "use step";

  return report(call, () => postToSlackWork(withConfig(call)));
}

/** The library's step functions by step name. */
export const graphSteps = {
  "notify.member": notifyMember,
  "text.summarize": summarizeText,
  "text.format": formatText,
  "slack.post": postToSlack,
};

const MAX_ITEMS = 100;

const asPath = (value: string): string => value.replaceAll(/[{}\s]/gu, "");

/** The `loop` node: one library step for each item of a list. */
async function loopNode(call: GraphNodeCall): Promise<readonly unknown[]> {
  "use step";

  return reportNode(call, async () => {
    const input = v.safeParse(JsonSchema, call.input);
    const results = v.safeParse(JsonObjectSchema, call.results);

    const scope = {
      input: input.success ? input.output : null,
      results: results.success ? results.output : {},
    };

    const listed = readTemplatePath(scope, asPath(text(call.config, "items")));

    const items = Array.isArray(listed)
      ? listed
      : listed === undefined || listed === null
        ? []
        : [listed];

    const max = Math.min(
      v.parse(v.fallback(v.number(), 25), call.config["max"]),
      MAX_ITEMS,
    );

    const name = text(call.config, "step");
    const work = libraryStep(name);
    const outputs: unknown[] = [];

    for (const item of items.slice(0, max)) {
      const inner: GraphStepCall = {
        node: call.node,
        step: name,
        config: v.parse(Config, call.config["stepConfig"]),
        input: item,
        results: call.results,
        runKey: call.runKey,
      };

      outputs.push(await work(withConfig(inner)));
    }

    return outputs;
  });
}

/** The `parallel` node: several library steps at the same time. */
async function parallelNode(call: GraphNodeCall) {
  "use step";

  return reportNode(call, async () => {
    const names = v.parse(
      v.fallback(v.array(v.string()), []),
      call.config["steps"],
    );

    const outputs = await Promise.all(
      names.map((name) =>
        libraryStep(name)(
          withConfig({
            node: call.node,
            step: name,
            config: {},
            input: call.input,
            results: call.results,
            runKey: call.runKey,
          }),
        ),
      ),
    );

    return Object.fromEntries(
      names.map((name, index) => [`${name}#${index + 1}`, outputs[index]]),
    );
  });
}

/** The payload a completed human task resumes its run with. */
const HumanTaskDone = v.object({ completedBy: v.string() });

/**
 * The `human-task` node: tells a member what to do and by when, then the run
 * waits (`waits: true`) until `completeHumanTask` resumes it. The resumed call
 * returns the task with who completed it.
 */
async function humanTaskNode(call: GraphNodeCall) {
  "use step";

  if (call.resumed !== undefined) {
    const done = v.safeParse(HumanTaskDone, call.resumed.payload);

    const task = v.parse(Config, call.resumed.output);

    // oxlint-disable-next-line typescript/require-await -- reportNode takes an async function.
    return reportNode(call, async () => ({
      ...task,
      completedBy: done.success ? done.output.completedBy : null,
    }));
  }

  return reportNode(
    call,
    async () => {
      const config = withConfig(call).config;
      const { tenant, actor } = await runOwner();
      const assignee = text(config, "assignee") || actor;

      if (tenant === undefined || assignee === undefined) {
        throw new Error("A human task needs a tenant and an assignee");
      }

      const days = v.parse(
        v.fallback(v.nullable(v.number()), null),
        config["dueInDays"],
      );

      const title = text(config, "title").slice(0, 160);

      await serviceNotifications()
        .send({
          type: "workflow.message",
          input: {
            tenant,
            recipients: [assignee],
            includeActor: true,
            data: {
              title: days === null ? title : `${title} (due in ${days} days)`,
            },
          },
        })
        .orThrow();

      return { assignee, title, dueInDays: days };
    },
    { waits: true },
  );
}

const DEFAULT_MODEL = "openai/gpt-5-mini";

/**
 * The `ai-step` node: a model's answer. Without a gateway key it answers with a
 * note.
 */
async function aiNode(call: GraphNodeCall) {
  "use step";

  return reportNode(call, async () => {
    const config = withConfig(call).config;
    const prompt = text(config, "prompt");
    const model = text(config, "model") || DEFAULT_MODEL;

    if (!env.AI_GATEWAY_API_KEY) {
      return {
        text: `Demo answer: set AI_GATEWAY_API_KEY to ask ${model}. Prompt: ${prompt.slice(0, 200)}`,
        model: "demo",
      };
    }

    const instructions = text(config, "system");

    const answer =
      instructions === ""
        ? await generateText({ model, prompt })
        : await generateText({ model, prompt, instructions });

    return { text: answer.text, model };
  });
}

/**
 * The deployment's node kinds that run as plain steps. `sub-workflow` starts a
 * run, which needs the starter this module feeds, so `graph-workflow.ts` holds
 * it.
 */
export const graphNodeSteps = {
  loop: loopNode,
  parallel: parallelNode,
  "human-task": humanTaskNode,
  "ai-step": aiNode,
};

/** The subject type and action a graph's approval nodes file requests under. */
export const GRAPH_APPROVAL = {
  subject: "workflow_run",
  action: "approve",
} as const;

/**
 * Files an approvals request for an approval node and returns its id, the hook
 * token the run waits on. Deciding the request on /approvals (or the canvas)
 * resumes the run through `wakeOnApproval`.
 */
export async function requestGraphApproval(
  call: GraphApprovalCall,
): Promise<string> {
  "use step";

  const { tenant } = await runOwner();

  if (tenant === undefined) {
    throw new Error("A graph run needs a tenant to request an approval");
  }

  const request = await createApprovals({
    transport: rpcTransport(serviceSupabase(), { schema: "api" }),
    schema: "api",
    tenant,
    temporal: Temporal,
  })
    .request({
      subject: { type: GRAPH_APPROVAL.subject, id: call.runKey },
      input: { action: GRAPH_APPROVAL.action, payload: { node: call.node } },
    })
    .orThrow();

  return request.id;
}
