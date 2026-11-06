"use client";

import type { WorkflowChatTransportOptions } from "@ai-sdk/workflow/client";
import type { ChatTransport, UIMessage, UIMessageChunk } from "ai";

import { WorkflowChatTransport } from "@ai-sdk/workflow/client";
import { lastAssistantMessageIsCompleteWithApprovalResponses } from "ai";
import { useMemo } from "react";

import type { AssistantTransportConfig } from "../react/body.ts";
import type { AssistantState, UseAssistantOptions } from "../react/index.ts";

import { assistantBody } from "../react/body.ts";
import { useAssistant } from "../react/index.ts";

export type { AssistantState } from "../react/index.ts";

/** The decisions in an assistant message whose approvals the user answered. */
function approvalsOf(
  message: UIMessage | undefined,
): { approvalId: string; approved: boolean; reason?: string }[] {
  if (message?.role !== "assistant") {
    return [];
  }

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
 * What `durableTransport` takes from the app, on top of the library's own
 * request handling: every `WorkflowChatTransport` option except `api`.
 *
 * - `prepareSendMessagesRequest` and `prepareReconnectToStreamRequest` refine the
 *   library's request: the library builds it first (the newest message, or the
 *   answered approvals), then your function's `body`, `headers`, `credentials`
 *   and `api` replace or extend it. `headers` are merged.
 * - `fetch`, `onChatSendMessage`, `onChatEnd`, `maxConsecutiveErrors` and
 *   `initialStartIndex` go to the Workflow SDK's transport as they are.
 */
export type DurableTransportOptions<UI_MESSAGE extends UIMessage = UIMessage> =
  Omit<WorkflowChatTransportOptions<UI_MESSAGE>, "api">;

const headersOf = (
  ...sources: (HeadersInit | undefined)[]
): Record<string, string> => {
  const merged: Record<string, string> = {};

  for (const source of sources) {
    for (const [key, value] of new Headers(source)) {
      merged[key] = value;
    }
  }

  return merged;
};

/**
 * The transport for `durableChat`: the Workflow SDK's chat transport, which
 * reconnects until the segment's `finish` when a request drops. It sends the
 * user's newest message, or the answered approvals of the last answer so the
 * waiting turn continues. Pass it as `useAssistant({ transport })`, or use
 * `useDurableAssistant`. A reconnect the server answers with 204 (no durable
 * run) resolves to `null`.
 */
export function durableTransport<UI_MESSAGE extends UIMessage = UIMessage>(
  config: AssistantTransportConfig,
  options: DurableTransportOptions<UI_MESSAGE> = {},
): ChatTransport<UI_MESSAGE> {
  const { api } = config;
  const baseFetch = options.fetch ?? globalThis.fetch;
  const seen = { empty: false };
  const wasEmpty = (): boolean => seen.empty;

  const transport = new WorkflowChatTransport<UI_MESSAGE>({
    ...options,
    api,
    fetch: async (input, init) => {
      const response = await baseFetch(input, init);

      if (response.status === 204) {
        seen.empty = true;
      }

      return response;
    },
    prepareSendMessagesRequest: async (request) => {
      const approvals = approvalsOf(request.messages.at(-1));

      const ours = {
        headers: headersOf(config.headers, request.headers),
        body:
          approvals.length > 0
            ? { ...config.body, id: request.id, approvals }
            : assistantBody(config, request),
      };

      const theirs = await options.prepareSendMessagesRequest?.(request);

      return {
        ...ours,
        ...theirs,
        headers: headersOf(ours.headers, theirs?.headers),
      };
    },
    prepareReconnectToStreamRequest: async (request) => {
      const ours = {
        headers: headersOf(config.headers, request.headers),
        api: `${api}/${encodeURIComponent(request.id)}/stream`,
      };

      const theirs = await options.prepareReconnectToStreamRequest?.(request);

      return {
        ...ours,
        ...theirs,
        headers: headersOf(ours.headers, theirs?.headers),
      };
    },
  });

  return {
    sendMessages: ({ messageId, abortSignal, ...rest }) =>
      transport.sendMessages({
        ...rest,
        ...(messageId === undefined ? {} : { messageId }),
        ...(abortSignal === undefined ? {} : { abortSignal }),
      }),
    reconnectToStream: async (reconnect) => {
      seen.empty = false;
      const stream = await transport.reconnectToStream(reconnect);

      if (stream === null) {
        return null;
      }

      // The transport reads lazily: the first chunk shows whether the server had a run.
      const reader = stream.getReader();
      let first: ReadableStreamReadResult<UIMessageChunk>;

      try {
        first = await reader.read();
      } catch (cause) {
        if (wasEmpty()) {
          return null;
        }

        throw cause;
      }

      if (first.done && wasEmpty()) {
        return null;
      }

      let pending: ReadableStreamReadResult<UIMessageChunk> | undefined = first;

      return new ReadableStream<UIMessageChunk>({
        async pull(controller) {
          const next = pending ?? (await reader.read());
          pending = undefined;

          if (next.done) {
            controller.close();
          } else {
            controller.enqueue(next.value);
          }
        },
        cancel: (reason) => reader.cancel(reason),
      });
    },
  };
}

export interface UseDurableAssistantOptions<
  UI_MESSAGE extends UIMessage = UIMessage,
> extends Omit<UseAssistantOptions<UI_MESSAGE>, "transport"> {
  /**
   * Options of the Workflow SDK's transport. Keep the object stable (module
   * scope or `useMemo`): a new one makes a new transport.
   */
  readonly transportOptions?: DurableTransportOptions<UI_MESSAGE>;
}

/**
 * `useAssistant` on `durableChat`. It continues the answer once every approval
 * is answered. `resume` defaults to `false`: pass `chat.activeStreamId !==
 * undefined` from the chat row so a reload picks up the running answer.
 */
export function useDurableAssistant<UI_MESSAGE extends UIMessage = UIMessage>(
  options: UseDurableAssistantOptions<UI_MESSAGE>,
): AssistantState<UI_MESSAGE> {
  const { transportOptions, ...rest } = options;

  const transport = useMemo(
    () => (config: AssistantTransportConfig) =>
      durableTransport<UI_MESSAGE>(config, transportOptions),
    [transportOptions],
  );

  return useAssistant<UI_MESSAGE>({
    ...rest,
    resume: options.resume ?? false,
    sendAutomaticallyWhen:
      options.sendAutomaticallyWhen ??
      lastAssistantMessageIsCompleteWithApprovalResponses,
    transport,
  });
}
