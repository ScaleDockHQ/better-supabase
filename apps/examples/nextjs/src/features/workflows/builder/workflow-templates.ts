import type { WorkflowGraph } from "better-supabase/blocks/workflow-editor";

import { autoLayout } from "./editor-model";

/** A starting graph for the template gallery. */
export interface WorkflowTemplate {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  /** The node kinds it shows, for the gallery's tags. */
  readonly tags: readonly string[];
  readonly graph: WorkflowGraph;
}

const trigger = {
  id: "trigger",
  kind: "trigger",
  label: "Start",
  config: { trigger: "manual" },
} as const;

const edge = (
  source: string,
  target: string,
  branch?: "true" | "false",
): WorkflowGraph["edges"][number] =>
  branch === undefined
    ? { id: `${source}-${target}`, source, target }
    : { id: `${source}-${target}-${branch}`, source, target, branch };

const raw: readonly WorkflowTemplate[] = [
  {
    id: "welcome-drip",
    name: "Welcome drip",
    description:
      "Greets the member who started the run, waits, then sends a tip.",
    tags: ["trigger", "wait", "action"],
    graph: {
      nodes: [
        trigger,
        {
          id: "welcome",
          kind: "step",
          step: "notify.member",
          label: "Welcome",
          config: { title: "Welcome to Acme" },
        },
        {
          id: "pause",
          kind: "sleep",
          label: "Wait",
          config: { duration: "1m" },
        },
        {
          id: "tip",
          kind: "step",
          step: "notify.member",
          label: "Tip",
          config: { title: "Tip: invite your team from Settings" },
        },
      ],
      edges: [
        edge("trigger", "welcome"),
        edge("welcome", "pause"),
        edge("pause", "tip"),
      ],
    },
  },
  {
    id: "summarize-and-route",
    name: "Summarize and route",
    description:
      "Counts the words of the input, then sends long texts and short texts different messages.",
    tags: ["condition", "action", "data mapping"],
    graph: {
      nodes: [
        trigger,
        {
          id: "summarize",
          kind: "step",
          step: "text.summarize",
          label: "Summarize",
          config: {},
        },
        {
          id: "long",
          kind: "condition",
          label: "Long text?",
          config: {
            path: "results.summarize.words",
            op: "greaterThan",
            value: 50,
          },
        },
        {
          id: "report",
          kind: "step",
          step: "text.format",
          label: "Report",
          config: {
            text: "Long text: {{results.summarize.words}} words in {{results.summarize.sentences}} sentences",
          },
        },
        {
          id: "tell-long",
          kind: "step",
          step: "notify.member",
          label: "Tell the member",
          config: { title: "{{results.report.text}}" },
        },
        {
          id: "tell-short",
          kind: "step",
          step: "notify.member",
          label: "Short note",
          config: { title: "Short text: {{results.summarize.words}} words" },
        },
      ],
      edges: [
        edge("trigger", "summarize"),
        edge("summarize", "long"),
        edge("long", "report", "true"),
        edge("report", "tell-long"),
        edge("long", "tell-short", "false"),
      ],
    },
  },
  {
    id: "approval-gate",
    name: "Approval gate",
    description:
      "Files an approval request and tells the member what was decided.",
    tags: ["approval", "action"],
    graph: {
      nodes: [
        trigger,
        { id: "approve", kind: "approval", label: "Approve", config: {} },
        {
          id: "approved",
          kind: "step",
          step: "notify.member",
          label: "Approved",
          config: { title: "Your request was approved" },
        },
        {
          id: "rejected",
          kind: "step",
          step: "notify.member",
          label: "Rejected",
          config: { title: "Your request was rejected" },
        },
      ],
      edges: [
        edge("trigger", "approve"),
        edge("approve", "approved", "true"),
        edge("approve", "rejected", "false"),
      ],
    },
  },
  {
    id: "ai-triage",
    name: "AI triage",
    description:
      "Asks a model to triage the input, then hands the answer to a member.",
    tags: ["ai step", "human task"],
    graph: {
      nodes: [
        trigger,
        {
          id: "triage",
          kind: "ai-step",
          label: "Triage",
          config: {
            prompt: "Triage this request in one sentence: {{input.text}}",
            model: "openai/gpt-5-mini",
          },
        },
        {
          id: "review",
          kind: "human-task",
          label: "Review",
          config: {
            title: "Review the triage: {{results.triage.text}}",
            dueInDays: 2,
          },
        },
      ],
      edges: [edge("trigger", "triage"), edge("triage", "review")],
    },
  },
  {
    id: "batch-notify",
    name: "Notify each item",
    description:
      'Runs a step for each entry of input.items. Run it with {"items": ["a", "b"]}.',
    tags: ["loop", "data mapping"],
    graph: {
      nodes: [
        trigger,
        {
          id: "each",
          kind: "loop",
          label: "For each item",
          config: {
            items: "input.items",
            step: "notify.member",
            stepConfig: { title: "Item: {{input}}" },
            max: 10,
          },
        },
      ],
      edges: [edge("trigger", "each")],
    },
  },
  {
    id: "fan-out",
    name: "Summarize and format in parallel",
    description: "Runs two steps at once, then reports the summary.",
    tags: ["parallel", "action"],
    graph: {
      nodes: [
        trigger,
        {
          id: "both",
          kind: "parallel",
          label: "Both at once",
          config: { steps: ["text.summarize", "text.format"] },
        },
        {
          id: "done",
          kind: "step",
          step: "notify.member",
          label: "Done",
          config: { title: "Both steps finished" },
        },
      ],
      edges: [edge("trigger", "both"), edge("both", "done")],
    },
  },
];

/** The templates with their nodes placed by the auto layout. */
export const workflowTemplates: readonly WorkflowTemplate[] = raw.map(
  (template) => {
    const positions = autoLayout(template.graph);

    return {
      ...template,
      graph: {
        ...template.graph,
        nodes: template.graph.nodes.map((node) => ({
          ...node,
          position: positions.get(node.id) ?? { x: 0, y: 0 },
        })),
      },
    };
  },
);

export function templateOf(id: string): WorkflowTemplate | undefined {
  return workflowTemplates.find((template) => template.id === id);
}
