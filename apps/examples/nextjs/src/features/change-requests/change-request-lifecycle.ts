import type {
  WorkflowGraph,
  WorkflowGraphNode,
} from "better-supabase/blocks/workflow-editor";

import * as v from "valibot";

/** The workflow slug the `change_request` state machine reads its stages from. */
export const CHANGE_WORKFLOW = "change-requests";

export const CHANGE_SUBJECT = "change_request";

/**
 * The lifecycle the empty state publishes: a request is submitted, the change
 * advisory board reviews it (and may send it back), then it is scheduled and
 * done. Tenants change it in the workflow builder.
 */
export const DEFAULT_CHANGE_GRAPH: WorkflowGraph = {
  nodes: [
    {
      id: "submitted",
      kind: "trigger",
      label: "Submitted",
      config: { stage: "submitted" },
      position: { x: 0, y: 0 },
    },
    {
      id: "review",
      kind: "approval",
      label: "CAB review",
      config: { stage: "review", returnsTo: ["submitted"] },
      position: { x: 240, y: 0 },
    },
    {
      id: "scheduled",
      kind: "approval",
      label: "Scheduled",
      config: { stage: "scheduled" },
      position: { x: 480, y: 0 },
    },
    {
      id: "done",
      kind: "approval",
      label: "Done",
      config: { stage: "done" },
      position: { x: 720, y: 0 },
    },
  ],
  edges: [
    { id: "submitted-review", source: "submitted", target: "review" },
    { id: "review-scheduled", source: "review", target: "scheduled" },
    { id: "scheduled-done", source: "scheduled", target: "done" },
  ],
};

export interface ChangeStage {
  readonly id: string;
  readonly label: string;
}

export interface ChangeLifecycle {
  /** The stages in the order their first node appears in the graph. */
  readonly stages: readonly ChangeStage[];
  readonly initial: string | undefined;
  /** The stages each stage may move to. */
  readonly moves: Readonly<Record<string, readonly string[]>>;
}

const Stage = v.string();

const Stages = v.array(v.unknown());

const stageOf = (node: WorkflowGraphNode): string | undefined => {
  const parsed = v.safeParse(Stage, node.config?.["stage"]);

  return parsed.success ? parsed.output : undefined;
};

const returnsOf = (node: WorkflowGraphNode): readonly string[] => {
  const parsed = v.safeParse(Stages, node.config?.["returnsTo"]);

  return parsed.success
    ? parsed.output.flatMap((item) => {
        const stage = v.safeParse(Stage, item);

        return stage.success ? [stage.output] : [];
      })
    : [];
};

/**
 * The stages and moves of a lifecycle graph, by the rules the database's
 * `lifecycle_graph` applies: a stage moves to the stages it reaches through
 * nodes without a stage, and to the stages its `returnsTo` lists. The trigger
 * still refuses any other move, so this only decides what the UI offers.
 */
export function getLifecycle(graph: WorkflowGraph): ChangeLifecycle {
  const byId = new Map(graph.nodes.map((node) => [node.id, node]));
  const targets = new Map<string, string[]>();

  for (const edge of graph.edges) {
    targets.set(edge.source, [
      ...(targets.get(edge.source) ?? []),
      edge.target,
    ]);
  }

  const stages: ChangeStage[] = [];
  const known = new Set<string>();

  for (const node of graph.nodes) {
    const stage = stageOf(node);

    if (stage !== undefined && !known.has(stage)) {
      known.add(stage);
      stages.push({ id: stage, label: node.label ?? stage });
    }
  }

  /** The stages `origin` reaches before it meets another stage. */
  const reached = (origin: string): string[] => {
    const found: string[] = [];
    const seen = new Set<string>([origin]);
    let frontier = targets.get(origin) ?? [];

    while (frontier.length > 0) {
      const next: string[] = [];

      for (const id of frontier) {
        const node = byId.get(id);

        if (node === undefined || seen.has(id)) {
          continue;
        }

        seen.add(id);
        const stage = stageOf(node);

        if (stage === undefined) {
          next.push(...(targets.get(id) ?? []));
        } else {
          found.push(stage);
        }
      }

      frontier = next;
    }

    return found;
  };

  const moves = new Map<string, Set<string>>();

  for (const node of graph.nodes) {
    const from = stageOf(node);

    if (from === undefined) {
      continue;
    }

    const into = moves.get(from) ?? new Set<string>();

    for (const to of [...reached(node.id), ...returnsOf(node)]) {
      if (to !== from && known.has(to)) {
        into.add(to);
      }
    }

    moves.set(from, into);
  }

  const trigger = graph.nodes.find((node) => node.kind === "trigger");

  const initial =
    (trigger && (stageOf(trigger) ?? reached(trigger.id)[0])) ?? stages[0]?.id;

  const order = new Map(stages.map((stage, index) => [stage.id, index]));

  return {
    stages,
    initial,
    moves: Object.fromEntries(
      [...moves].map(([from, into]) => [
        from,
        [...into].toSorted((a, b) => (order.get(a) ?? 0) - (order.get(b) ?? 0)),
      ]),
    ),
  };
}
