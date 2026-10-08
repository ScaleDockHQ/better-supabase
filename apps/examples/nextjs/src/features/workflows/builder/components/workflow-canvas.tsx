"use client";

import type { WorkflowNodeKind } from "better-supabase/blocks/workflow-builder";

import {
  addEdge,
  Background,
  type Connection,
  Controls,
  ReactFlow,
  useEdgesState,
  useNodesState,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import { useWorkflowCanvasRun } from "better-supabase/blocks/workflow-builder/react";
import { useWorkflowRuns } from "better-supabase/blocks/workflows/react";
import { useAction } from "better-supabase/react";
import { PlayIcon, PlusIcon, SaveIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useState } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import type { BuilderDetail } from "../builder-queries";

import { isFinished, statusVariant } from "../../workflow-labels";
import {
  decideNode,
  publishGraph,
  runDefinition,
  saveDraft,
} from "../builder-actions";
import { CredentialSheet } from "./credential-sheet";
import {
  fromFlow,
  type GraphFlowNode,
  type GraphNodeData,
  nodeTypes,
  toFlow,
} from "./graph-node";
import { NodePanel } from "./node-panel";
import { PublishDialog } from "./publish-dialog";
import { TriggerSheet } from "./trigger-sheet";

const shortId = () => crypto.randomUUID().slice(0, 8);

/**
 * The canvas: a palette from the step library, the graph on React Flow, an
 * inspector for the selected node, and the status of a run's nodes on top,
 * live over `workflow-run:<id>`.
 */
export function WorkflowCanvas({ detail }: { detail: BuilderDetail }) {
  const t = useExtracted("workflows");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const [initial] = useState(() => toFlow(detail.graph));
  const [nodes, setNodes, onNodesChange] = useNodesState<GraphFlowNode>(
    initial.nodes,
  );
  const [edges, setEdges, onEdgesChange] = useEdgesState(initial.edges);
  const [selected, setSelected] = useState<string | null>(null);
  const [runId, setRunId] = useState<string | null>(null);
  const [input, setInput] = useState("");
  const { runs } = useWorkflowRuns({
    tenant: detail.tenant,
    schema: "api",
    limit: 50,
  });
  const overlay = useWorkflowCanvasRun(runId, { schema: "api" });
  const definitionRuns = (runs ?? []).filter(
    (run) => run.attributes["bs.definition"] === detail.definition.id,
  );
  const graph = fromFlow(nodes, edges);
  const draft = { nodes: [...graph.nodes], edges: [...graph.edges] };
  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };
  const save = useAction(saveDraft, {
    onError,
    onSuccess: () => {
      toast.success(t("Draft saved"));
    },
  });
  const publish = useAction(publishGraph, {
    onError,
    onSuccess: (version) => {
      toast.success(
        t("Version {version} published", { version: String(version) }),
      );
    },
  });
  const run = useAction(runDefinition, {
    onError,
    onSuccess: (id) => {
      setRunId(id);
    },
  });
  const decide = useAction(decideNode, { onError });

  const addNode = (kind: WorkflowNodeKind, step?: string, title?: string) => {
    const id = `${step ?? kind}-${shortId()}`.replaceAll(".", "-");
    const lowest = Math.max(0, ...nodes.map((node) => node.position.y));
    const data: GraphNodeData = {
      kind,
      label: title ?? kind,
      config: kind === "sleep" ? { duration: "1m" } : {},
    };
    setNodes((current) => [
      ...current,
      {
        id,
        type: "graph",
        position: { x: 0, y: lowest + 120 },
        data: step === undefined ? data : { ...data, step },
      },
    ]);
    setSelected(id);
  };
  const onConnect = (connection: Connection) => {
    setEdges((current) =>
      addEdge(
        connection.sourceHandle
          ? {
              ...connection,
              id: `e-${shortId()}`,
              label: connection.sourceHandle,
            }
          : { ...connection, id: `e-${shortId()}` },
        current,
      ),
    );
  };
  const updateNode = (id: string, data: Partial<GraphNodeData>) => {
    setNodes((current) =>
      current.map((node) =>
        node.id === id ? { ...node, data: { ...node.data, ...data } } : node,
      ),
    );
  };
  const removeNode = (id: string) => {
    setNodes((current) => current.filter((node) => node.id !== id));
    setEdges((current) =>
      current.filter((edge) => edge.source !== id && edge.target !== id),
    );
    setSelected(null);
  };

  const shown =
    runId === null
      ? nodes
      : nodes.map((node) => {
          const status = overlay.nodes[node.id]?.status;
          return status === undefined
            ? node
            : { ...node, data: { ...node.data, status } };
        });
  const selectedNode = nodes.find((node) => node.id === selected);
  const runOpen = overlay.run !== undefined && !isFinished(overlay.run.status);
  const definition = detail.definition.id;

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Button
          variant="outline"
          size="sm"
          disabled={save.pending}
          onClick={() => {
            void save.run({ definition, graph: draft });
          }}
        >
          <SaveIcon />
          {t("Save draft")}
        </Button>
        <PublishDialog
          published={detail.published}
          graph={graph}
          pending={publish.pending}
          onPublish={() => {
            void publish.run({ definition, graph: draft });
          }}
        />
        <TriggerSheet definition={definition} triggers={detail.triggers} />
        <CredentialSheet credentials={detail.credentials} />
        <span className="grow" />
        <Input
          value={input}
          onChange={(event) => {
            setInput(event.target.value);
          }}
          placeholder={t("Input text")}
          aria-label={t("Input text")}
          className="w-56"
        />
        <Button
          size="sm"
          disabled={run.pending || detail.published === null}
          onClick={() => {
            void run.run({ definition, text: input });
          }}
        >
          <PlayIcon />
          {t("Run")}
        </Button>
        <Select
          value={runId}
          onValueChange={(value) => {
            setRunId(value);
          }}
          items={definitionRuns.map((item) => ({
            value: item.externalId,
            label: format.dateTime(new Date(item.createdAt.epochMilliseconds), {
              timeStyle: "medium",
            }),
          }))}
        >
          <SelectTrigger className="w-44" aria-label={t("Show a run")}>
            <SelectValue placeholder={t("Show a run")} />
          </SelectTrigger>
          <SelectContent>
            {definitionRuns.map((item) => (
              <SelectItem key={item.id} value={item.externalId}>
                {format.dateTime(new Date(item.createdAt.epochMilliseconds), {
                  timeStyle: "medium",
                })}{" "}
                · {item.status}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {overlay.run ? (
          <Badge variant={statusVariant(overlay.run.status)}>
            {overlay.run.status}
          </Badge>
        ) : null}
      </div>
      <div className="flex gap-3">
        <nav
          className="bg-card w-48 shrink-0 space-y-1 rounded-lg border p-2"
          aria-label={t("Palette")}
        >
          {detail.steps.map((step) => (
            <Button
              key={step.name}
              variant="ghost"
              size="sm"
              className="w-full justify-start"
              title={step.description}
              onClick={() => {
                addNode("step", step.name, step.title);
              }}
            >
              <PlusIcon />
              <span className="truncate">{step.title}</span>
            </Button>
          ))}
          {(
            [
              ["sleep", t("Wait")],
              ["approval", t("Approval")],
              ["condition", t("Condition")],
            ] as const
          ).map(([kind, label]) => (
            <Button
              key={kind}
              variant="ghost"
              size="sm"
              className="w-full justify-start"
              onClick={() => {
                addNode(kind, undefined, label);
              }}
            >
              <PlusIcon />
              {label}
            </Button>
          ))}
        </nav>
        <div
          className="bg-muted/30 h-150 min-w-0 flex-1 rounded-lg border"
          data-testid="workflow-canvas"
        >
          <ReactFlow
            nodes={shown}
            edges={edges}
            nodeTypes={nodeTypes}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onConnect={onConnect}
            onNodeClick={(_, node) => {
              setSelected(node.id);
            }}
            onPaneClick={() => {
              setSelected(null);
            }}
            fitView
          >
            <Background />
            <Controls />
          </ReactFlow>
        </div>
        {selectedNode ? (
          <NodePanel
            key={selectedNode.id}
            node={selectedNode}
            steps={detail.steps}
            credentials={detail.credentials}
            canDecide={runOpen}
            onChange={(data) => {
              updateNode(selectedNode.id, data);
            }}
            onRemove={() => {
              removeNode(selectedNode.id);
            }}
            onDecide={(approved) => {
              if (runId === null) return;
              void decide.run({ run: runId, node: selectedNode.id, approved });
            }}
          />
        ) : null}
      </div>
    </div>
  );
}
