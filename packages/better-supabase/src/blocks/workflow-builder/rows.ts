import type { CredentialRef } from "../../credentials/provider.ts";
import type {
  WorkflowAlert,
  WorkflowCredential,
  WorkflowDefinition,
  WorkflowNodeRun,
  WorkflowNodeRunStatus,
  WorkflowStepInfo,
  WorkflowTrigger,
  WorkflowTriggerKind,
  WorkflowVersion,
  WorkflowVersionStatus,
} from "./types.ts";

import {
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOrEmpty,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";
import { graphOf } from "./graph.ts";

const VERSION_STATUSES: readonly WorkflowVersionStatus[] = [
  "draft",
  "published",
  "archived",
];
const TRIGGER_KINDS: readonly WorkflowTriggerKind[] = [
  "manual",
  "webhook",
  "schedule",
  "event",
  "form",
  "chat",
];
const NODE_RUN_STATUSES: readonly WorkflowNodeRunStatus[] = [
  "running",
  "waiting",
  "completed",
  "failed",
  "skipped",
];

export function definitionOf(row: Record<string, unknown>): WorkflowDefinition {
  const published = row["published"];
  return {
    id: textOf(row["id"]),
    tenant: optionalText(row["tenant"]),
    slug: textOf(row["slug"]),
    name: textOf(row["name"]),
    description: optionalText(row["description"]),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...("published" in row
      ? { published: typeof published === "number" ? published : undefined }
      : {}),
    ...("draft" in row ? { draft: row["draft"] === true } : {}),
  };
}

export function versionOf(row: Record<string, unknown>): WorkflowVersion {
  return {
    id: textOf(row["id"]),
    definition: textOf(row["definition"]),
    version: Number(row["version"]),
    status: enumOrThrow(row["status"], VERSION_STATUSES, "version status"),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    publishedAt: optionalInstant(row["publishedAt"]),
    ...("graph" in row ? { graph: graphOf(row["graph"]) } : {}),
    ...("compiled" in row && row["compiled"] !== null
      ? { compiled: row["compiled"] }
      : {}),
  };
}

export function triggerOf(row: Record<string, unknown>): WorkflowTrigger {
  return {
    id: textOf(row["id"]),
    definition: textOf(row["definition"]),
    kind: enumOrThrow(row["kind"], TRIGGER_KINDS, "trigger kind"),
    config: recordOrEmpty(row["config"]),
    enabled: row["enabled"] !== false,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function refOf(value: unknown): CredentialRef {
  if (!isRecord(value) || typeof value["provider"] !== "string") {
    throw new TypeError("workflow-builder: a credential_ref has no provider");
  }
  return { ...value, provider: value["provider"] };
}

export function credentialOf(row: Record<string, unknown>): WorkflowCredential {
  return {
    id: textOf(row["id"]),
    tenant: optionalText(row["tenant"]),
    kind: textOf(row["kind"]),
    name: textOf(row["name"]),
    ref: refOf(row["ref"]),
    scopes: Array.isArray(row["scopes"]) ? stringsOf(row["scopes"]) : [],
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

export function stepOf(row: Record<string, unknown>): WorkflowStepInfo {
  return {
    name: textOf(row["name"]),
    title: textOf(row["title"]),
    description: optionalText(row["description"]),
    inputSchema: recordOrEmpty(row["inputSchema"]),
    outputSchema: recordOrEmpty(row["outputSchema"]),
    credentialKind: optionalText(row["credentialKind"]),
  };
}

export function nodeRunOf(row: Record<string, unknown>): WorkflowNodeRun {
  return {
    run: textOf(row["run"]),
    node: textOf(row["node"]),
    status: enumOrThrow(row["status"], NODE_RUN_STATUSES, "node status"),
    attempts: Number(row["attempts"] ?? 0),
    output: row["output"] ?? undefined,
    error: optionalText(row["error"]),
    startedAt: optionalInstant(row["startedAt"]),
    endedAt: optionalInstant(row["endedAt"]),
  };
}

export function alertOf(row: Record<string, unknown>): WorkflowAlert {
  const threshold = row["threshold"];
  return {
    id: textOf(row["id"]),
    definition: textOf(row["definition"]),
    onEvent: row["onEvent"] === "slow" ? "slow" : "failed",
    threshold:
      threshold === null || threshold === undefined
        ? undefined
        : Number(threshold),
    channel: recordOrEmpty(row["channel"]),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

/** `map` over an object result, or `undefined` for anything else. */
export function optionalOf<T>(
  map: (row: Record<string, unknown>) => T,
): (value: unknown) => T | undefined {
  return (value) => (isRecord(value) ? map(value) : undefined);
}
