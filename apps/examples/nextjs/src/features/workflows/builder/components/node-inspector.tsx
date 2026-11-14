"use client";

import type { WorkflowNodeRun } from "better-supabase/blocks/workflow-editor";

import {
  CheckIcon,
  MousePointerClickIcon,
  Trash2Icon,
  XIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { useId } from "react";
import * as v from "valibot";

import { Alert, AlertDescription, AlertTitle } from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  CodeBlock,
  CodeBlockContent,
  CodeBlockHeader,
  CodeBlockTitle,
} from "@/components/ui/code-block";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";

import type { PaletteEntry } from "../editor-model";
import type { GraphFlowNode, GraphNodeData } from "./graph-node";
import type { SchemaFormContext } from "./schema-form";

import { JsonObjectSchema } from "../config-templates";
import { SchemaForm } from "./schema-form";

const requiredOf = (entry: PaletteEntry | undefined): readonly string[] =>
  v.parse(v.fallback(v.array(v.string()), []), entry?.schema["required"]);

/**
 * The node panel: label, the form its schema describes, and the last run's
 * result.
 */
export function NodeInspector({
  node,
  entry,
  context,
  result,
  canDecide,
  onChange,
  onRemove,
  onDecide,
  onComplete,
}: {
  node: GraphFlowNode | undefined;
  entry: PaletteEntry | undefined;
  context: SchemaFormContext;
  /** The node's record in the run the overlay shows. */
  result: WorkflowNodeRun | undefined;
  /** Whether the overlay's run can still take this approval. */
  canDecide: boolean;
  onChange: (id: string, data: Partial<GraphNodeData>) => void;
  onRemove: (id: string) => void;
  onDecide: (id: string, approved: boolean) => void;
  /** Marks a waiting human task done, which resumes the run. */
  onComplete: (id: string) => void;
}) {
  const t = useExtracted("workflows");
  const id = useId();

  if (node === undefined) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <MousePointerClickIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No node selected")}</EmptyTitle>
          <EmptyDescription>
            {t("Select a node on the canvas to edit it.")}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  const { data } = node;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <h3 className="text-sm font-medium">{entry?.title ?? data.kind}</h3>
        {entry?.description ? (
          <p className="text-xs text-muted-foreground">{entry.description}</p>
        ) : null}
      </div>
      <Field>
        <FieldLabel htmlFor={`${id}-label`}>{t("Label")}</FieldLabel>
        <Input
          id={`${id}-label`}
          value={data.label}
          maxLength={100}
          onChange={(event) => {
            onChange(node.id, { label: event.target.value });
          }}
        />
      </Field>
      <SchemaForm
        key={node.id}
        schema={entry?.schema ?? {}}
        config={v.parse(v.fallback(JsonObjectSchema, {}), data.config)}
        context={{ ...context, credentialKind: entry?.credentialKind }}
        required={requiredOf(entry)}
        onChange={(key, value) => {
          onChange(node.id, { config: { ...data.config, [key]: value } });
        }}
      />
      {result === undefined ? null : (
        <div className="flex flex-col gap-2" data-testid="node-result">
          <div className="flex items-center gap-2 text-sm">
            <span className="font-medium">{t("Last run")}</span>
            <Badge
              variant={
                result.status === "failed"
                  ? "destructive-light"
                  : result.status === "completed"
                    ? "success-light"
                    : "secondary"
              }
            >
              {result.status}
            </Badge>
            <span className="text-xs text-muted-foreground tabular-nums">
              {t("attempt {n}", { n: String(result.attempts) })}
            </span>
          </div>
          {result.error ? (
            <Alert variant="destructive">
              <AlertTitle>{t("The node failed")}</AlertTitle>
              <AlertDescription>{result.error}</AlertDescription>
            </Alert>
          ) : null}
          {result.input === undefined || result.input === null ? null : (
            <CodeBlock size="sm">
              <CodeBlockHeader>
                <CodeBlockTitle>{t("Input")}</CodeBlockTitle>
              </CodeBlockHeader>
              <CodeBlockContent wrap>
                {JSON.stringify(result.input, null, 2)}
              </CodeBlockContent>
            </CodeBlock>
          )}
          {result.output === undefined || result.output === null ? null : (
            <CodeBlock size="sm">
              <CodeBlockHeader>
                <CodeBlockTitle>{t("Output")}</CodeBlockTitle>
              </CodeBlockHeader>
              <CodeBlockContent wrap>
                {JSON.stringify(result.output, null, 2)}
              </CodeBlockContent>
            </CodeBlock>
          )}
        </div>
      )}
      {node.data.kind === "approval" && canDecide ? (
        <div className="flex gap-2">
          <Button
            size="sm"
            onClick={() => {
              onDecide(node.id, true);
            }}
          >
            <CheckIcon />
            {t("Approve")}
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => {
              onDecide(node.id, false);
            }}
          >
            <XIcon />
            {t("Reject")}
          </Button>
        </div>
      ) : null}
      {node.data.kind === "human-task" &&
      canDecide &&
      result?.status === "waiting" ? (
        <Button
          size="sm"
          className="w-fit"
          onClick={() => {
            onComplete(node.id);
          }}
        >
          <CheckIcon />
          {t("Mark done")}
        </Button>
      ) : null}
      {data.kind === "trigger" ? null : (
        <Button
          variant="ghost"
          size="sm"
          className="w-fit"
          onClick={() => {
            onRemove(node.id);
          }}
        >
          <Trash2Icon />
          {t("Remove node")}
        </Button>
      )}
    </div>
  );
}
