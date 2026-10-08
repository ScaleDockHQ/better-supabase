import type {
  DynamicToolUIPart,
  ProviderMetadata,
  ToolUIPart,
  UIMessage,
} from "ai";

import type {
  AiMessage,
  AiMessagePart,
  AiToolApprovalPart,
  AiToolCallPart,
  AiToolResultPart,
} from "../blocks/ai-chat/message.ts";

import { isRecord } from "../blocks/shared.ts";

/** The `format` the chat tree stores next to an AI SDK message it keeps as is. */
export const AI_SDK_UI_FORMAT = "ai-sdk-ui";

/** The output a denied tool call gets in the canonical history. */
export const DENIED_TOOL_OUTPUT = "The tool call was denied.";

type UIPart = UIMessage["parts"][number];
type ToolPart = ToolUIPart | DynamicToolUIPart;
type Metadata = Readonly<Record<string, unknown>>;

/** A message as the chat tree returns it with `native: true`. */
interface StoredLike extends AiMessage {
  readonly format?: string;
  readonly native?: unknown;
}

const meta = (value: unknown): { readonly providerMetadata?: Metadata } =>
  isRecord(value) ? { providerMetadata: value } : {};

/** Provider metadata is an object of objects per provider; JSON values inside. */
function isProviderMetadata(value: unknown): value is ProviderMetadata {
  return isRecord(value) && Object.values(value).every(isRecord);
}

const isToolPart = (part: UIPart): part is ToolPart =>
  part.type === "dynamic-tool" || part.type.startsWith("tool-");

/** Whether `value` has the shape of an AI SDK `UIMessage`. */
export function isUIMessage(value: unknown): value is UIMessage {
  return (
    isRecord(value) &&
    typeof value["id"] === "string" &&
    (value["role"] === "system" ||
      value["role"] === "user" ||
      value["role"] === "assistant") &&
    Array.isArray(value["parts"])
  );
}

function toolParts(part: ToolPart): AiMessagePart[] {
  const toolName =
    part.type === "dynamic-tool" ? part.toolName : part.type.slice(5);
  const call: AiToolCallPart = {
    type: "tool-call",
    toolCallId: part.toolCallId,
    toolName,
    input: part.input ?? {},
    ...(part.providerExecuted === undefined
      ? {}
      : { providerExecuted: part.providerExecuted }),
    ...meta(part.callProviderMetadata),
  };
  const parts: AiMessagePart[] = [call];
  const { approval } = part;
  if (approval !== undefined) {
    let state: AiToolApprovalPart["state"] = "requested";
    if (approval.approved === true) state = "approved";
    else if (approval.approved === false) state = "denied";
    parts.push({
      type: "tool-approval",
      toolCallId: part.toolCallId,
      approvalId: approval.id,
      state,
      ...(approval.reason === undefined ? {} : { reason: approval.reason }),
    });
  }
  const result = (
    output: unknown,
    isError: boolean,
    metadata?: unknown,
  ): AiToolResultPart => ({
    type: "tool-result",
    toolCallId: part.toolCallId,
    toolName,
    output,
    ...(isError ? { isError } : {}),
    ...meta(metadata),
  });
  switch (part.state) {
    case "output-available": {
      parts.push(result(part.output, false, part.resultProviderMetadata));
      break;
    }
    case "output-error": {
      parts.push(result(part.errorText, true, part.resultProviderMetadata));
      break;
    }
    case "output-denied": {
      parts.push(result(part.approval.reason ?? DENIED_TOOL_OUTPUT, true));
      break;
    }
    case "input-streaming":
    case "input-available":
    case "approval-requested":
    case "approval-responded": {
      break;
    }
    default: {
      const unreachable: never = part;
      return unreachable;
    }
  }
  return parts;
}

function fromPart(part: UIPart): AiMessagePart[] {
  if (isToolPart(part)) return toolParts(part);
  switch (part.type) {
    case "text":
    case "reasoning": {
      return [
        {
          type: part.type,
          text: part.text,
          ...(part.state === undefined ? {} : { state: part.state }),
          ...meta(part.providerMetadata),
        },
      ];
    }
    case "file": {
      return [
        {
          type: "file",
          mediaType: part.mediaType,
          url: part.url,
          ...(part.filename === undefined ? {} : { filename: part.filename }),
          ...meta(part.providerMetadata),
        },
      ];
    }
    case "source-url": {
      return [
        {
          type: "source",
          sourceType: "url",
          id: part.sourceId,
          url: part.url,
          ...(part.title === undefined ? {} : { title: part.title }),
          ...meta(part.providerMetadata),
        },
      ];
    }
    case "source-document": {
      return [
        {
          type: "source",
          sourceType: "document",
          id: part.sourceId,
          title: part.title,
          mediaType: part.mediaType,
          ...meta(part.providerMetadata),
        },
      ];
    }
    case "step-start": {
      return [{ type: "step", boundary: "start" }];
    }
    case "custom": {
      return [
        {
          type: "data",
          name: "ui.custom",
          data: { kind: part.kind },
          ...meta(part.providerMetadata),
        },
      ];
    }
    case "reasoning-file": {
      return [
        {
          type: "data",
          name: "ui.reasoning-file",
          data: { mediaType: part.mediaType, url: part.url },
          ...meta(part.providerMetadata),
        },
      ];
    }
    default: {
      if (part.type.startsWith("data-") && "data" in part)
        return [
          {
            type: "data",
            name: part.type.slice(5),
            ...("id" in part && typeof part.id === "string"
              ? { id: part.id }
              : {}),
            data: part.data,
          },
        ];
      return [];
    }
  }
}

/**
 * The canonical form of an AI SDK `UIMessage`. Tool parts become a
 * `tool-call`, then a `tool-approval` and a `tool-result` as far as the
 * call got; parts with no canonical counterpart become `data` parts named
 * `ui.<type>`.
 */
export function fromUIMessage(message: UIMessage): AiMessage {
  return {
    id: message.id,
    role: message.role,
    parts: message.parts.flatMap(fromPart),
    ...(isRecord(message.metadata) ? { metadata: message.metadata } : {}),
  };
}

interface ToolState {
  call: AiToolCallPart;
  approval?: AiToolApprovalPart;
  result?: AiToolResultPart;
}

function toToolPart({ call, approval, result }: ToolState): UIPart {
  const base = {
    type: `tool-${call.toolName}` as const,
    toolCallId: call.toolCallId,
    input: call.input,
    ...(call.providerExecuted === undefined
      ? {}
      : { providerExecuted: call.providerExecuted }),
    ...(isProviderMetadata(call.providerMetadata)
      ? { callProviderMetadata: call.providerMetadata }
      : {}),
  };
  const reason =
    approval?.reason === undefined ? {} : { reason: approval.reason };
  if (approval?.state === "denied")
    return result === undefined
      ? {
          ...base,
          state: "approval-responded",
          approval: { id: approval.approvalId, approved: false, ...reason },
        }
      : {
          ...base,
          state: "output-denied",
          approval: { id: approval.approvalId, approved: false, ...reason },
        };
  const approved =
    approval?.state === "approved"
      ? { approval: { id: approval.approvalId, approved: true as const } }
      : {};
  if (result !== undefined) {
    const resultMeta = isProviderMetadata(result.providerMetadata)
      ? { resultProviderMetadata: result.providerMetadata }
      : {};
    if (result.isError === true)
      return {
        ...base,
        ...approved,
        ...resultMeta,
        state: "output-error",
        errorText:
          typeof result.output === "string"
            ? result.output
            : JSON.stringify(result.output),
      };
    return {
      ...base,
      ...approved,
      ...resultMeta,
      state: "output-available",
      output: result.output,
    };
  }
  if (approval?.state === "requested")
    return {
      ...base,
      state: "approval-requested",
      approval: { id: approval.approvalId },
    };
  if (approval?.state === "approved")
    return {
      ...base,
      state: "approval-responded",
      approval: { id: approval.approvalId, approved: true, ...reason },
    };
  return { ...base, state: "input-available" };
}

function toPart(part: AiMessagePart): UIPart | undefined {
  const providerMetadata = isProviderMetadata(part.providerMetadata)
    ? { providerMetadata: part.providerMetadata }
    : {};
  switch (part.type) {
    case "text":
    case "reasoning": {
      return {
        type: part.type,
        text: part.text,
        ...(part.state === undefined ? {} : { state: part.state }),
        ...providerMetadata,
      };
    }
    case "file": {
      return {
        type: "file",
        mediaType: part.mediaType,
        url: part.url,
        ...(part.filename === undefined ? {} : { filename: part.filename }),
        ...providerMetadata,
      };
    }
    case "source": {
      return part.sourceType === "url"
        ? {
            type: "source-url",
            sourceId: part.id,
            url: part.url ?? "",
            ...(part.title === undefined ? {} : { title: part.title }),
            ...providerMetadata,
          }
        : {
            type: "source-document",
            sourceId: part.id,
            mediaType: part.mediaType ?? "application/octet-stream",
            title: part.title ?? "",
            ...providerMetadata,
          };
    }
    case "step": {
      return part.boundary === "start" ? { type: "step-start" } : undefined;
    }
    case "data": {
      if (part.name === "ui.custom" && isRecord(part.data)) {
        const kind = part.data["kind"];
        return typeof kind === "string" && kind.includes(".")
          ? {
              type: "custom",
              // SAFETY: the check above found the provider.type dot.
              kind: kind as `${string}.${string}`,
              ...providerMetadata,
            }
          : undefined;
      }
      if (part.name === "ui.reasoning-file" && isRecord(part.data)) {
        const { mediaType, url } = part.data;
        return typeof mediaType === "string" && typeof url === "string"
          ? { type: "reasoning-file", mediaType, url, ...providerMetadata }
          : undefined;
      }
      return {
        type: `data-${part.name}`,
        ...(part.id === undefined ? {} : { id: part.id }),
        data: part.data,
      };
    }
    case "tool-call":
    case "tool-result":
    case "tool-approval": {
      return undefined;
    }
    default: {
      const unreachable: never = part;
      return unreachable;
    }
  }
}

function render(
  parts: readonly AiMessagePart[],
  tools: Map<string, ToolState>,
  into: UIPart[],
  slots: Map<string, number>,
): void {
  for (const part of parts) {
    if (
      part.type === "tool-call" ||
      part.type === "tool-result" ||
      part.type === "tool-approval"
    ) {
      let state = tools.get(part.toolCallId);
      if (part.type === "tool-call") {
        state = { ...state, call: part };
        tools.set(part.toolCallId, state);
        if (!slots.has(part.toolCallId)) {
          slots.set(part.toolCallId, into.length);
          into.push(toToolPart(state));
        }
      } else if (state !== undefined) {
        if (part.type === "tool-result") state.result = part;
        else state.approval = part;
      }
      const slot = slots.get(part.toolCallId);
      if (state !== undefined && slot !== undefined)
        into[slot] = toToolPart(state);
      continue;
    }
    const converted = toPart(part);
    if (converted !== undefined) into.push(converted);
  }
}

function nativeOf(message: AiMessage): UIMessage | undefined {
  const stored: StoredLike = message;
  return stored.format === AI_SDK_UI_FORMAT && isUIMessage(stored.native)
    ? stored.native
    : undefined;
}

/**
 * The AI SDK form of a canonical message: the stored native message when the
 * tree kept one (`format: "ai-sdk-ui"`), otherwise a conversion. A `tool`
 * message becomes an assistant message.
 */
export function toUIMessage(message: AiMessage): UIMessage {
  const native = nativeOf(message);
  if (native !== undefined) return native;
  const parts: UIPart[] = [];
  render(message.parts, new Map(), parts, new Map());
  return {
    id: message.id,
    role: message.role === "tool" ? "assistant" : message.role,
    parts,
    ...(message.metadata === undefined ? {} : { metadata: message.metadata }),
  };
}

/**
 * Converts a history. Tool results and approvals in later messages, such as
 * the `tool` messages of other SDKs, update the tool part of the assistant
 * message that made the call.
 */
export function toUIMessages(messages: readonly AiMessage[]): UIMessage[] {
  const out: UIMessage[] = [];
  const tools = new Map<string, ToolState>();
  let owner: { parts: UIPart[]; slots: Map<string, number> } | undefined;
  for (const message of messages) {
    const native = nativeOf(message);
    if (native !== undefined) {
      out.push(native);
      owner = undefined;
      continue;
    }
    if (message.role === "tool" && owner !== undefined) {
      render(message.parts, tools, owner.parts, owner.slots);
      continue;
    }
    const parts: UIPart[] = [];
    const slots = new Map<string, number>();
    render(message.parts, tools, parts, slots);
    out.push({
      id: message.id,
      role: message.role === "tool" ? "assistant" : message.role,
      parts,
      ...(message.metadata === undefined ? {} : { metadata: message.metadata }),
    });
    owner = message.role === "user" ? undefined : { parts, slots };
  }
  return out;
}
