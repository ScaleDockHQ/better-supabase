"use client";

import type { Edge, Node, NodeProps } from "@xyflow/react";
import type {
  WorkflowGraph,
  WorkflowGraphNode,
  WorkflowNodeKind,
  WorkflowNodeRunStatus,
} from "better-supabase/blocks/workflow-editor";

import { Handle, Position } from "@xyflow/react";

import { Badge } from "@/components/reui/badge";
import { Card } from "@/components/ui/card";

import { KindIcon } from "../../kind-icon";

export type NodeConfig = NonNullable<WorkflowGraphNode["config"]>;

export interface GraphNodeData extends Record<string, unknown> {
  readonly kind: WorkflowNodeKind;
  readonly label: string;
  readonly step?: string | undefined;
  readonly config: NodeConfig;
  /** Whether the kind takes true and false branches. */
  readonly branches?: boolean;
  /** The node's status in the run the overlay shows. */
  readonly status?: WorkflowNodeRunStatus | undefined;
  /** The worst validation problem on the node. */
  readonly issue?: "error" | "warning" | undefined;
}

export type GraphFlowNode = Node<GraphNodeData, "graph">;

const STATUS_BADGE = {
  running: "info-light",
  waiting: "warning-light",
  completed: "success-light",
  failed: "destructive-light",
  skipped: "secondary",
} as const satisfies Record<WorkflowNodeRunStatus, string>;

const branches = (data: GraphNodeData): boolean =>
  data.kind === "condition" ||
  data.kind === "approval" ||
  data.branches === true;

function GraphNode({ data, selected }: NodeProps<GraphFlowNode>) {
  return (
    <Card
      size="sm"
      className="w-56 gap-1 overflow-visible data-[issue=error]:ring-2 data-[issue=error]:ring-destructive/60 data-[issue=warning]:ring-2 data-[issue=warning]:ring-warning/60 data-[selected=true]:ring-2 data-[selected=true]:ring-primary data-[status=completed]:ring-2 data-[status=completed]:ring-success data-[status=failed]:ring-2 data-[status=failed]:ring-destructive data-[status=running]:ring-2 data-[status=running]:ring-info data-[status=skipped]:opacity-60 data-[status=waiting]:ring-2 data-[status=waiting]:ring-warning"
      data-selected={selected}
      data-issue={data.issue}
      data-status={data.status}
      data-testid={`graph-node-${data.kind}`}
    >
      {data.kind === "trigger" ? null : (
        <Handle type="target" position={Position.Top} />
      )}
      <div className="flex items-center gap-2 px-(--card-spacing)">
        <KindIcon
          kind={data.kind}
          className="size-4 shrink-0 text-muted-foreground"
        />
        <span className="truncate text-sm font-medium">{data.label}</span>
      </div>
      <div className="flex items-center justify-between gap-2 px-(--card-spacing) text-xs text-muted-foreground">
        <span className="truncate font-mono">{data.step ?? data.kind}</span>
        {data.status === undefined ? null : (
          <Badge variant={STATUS_BADGE[data.status]}>{data.status}</Badge>
        )}
      </div>
      {branches(data) ? (
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
          <div className="flex justify-around text-xs text-muted-foreground uppercase">
            <span>true</span>
            <span>false</span>
          </div>
        </>
      ) : (
        <Handle type="source" position={Position.Bottom} />
      )}
    </Card>
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
