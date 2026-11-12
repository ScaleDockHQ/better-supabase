import type { WorkflowGraphNode } from "better-supabase/blocks/workflow-editor";

import { defineNodeKind } from "better-supabase/blocks/workflow-editor";
import * as v from "valibot";

const Text = v.fallback(v.pipe(v.string(), v.trim()), "");
const Names = v.fallback(v.array(v.string()), []);

/** A config field of a node as trimmed text; anything else reads as empty. */
const text = (node: WorkflowGraphNode, key: string): string =>
  v.parse(Text, node.config?.[key]);

/**
 * The deployment's own node kinds beside the five built-in ones (ADR 0126).
 * Each runs as one step: `loop` and `parallel` call library steps inside it,
 * `ai-step` calls a model, `human-task` asks a member and `sub-workflow` starts
 * another definition. The canvas builds the palette and the inspector form from
 * these `configSchema`s.
 */
const loopKind = defineNodeKind({
  apiVersion: 1,
  kind: "loop",
  title: "Loop",
  description: "Runs one library step for each item of a list.",
  configSchema: {
    type: "object",
    properties: {
      items: {
        type: "string",
        title: "List",
        description: "A data path such as results.fetch.items.",
      },
      step: { type: "string", title: "Step", "x-field": "step" },
      stepConfig: {
        type: "object",
        title: "Step config",
        description: "The step's fields as JSON. Use {{input}} for the item.",
      },
      max: {
        type: "integer",
        title: "At most",
        minimum: 1,
        maximum: 100,
        default: 25,
      },
    },
    required: ["items", "step"],
  },
  validate: (node) => [
    ...(text(node, "items") === "" ? [`Loop ${node.id} names no list`] : []),
    ...(text(node, "step") === "" ? [`Loop ${node.id} names no step`] : []),
  ],
});

const parallelKind = defineNodeKind({
  apiVersion: 1,
  kind: "parallel",
  title: "Parallel",
  description: "Runs several library steps at the same time.",
  configSchema: {
    type: "object",
    properties: {
      steps: {
        type: "array",
        title: "Steps",
        items: { type: "string" },
        "x-field": "steps",
      },
    },
    required: ["steps"],
  },
  validate: (node) =>
    v.parse(Names, node.config?.["steps"]).length < 2
      ? [`Parallel ${node.id} needs at least two steps`]
      : [],
});

const humanTaskKind = defineNodeKind({
  apiVersion: 1,
  kind: "human-task",
  title: "Human task",
  description: "Asks a member to do something and notifies them.",
  configSchema: {
    type: "object",
    properties: {
      title: { type: "string", title: "Task", maxLength: 200 },
      assignee: {
        type: "string",
        title: "Assignee",
        description:
          "A member id. Leave empty for the member who started the run.",
      },
      dueInDays: {
        type: "integer",
        title: "Due in days",
        minimum: 0,
        maximum: 365,
      },
    },
    required: ["title"],
  },
  validate: (node) =>
    text(node, "title") === "" ? [`Human task ${node.id} has no title`] : [],
});

const aiStepKind = defineNodeKind({
  apiVersion: 1,
  kind: "ai-step",
  title: "AI step",
  description: "Asks a model and returns its answer as text.",
  configSchema: {
    type: "object",
    properties: {
      prompt: {
        type: "string",
        title: "Prompt",
        maxLength: 4000,
        "x-multiline": true,
      },
      system: { type: "string", title: "Instructions", maxLength: 1000 },
      model: {
        type: "string",
        title: "Model",
        description: "A provider/model id on AI Gateway.",
        default: "openai/gpt-5-mini",
      },
    },
    required: ["prompt"],
  },
  validate: (node) =>
    text(node, "prompt") === "" ? [`AI step ${node.id} has no prompt`] : [],
});

const subWorkflowKind = defineNodeKind({
  apiVersion: 1,
  kind: "sub-workflow",
  title: "Sub-workflow",
  description: "Starts another workflow and returns its run id.",
  configSchema: {
    type: "object",
    properties: {
      definition: {
        type: "string",
        title: "Workflow",
        "x-field": "definition",
      },
      text: { type: "string", title: "Input text" },
    },
    required: ["definition"],
  },
  validate: (node) =>
    text(node, "definition") === ""
      ? [`Sub-workflow ${node.id} names no workflow`]
      : [],
});

export const nodeKinds = [
  loopKind,
  parallelKind,
  humanTaskKind,
  aiStepKind,
  subWorkflowKind,
] as const;
