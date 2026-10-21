import type { AssistantModelMessage, ModelMessage, ToolModelMessage } from "ai";

import type {
  AiMessage,
  AiMessagePart,
  AiToolApprovalPart,
} from "../blocks/ai-chat/message.ts";

import { isRecord } from "../core/block-helpers.ts";
import { DENIED_TOOL_OUTPUT, meta } from "./messages.ts";

/** A source a model step cited, as `StepResult.sources` holds it. */
export interface ModelSource {
  readonly sourceType: "url" | "document";
  readonly id: string;
  readonly url?: string;
  readonly title?: string;
  readonly mediaType?: string;
  readonly providerMetadata?: unknown;
}

/** An approval decision the messages may no longer carry. */
export interface ModelApproval {
  readonly approvalId: string;
  readonly toolCallId: string;
  readonly state: AiToolApprovalPart["state"];
  readonly reason?: string;
}

export interface FromModelMessagesOptions {
  /** The sources the steps cited; model messages don't keep them. */
  readonly sources?: readonly ModelSource[];
  /** Decisions to apply over the approval parts the messages hold. */
  readonly approvals?: readonly ModelApproval[];
}

const FETCHABLE_URL = /^(?:https?|data):/u;

function fileUrl(data: unknown): string | undefined {
  if (data instanceof URL) {
    return data.href;
  }

  if (typeof data === "string") {
    return FETCHABLE_URL.test(data) ? data : undefined;
  }

  if (isRecord(data) && data["type"] === "url") {
    return fileUrl(data["url"]);
  }

  return undefined;
}

type ModelToolOutput = Extract<
  ToolModelMessage["content"][number],
  { type: "tool-result" }
>["output"];

function outputOf(output: ModelToolOutput): {
  readonly output: unknown;
  readonly isError: boolean;
  readonly denied?: string | undefined;
} {
  switch (output.type) {
    case "text":
    case "json":
    case "content": {
      return { output: output.value, isError: false };
    }

    case "error-text":
    case "error-json": {
      return { output: output.value, isError: true };
    }

    case "execution-denied": {
      const reason = output.reason ?? DENIED_TOOL_OUTPUT;

      return { output: reason, isError: true, denied: reason };
    }

    default: {
      const unreachable: never = output;

      return unreachable;
    }
  }
}

/** Collects one turn's parts, keeping one approval part per tool call. */
class TurnParts {
  readonly parts: AiMessagePart[] = [];
  readonly #approvalAt = new Map<string, number>();
  readonly #callOf = new Map<string, string>();

  constructor(approvals: readonly ModelApproval[]) {
    for (const approval of approvals) {
      this.#callOf.set(approval.approvalId, approval.toolCallId);
    }
  }

  approval(part: AiToolApprovalPart): void {
    this.#callOf.set(part.approvalId, part.toolCallId);
    const at = this.#approvalAt.get(part.toolCallId);

    if (at === undefined) {
      this.#approvalAt.set(part.toolCallId, this.parts.length);
      this.parts.push(part);
    } else {
      this.parts[at] = part;
    }
  }

  callOf(approvalId: string): string | undefined {
    return this.#callOf.get(approvalId);
  }

  result(toolCallId: string, toolName: string, output: ModelToolOutput): void {
    const result = outputOf(output);

    if (result.denied !== undefined) {
      const at = this.#approvalAt.get(toolCallId);
      const current = at === undefined ? undefined : this.parts[at];
      this.approval({
        type: "tool-approval",
        toolCallId,
        approvalId:
          current?.type === "tool-approval"
            ? current.approvalId
            : `approval-${toolCallId}`,
        state: "denied",
        reason: result.denied,
      });
    }

    this.parts.push({
      type: "tool-result",
      toolCallId,
      toolName,
      output: result.output,
      ...(result.isError ? { isError: true } : {}),
    });
  }
}

function assistantParts(message: AssistantModelMessage, turn: TurnParts): void {
  if (typeof message.content === "string") {
    if (message.content !== "") {
      turn.parts.push({ type: "text", text: message.content, state: "done" });
    }

    return;
  }

  for (const part of message.content) {
    switch (part.type) {
      case "text":
      case "reasoning": {
        turn.parts.push({ type: part.type, text: part.text, state: "done" });
        break;
      }

      case "file": {
        const url = fileUrl(part.data);

        if (url !== undefined) {
          turn.parts.push({
            type: "file",
            mediaType: part.mediaType,
            url,
            ...(part.filename === undefined ? {} : { filename: part.filename }),
          });
        }

        break;
      }

      case "reasoning-file": {
        const url = fileUrl(part.data);

        if (url !== undefined) {
          turn.parts.push({
            type: "data",
            name: "ui.reasoning-file",
            data: { mediaType: part.mediaType, url },
          });
        }

        break;
      }

      case "custom": {
        turn.parts.push({
          type: "data",
          name: "ui.custom",
          data: { kind: part.kind },
        });
        break;
      }

      case "tool-call": {
        turn.parts.push({
          type: "tool-call",
          toolCallId: part.toolCallId,
          toolName: part.toolName,
          input: part.input ?? {},
          ...(part.providerExecuted === undefined
            ? {}
            : { providerExecuted: part.providerExecuted }),
        });
        break;
      }

      case "tool-result": {
        turn.result(part.toolCallId, part.toolName, part.output);
        break;
      }

      case "tool-approval-request": {
        turn.approval({
          type: "tool-approval",
          toolCallId: part.toolCallId,
          approvalId: part.approvalId,
          state: "requested",
        });
        break;
      }

      default: {
        const unreachable: never = part;

        return unreachable;
      }
    }
  }
}

function toolMessageParts(message: ToolModelMessage, turn: TurnParts): void {
  for (const part of message.content) {
    switch (part.type) {
      case "tool-result": {
        turn.result(part.toolCallId, part.toolName, part.output);
        break;
      }

      case "tool-approval-response": {
        const toolCallId = turn.callOf(part.approvalId);

        if (toolCallId !== undefined) {
          turn.approval({
            type: "tool-approval",
            toolCallId,
            approvalId: part.approvalId,
            state: part.approved ? "approved" : "denied",
            ...(part.reason === undefined ? {} : { reason: part.reason }),
          });
        }

        break;
      }

      default: {
        const unreachable: never = part;

        return unreachable;
      }
    }
  }
}

/**
 * One answer in the canonical form, from the model messages an agent added in a
 * turn (`result.messages` after the history). Each assistant message starts a
 * step whose id is `<id>:<n>`, so saving the answer again after another step
 * updates the same message.
 */
export function fromModelMessages(
  id: string,
  messages: readonly ModelMessage[],
  options: FromModelMessagesOptions = {},
): AiMessage {
  const approvals = options.approvals ?? [];
  const turn = new TurnParts(approvals);
  let step = 0;

  for (const message of messages) {
    if (message.role === "assistant") {
      turn.parts.push({
        type: "step",
        boundary: "start",
        stepId: `${id}:${step}`,
      });
      step += 1;
      assistantParts(message, turn);
    } else if (message.role === "tool") {
      toolMessageParts(message, turn);
    }
  }

  for (const approval of approvals) {
    turn.approval({
      type: "tool-approval",
      toolCallId: approval.toolCallId,
      approvalId: approval.approvalId,
      state: approval.state,
      ...(approval.reason === undefined ? {} : { reason: approval.reason }),
    });
  }

  for (const source of options.sources ?? []) {
    turn.parts.push({
      type: "source",
      sourceType: source.sourceType,
      id: source.id,
      ...(source.url === undefined ? {} : { url: source.url }),
      ...(source.title === undefined ? {} : { title: source.title }),
      ...(source.mediaType === undefined
        ? {}
        : { mediaType: source.mediaType }),
      ...meta(source.providerMetadata),
    });
  }

  return { id, role: "assistant", parts: turn.parts };
}
