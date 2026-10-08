"use client";

import type { WorkflowStepInfo } from "better-supabase/blocks/workflow-builder";

import { CheckIcon, Trash2Icon, XIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId } from "react";
import * as v from "valibot";

import { Button } from "@/components/ui/button";
import { Field, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

import type { CredentialRow } from "../builder-queries";
import type { GraphFlowNode, GraphNodeData, NodeConfig } from "./graph-node";

const OPERATORS = [
  "equals",
  "notEquals",
  "exists",
  "truthy",
  "greaterThan",
  "lessThan",
  "contains",
] as const;

const Scalar = v.union([v.string(), v.number(), v.boolean(), v.null()]);
type Scalar = v.InferOutput<typeof Scalar>;
const Properties = v.looseObject({});

/** A config field as the text an input shows: strings as they are, other values as JSON. */
function text(config: NodeConfig, key: string): string {
  const value = config[key];
  if (v.is(v.string(), value)) return value;
  return value === undefined ? "" : JSON.stringify(value);
}

/** A condition value: a JSON scalar when it parses (`3`, `true`, `"pro"`), the raw text otherwise. */
function valueOf(raw: string): Scalar {
  try {
    const parsed = v.safeParse(Scalar, JSON.parse(raw));
    return parsed.success ? parsed.output : raw;
  } catch {
    return raw;
  }
}

function properties(step: WorkflowStepInfo | undefined): readonly string[] {
  const props = step?.inputSchema?.["properties"];
  return v.is(Properties, props) ? Object.keys(props) : [];
}

export function NodePanel({
  node,
  steps,
  credentials,
  canDecide,
  onChange,
  onRemove,
  onDecide,
}: {
  node: GraphFlowNode;
  steps: readonly WorkflowStepInfo[];
  credentials: readonly CredentialRow[];
  /** Whether the overlay's run can still take this approval. */
  canDecide: boolean;
  onChange: (data: Partial<GraphNodeData>) => void;
  onRemove: () => void;
  onDecide: (approved: boolean) => void;
}) {
  const t = useExtracted("workflows");
  const id = useId();
  const { data } = node;
  const setConfig = (key: string, value: Scalar) => {
    onChange({ config: { ...data.config, [key]: value } });
  };
  const step = steps.find((item) => item.name === data.step);
  return (
    <aside className="bg-card w-72 shrink-0 space-y-4 rounded-lg border p-4">
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor={`${id}-label`}>{t("Label")}</FieldLabel>
          <Input
            id={`${id}-label`}
            value={data.label}
            maxLength={100}
            onChange={(event) => {
              onChange({ label: event.target.value });
            }}
          />
        </Field>
        {data.kind === "step"
          ? properties(step).map((key) => {
              const options = credentials.filter(
                (credential) => credential.kind === step?.credentialKind,
              );
              return (
                <Field key={key}>
                  <FieldLabel htmlFor={`${id}-${key}`}>{key}</FieldLabel>
                  {key === "credential" && step?.credentialKind ? (
                    <Select
                      value={text(data.config, key) || null}
                      onValueChange={(value) => {
                        setConfig(key, value ?? "");
                      }}
                      items={options.map((credential) => ({
                        value: credential.id,
                        label: credential.name,
                      }))}
                    >
                      <SelectTrigger id={`${id}-${key}`}>
                        <SelectValue placeholder={t("Pick a credential")} />
                      </SelectTrigger>
                      <SelectContent>
                        {options.map((credential) => (
                          <SelectItem key={credential.id} value={credential.id}>
                            {credential.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  ) : (
                    <Input
                      id={`${id}-${key}`}
                      value={text(data.config, key)}
                      onChange={(event) => {
                        setConfig(key, event.target.value);
                      }}
                    />
                  )}
                </Field>
              );
            })
          : null}
        {data.kind === "sleep" ? (
          <Field>
            <FieldLabel htmlFor={`${id}-duration`}>{t("Duration")}</FieldLabel>
            <Input
              id={`${id}-duration`}
              value={text(data.config, "duration")}
              placeholder="30s, 5m, 1d"
              onChange={(event) => {
                setConfig("duration", event.target.value);
              }}
            />
          </Field>
        ) : null}
        {data.kind === "condition" ? (
          <>
            <Field>
              <FieldLabel htmlFor={`${id}-path`}>{t("Path")}</FieldLabel>
              <Input
                id={`${id}-path`}
                value={text(data.config, "path")}
                placeholder="results.summarize.words"
                className="font-mono"
                onChange={(event) => {
                  setConfig("path", event.target.value);
                }}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${id}-op`}>{t("Operator")}</FieldLabel>
              <Select
                value={text(data.config, "op") || "equals"}
                onValueChange={(value) => {
                  setConfig("op", value ?? "equals");
                }}
                items={OPERATORS.map((op) => ({ value: op, label: op }))}
              >
                <SelectTrigger id={`${id}-op`}>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {OPERATORS.map((op) => (
                    <SelectItem key={op} value={op}>
                      {op}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${id}-value`}>{t("Value")}</FieldLabel>
              <Input
                id={`${id}-value`}
                value={text(data.config, "value")}
                className="font-mono"
                onChange={(event) => {
                  setConfig("value", valueOf(event.target.value));
                }}
              />
            </Field>
          </>
        ) : null}
      </FieldGroup>
      {data.kind === "approval" && canDecide ? (
        <div className="flex gap-2">
          <Button
            size="sm"
            onClick={() => {
              onDecide(true);
            }}
          >
            <CheckIcon />
            {t("Approve")}
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => {
              onDecide(false);
            }}
          >
            <XIcon />
            {t("Reject")}
          </Button>
        </div>
      ) : null}
      {data.kind === "trigger" ? null : (
        <Button variant="ghost" size="sm" onClick={onRemove}>
          <Trash2Icon />
          {t("Remove node")}
        </Button>
      )}
    </aside>
  );
}
