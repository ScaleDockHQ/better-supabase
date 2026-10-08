"use client";

import type {
  WorkflowGraph,
  WorkflowGraphNode,
  WorkflowNodeKind,
  WorkflowNodeRunStatus,
} from "better-supabase/blocks/workflow-builder";

import {
  type Edge,
  Handle,
  type Node,
  type NodeProps,
  Position,
} from "@xyflow/react";
import {
  ClockIcon,
  GitBranchIcon,
  HandIcon,
  type LucideIcon,
  PlayIcon,
  SquareFunctionIcon,
} from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

export type NodeConfig = NonNullable<WorkflowGraphNode["config"]>;

export interface GraphNodeData extends Record<string, unknown> {
  readonly kind: WorkflowNodeKind;
  readonly label: string;
  readonly step?: string;
  readonly config: NodeConfig;
  /** The node's status in the run the overlay shows. */
  readonly status?: WorkflowNodeRunStatus;
}

export type GraphFlowNode = Node<GraphNodeData, "graph">;

const ICONS = {
  trigger: PlayIcon,
  step: SquareFunctionIcon,
  sleep: ClockIcon,
  approval: HandIcon,
  condition: GitBranchIcon,
} satisfies Record<WorkflowNodeKind, LucideIcon>;

const STATUS_RING = {
  running: "ring-2 ring-sky-500",
  waiting: "ring-2 ring-amber-500",
  completed: "ring-2 ring-emerald-500",
  failed: "ring-2 ring-red-500",
  skipped: "opacity-60",
} satisfies Record<WorkflowNodeRunStatus, string>;

const branches = (kind: WorkflowNodeKind): boolean =>
  kind === "condition" || kind === "approval";

export function GraphNode({ data, selected }: NodeProps<GraphFlowNode>) {
  const Icon = ICONS[data.kind];
  return (
    <div
      className={cn(
        "bg-card text-card-foreground w-52 rounded-lg border px-3 py-2 text-sm shadow-sm",
        selected && "border-primary",
        data.status === undefined ? undefined : STATUS_RING[data.status],
      )}
      data-testid={`graph-node-${data.kind}`}
    >
      {data.kind === "trigger" ? null : (
        <Handle type="target" position={Position.Top} />
      )}
      <div className="flex items-center gap-2">
        <Icon className="text-muted-foreground size-4 shrink-0" />
        <span className="truncate font-medium">{data.label}</span>
      </div>
      <div className="text-muted-foreground mt-1 flex items-center justify-between gap-2 text-xs">
        <span className="truncate font-mono">{data.step ?? data.kind}</span>
        {data.status === undefined ? null : (
          <Badge variant="outline">{data.status}</Badge>
        )}
      </div>
      {branches(data.kind) ? (
        <>
          <Handle
            id="true"
            type="source"
            position={Position.Bottom}
            className="left-1/3!"
          />
          <Handle
            id="false"
            type="source"
            position={Position.Bottom}
            className="left-2/3!"
          />
          <div className="text-muted-foreground mt-1 flex justify-around text-xs uppercase">
            <span>true</span>
            <span>false</span>
          </div>
        </>
      ) : (
        <Handle type="source" position={Position.Bottom} />
      )}
    </div>
  );
}

export const nodeTypes = { graph: GraphNode };

function toFlowNode(node: WorkflowGraphNode, index: number): GraphFlowNode {
  const data: GraphNodeData = {
    kind: node.kind,
    label: node.label ?? node.step ?? node.kind,
    config: node.config ?? {},
  };
  return {
    id: node.id,
    type: "graph",
    position: node.position ?? { x: 0, y: index * 120 },
    data: node.step === undefined ? data : { ...data, step: node.step },
  };
}

/** The stored graph as React Flow nodes and edges. */
export function toFlow(graph: WorkflowGraph) {
  return {
    nodes: graph.nodes.map(toFlowNode),
    edges: graph.edges.map((edge): Edge => {
      const flowEdge = {
        id: edge.id,
        source: edge.source,
        target: edge.target,
      };
      return edge.branch === undefined
        ? flowEdge
        : { ...flowEdge, sourceHandle: edge.branch, label: edge.branch };
    }),
  };
}

const branchOf = (handle: string | null | undefined) =>
  handle === "true" || handle === "false" ? handle : undefined;

/** The canvas as the engine-neutral graph a version stores. */
export function fromFlow(
  nodes: readonly GraphFlowNode[],
  edges: readonly Edge[],
): WorkflowGraph {
  return {
    nodes: nodes.map((node): WorkflowGraphNode => {
      const graphNode = {
        id: node.id,
        kind: node.data.kind,
        label: node.data.label,
        config: node.data.config,
        position: {
          x: Math.round(node.position.x),
          y: Math.round(node.position.y),
        },
      };
      return node.data.step === undefined
        ? graphNode
        : { ...graphNode, step: node.data.step };
    }),
    edges: edges.map((edge) => {
      const branch = branchOf(edge.sourceHandle);
      const graphEdge = {
        id: edge.id,
        source: edge.source,
        target: edge.target,
      };
      return branch === undefined ? graphEdge : { ...graphEdge, branch };
    }),
  };
}
