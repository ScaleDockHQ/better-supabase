import type { StandardSchemaV1 } from "@standard-schema/spec";

import { isRecord } from "../shared.ts";

/** `$id` of `schemas/ai-message-v1.json`, the JSON Schema of `AiMessage`. */
export const AI_MESSAGE_SCHEMA_ID =
  "https://unpkg.com/better-supabase/schemas/ai-message-v1.json";

type ProviderMetadata = Readonly<Record<string, unknown>>;

interface PartBase {
  /** What the provider attached, kept for replay; never read for logic. */
  readonly providerMetadata?: ProviderMetadata;
}

export interface AiTextPart extends PartBase {
  readonly type: "text";
  readonly text: string;
  readonly state?: "streaming" | "done";
}

export interface AiReasoningPart extends PartBase {
  readonly type: "reasoning";
  readonly text: string;
  readonly state?: "streaming" | "done";
}

export interface AiFilePart extends PartBase {
  readonly type: "file";
  /** IANA media type, e.g. `image/png`. */
  readonly mediaType: string;
  /** A URL the reader can fetch: `https:`, `data:` or a storage path the app signs. */
  readonly url: string;
  readonly filename?: string;
}

export interface AiToolCallPart extends PartBase {
  readonly type: "tool-call";
  readonly toolCallId: string;
  readonly toolName: string;
  readonly input: unknown;
  /** The provider ran the tool itself (web search on the model's side). */
  readonly providerExecuted?: boolean;
}

export interface AiToolResultPart extends PartBase {
  readonly type: "tool-result";
  readonly toolCallId: string;
  readonly toolName: string;
  readonly output: unknown;
  readonly isError?: boolean;
}

export interface AiToolApprovalPart extends PartBase {
  readonly type: "tool-approval";
  readonly toolCallId: string;
  readonly approvalId: string;
  readonly state: "requested" | "approved" | "denied";
  readonly reason?: string;
}

export interface AiSourcePart extends PartBase {
  readonly type: "source";
  readonly sourceType: "url" | "document";
  readonly id: string;
  readonly url?: string;
  readonly title?: string;
  readonly mediaType?: string;
}

/** App data in the message (`data-weather` in the AI SDK becomes `name: "weather"`). */
export interface AiDataPart extends PartBase {
  readonly type: "data";
  readonly name: string;
  readonly id?: string;
  readonly data: unknown;
}

/** Where a model step starts or ends, for multi-step tool loops. */
export interface AiStepPart extends PartBase {
  readonly type: "step";
  readonly boundary: "start" | "finish";
  readonly stepId?: string;
}

/**
 * A part of a canonical message. Adapters map their SDK's parts onto these;
 * a part with no counterpart becomes a `data` part rather than being lost.
 */
export type AiMessagePart =
  | AiTextPart
  | AiReasoningPart
  | AiFilePart
  | AiToolCallPart
  | AiToolResultPart
  | AiToolApprovalPart
  | AiSourcePart
  | AiDataPart
  | AiStepPart;

export type AiMessagePartType = AiMessagePart["type"];

export type AiMessageRole = "system" | "user" | "assistant" | "tool";

/** A message in the SDK-neutral format `ai_messages.parts` stores (version 1). */
export interface AiMessage {
  readonly id: string;
  readonly role: AiMessageRole;
  readonly parts: readonly AiMessagePart[];
  readonly metadata?: Readonly<Record<string, unknown>>;
}

export const AI_MESSAGE_PART_TYPES: readonly AiMessagePartType[] = [
  "text",
  "reasoning",
  "file",
  "tool-call",
  "tool-result",
  "tool-approval",
  "source",
  "data",
  "step",
];

const ROLES: ReadonlySet<string> = new Set<AiMessageRole>([
  "system",
  "user",
  "assistant",
  "tool",
]);

type Issue = StandardSchemaV1.Issue;
type Path = readonly PropertyKey[];

interface Field {
  readonly kind: "string" | "boolean" | "object" | "any";
  readonly required?: boolean;
  readonly values?: readonly string[];
}

const text: Field = { kind: "string", required: true };
const optionalText: Field = { kind: "string" };
const state: Field = { kind: "string", values: ["streaming", "done"] };

const FIELDS: {
  readonly [K in AiMessagePartType]: Readonly<Record<string, Field>>;
} = {
  text: { text, state },
  reasoning: { text, state },
  file: { mediaType: text, url: text, filename: optionalText },
  "tool-call": {
    toolCallId: text,
    toolName: text,
    input: { kind: "any", required: true },
    providerExecuted: { kind: "boolean" },
  },
  "tool-result": {
    toolCallId: text,
    toolName: text,
    output: { kind: "any", required: true },
    isError: { kind: "boolean" },
  },
  "tool-approval": {
    toolCallId: text,
    approvalId: text,
    state: {
      kind: "string",
      required: true,
      values: ["requested", "approved", "denied"],
    },
    reason: optionalText,
  },
  source: {
    sourceType: { kind: "string", required: true, values: ["url", "document"] },
    id: text,
    url: optionalText,
    title: optionalText,
    mediaType: optionalText,
  },
  data: {
    name: text,
    id: optionalText,
    data: { kind: "any", required: true },
  },
  step: {
    boundary: { kind: "string", required: true, values: ["start", "finish"] },
    stepId: optionalText,
  },
};

const isPartType = (value: unknown): value is AiMessagePartType =>
  typeof value === "string" && Object.hasOwn(FIELDS, value);

function checkField(
  value: unknown,
  field: Field,
  path: Path,
  issues: Issue[],
): void {
  switch (field.kind) {
    case "any": {
      return;
    }
    case "boolean": {
      if (typeof value !== "boolean")
        issues.push({ message: "Expected a boolean", path });
      return;
    }
    case "object": {
      if (!isRecord(value))
        issues.push({ message: "Expected an object", path });
      return;
    }
    case "string": {
      if (typeof value !== "string")
        issues.push({ message: "Expected a string", path });
      else if (field.values !== undefined && !field.values.includes(value))
        issues.push({
          message: `Expected one of ${field.values.join(", ")}`,
          path,
        });
      return;
    }
    default: {
      const unreachable: never = field.kind;
      return unreachable;
    }
  }
}

function checkPart(value: unknown, path: Path, issues: Issue[]): void {
  if (!isRecord(value)) {
    issues.push({ message: "Expected a part object", path });
    return;
  }
  const type = value["type"];
  if (!isPartType(type)) {
    issues.push({
      message: `Expected a part type: ${AI_MESSAGE_PART_TYPES.join(", ")}`,
      path: [...path, "type"],
    });
    return;
  }
  const fields = FIELDS[type];
  for (const [key, entry] of Object.entries(value)) {
    if (key === "type") continue;
    if (key === "providerMetadata") {
      checkField(entry, { kind: "object" }, [...path, key], issues);
      continue;
    }
    const field = fields[key];
    if (field === undefined)
      issues.push({
        message: `Unknown ${type} part field`,
        path: [...path, key],
      });
    else if (entry !== undefined)
      checkField(entry, field, [...path, key], issues);
  }
  for (const [key, field] of Object.entries(fields))
    if (field.required === true && value[key] === undefined)
      issues.push({ message: "Required", path: [...path, key] });
}

function checkMessage(value: unknown): readonly Issue[] {
  const issues: Issue[] = [];
  if (!isRecord(value)) return [{ message: "Expected a message object" }];
  for (const key of Object.keys(value))
    if (!["id", "role", "parts", "metadata"].includes(key))
      issues.push({ message: "Unknown message field", path: [key] });
  if (typeof value["id"] !== "string" || value["id"].length === 0)
    issues.push({ message: "Expected a non-empty id", path: ["id"] });
  const role = value["role"];
  if (typeof role !== "string" || !ROLES.has(role))
    issues.push({
      message: "Expected system, user, assistant or tool",
      path: ["role"],
    });
  const parts = value["parts"];
  if (Array.isArray(parts))
    for (const [index, part] of parts.entries())
      checkPart(part, ["parts", index], issues);
  else issues.push({ message: "Expected a parts array", path: ["parts"] });
  if (value["metadata"] !== undefined && !isRecord(value["metadata"]))
    issues.push({ message: "Expected an object", path: ["metadata"] });
  return issues;
}

/**
 * A Standard Schema for `AiMessage`, matching `schemas/ai-message-v1.json`.
 * Pass it to `validate()` or any library that takes a Standard Schema.
 */
export const aiMessageSchema: StandardSchemaV1<unknown, AiMessage> = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate(value) {
      const issues = checkMessage(value);
      // SAFETY: checkMessage found no issue, so value has the AiMessage shape.
      return issues.length > 0 ? { issues } : { value: value as AiMessage };
    },
  },
};

/** Whether `value` is a canonical message, without collecting the issues. */
export function isAiMessage(value: unknown): value is AiMessage {
  return checkMessage(value).length === 0;
}
