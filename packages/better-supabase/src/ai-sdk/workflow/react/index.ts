"use client";

import { WorkflowChatTransport } from "@ai-sdk/workflow/client";
import {
  type ChatTransport,
  lastAssistantMessageIsCompleteWithApprovalResponses,
  type UIMessage,
} from "ai";

import {
  type AssistantTransportConfig,
  assistantBody,
} from "../../react/body.ts";
import {
  type AssistantState,
  useAssistant,
  type UseAssistantOptions,
} from "../../react/index.ts";

export type { AssistantState } from "../../react/index.ts";

/** The decisions in an assistant message whose approvals the user answered. */
function approvalsOf(message: UIMessage | undefined): {
  approvalId: string;
  approved: boolean;
  reason?: string;
}[] {
  if (message?.role !== "assistant") return [];
  return message.parts.flatMap((part) =>
    "state" in part && part.state === "approval-responded"
      ? [
          {
            approvalId: part.approval.id,
            approved: part.approval.approved,
            ...(part.approval.reason === undefined
              ? {}
              : { reason: part.approval.reason }),
          },
        ]
      : [],
  );
}

/**
 * The transport for `durableChat`: the Workflow SDK's chat transport, which
 * reconnects until the segment's `finish` when a request drops. It sends
 * the user's newest message, or the answered approvals of the last answer
 * so the waiting turn continues. Pass it as `useAssistant({ transport })`.
 */
export function durableTransport(
  config: AssistantTransportConfig,
): ChatTransport<UIMessage> {
  const { api, headers } = config;
  const extra = headers === undefined ? {} : { headers: { ...headers } };
  const transport = new WorkflowChatTransport<UIMessage>({
    api,
    prepareSendMessagesRequest: (request) => {
      const approvals = approvalsOf(request.messages.at(-1));
      return {
        ...extra,
        body:
          approvals.length > 0
            ? { ...config.body, id: request.id, approvals }
            : assistantBody(config, request),
      };
    },
    prepareReconnectToStreamRequest: (request) => ({
      ...extra,
      api: `${api}/${encodeURIComponent(request.id)}/stream`,
    }),
  });
  return {
    sendMessages: ({ messageId, abortSignal, ...rest }) =>
      transport.sendMessages({
        ...rest,
        ...(messageId === undefined ? {} : { messageId }),
        ...(abortSignal === undefined ? {} : { abortSignal }),
      }),
    reconnectToStream: (options) => transport.reconnectToStream(options),
  };
}

export type UseDurableAssistantOptions = Omit<UseAssistantOptions, "transport">;

/**
 * `useAssistant` on `durableChat`. It continues the answer once every
 * approval is answered. `resume` defaults to `false`: pass
 * `chat.activeStreamId !== undefined` from the chat row so a reload picks
 * up the running answer.
 */
export function useDurableAssistant(
  options: UseDurableAssistantOptions,
): AssistantState {
  return useAssistant({
    ...options,
    resume: options.resume ?? false,
    sendAutomaticallyWhen:
      options.sendAutomaticallyWhen ??
      lastAssistantMessageIsCompleteWithApprovalResponses,
    transport: durableTransport,
  });
}
