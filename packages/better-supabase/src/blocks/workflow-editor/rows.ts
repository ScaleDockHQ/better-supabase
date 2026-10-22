import type { CredentialRef } from "../../credentials/provider.ts";
import type {
  WorkflowAlert,
  WorkflowCredential,
  WorkflowDefinition,
  WorkflowDefinitionGrant,
  WorkflowDefinitionScope,
  WorkflowGrantAction,
  WorkflowGrantPrincipal,
  WorkflowNodeRun,
  WorkflowNodeRunStatus,
  WorkflowStepInfo,
  WorkflowTrigger,
  WorkflowTriggerKind,
  WorkflowVersion,
  WorkflowVersionOwner,
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

const VERSION_OWNERS: readonly WorkflowVersionOwner[] = [
  "user",
  "organization",
];

const TRIGGER_KINDS: readonly WorkflowTriggerKind[] = [
  "manual",
  "webhook",
  "schedule",
  "event",
  "form",
  "chat",
];

const SCOPES: readonly WorkflowDefinitionScope[] = ["tenant", "system"];

const GRANT_PRINCIPALS: readonly WorkflowGrantPrincipal[] = [
  "user",
  "team",
  "role",
];

const GRANT_ACTIONS: readonly WorkflowGrantAction[] = ["run", "edit"];

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
    subjectTypes: stringsOf(row["subjectTypes"]),
    scope:
      row["scope"] === undefined || row["scope"] === null
        ? "tenant"
        : enumOrThrow(row["scope"], SCOPES, "definition scope"),
    forkedFrom: optionalText(row["forkedFrom"]),
    forkedFromVersion: optionalNumber(row["forkedFromVersion"]),
    restricted: row["restricted"] === true,
    ...("published" in row ? { published: optionalNumber(published) } : {}),
    ...("draft" in row ? { draft: row["draft"] === true } : {}),
    ...("upstreamVersion" in row
      ? { upstreamVersion: optionalNumber(row["upstreamVersion"]) }
      : {}),
    ...("behind" in row ? { behind: row["behind"] === true } : {}),
    ...("optedOut" in row && typeof row["optedOut"] === "boolean"
      ? { optedOut: row["optedOut"] }
      : {}),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

export function grantOf(row: Record<string, unknown>): WorkflowDefinitionGrant {
  return {
    id: textOf(row["id"]),
    definition: textOf(row["definition"]),
    principalKind: enumOrThrow(
      row["principalKind"],
      GRANT_PRINCIPALS,
      "grant principal",
    ),
    principalId: textOf(row["principalId"]),
    action: enumOrThrow(row["action"], GRANT_ACTIONS, "grant action"),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

function optionalNumber(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
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
    publishedBy: optionalText(row["publishedBy"]),
    owner:
      row["owner"] === null || row["owner"] === undefined
        ? undefined
        : enumOrThrow(row["owner"], VERSION_OWNERS, "version owner"),
    permissions: Array.isArray(row["permissions"])
      ? stringsOf(row["permissions"])
      : [],
    ...("graph" in row ? { graph: graphOf(row["graph"]) } : {}),
    ...("compiled" in row && row["compiled"] !== null
      ? { compiled: row["compiled"] }
      : {}),
    ...(isRecord(row["inputSchema"])
      ? { inputSchema: row["inputSchema"] }
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
    throw new TypeError("workflow-editor: a credential_ref has no provider");
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
    operation: optionalText(row["operation"]),
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
