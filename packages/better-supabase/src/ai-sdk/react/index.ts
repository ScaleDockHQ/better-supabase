"use client";

import { type UseChatHelpers, useChat } from "@ai-sdk/react";
import {
  type ChatOnFinishCallback,
  DefaultChatTransport,
  type UIMessage,
} from "ai";
import { useCallback, useMemo } from "react";

export interface UseAssistantOptions {
  /** The chat id; make one on the client for a new chat. */
  readonly id: string;
  /** The route of `createAssistant`. Defaults to `/api/chat`. */
  readonly api?: string;
  /** The model the next answer uses; the server checks it against the catalog. */
  readonly model?: string;
  /** The stored history, such as `toUIMessages(path)` from the server. */
  readonly messages?: UIMessage[];
  /** Picks up an answer that is still being written. Defaults to true. */
  readonly resume?: boolean;
  /** Extra fields for the request body. */
  readonly body?: Readonly<Record<string, unknown>>;
  readonly headers?: Readonly<Record<string, string>>;
  readonly onError?: (error: Error) => void;
  readonly onFinish?: ChatOnFinishCallback<UIMessage>;
  /** Custom throttle wait in ms for message updates. */
  readonly throttle?: number;
}

export type AssistantState = UseChatHelpers<UIMessage> & {
  /** Stops the answer on the server too, so it is stored as stopped. */
  stop: () => Promise<void>;
};

/**
 * `useChat` wired to `createAssistant`: it sends only the new message (the
 * server keeps the history), resumes a running answer after a reload and
 * stops it on the server.
 */
export function useAssistant(options: UseAssistantOptions): AssistantState {
  const api = options.api ?? "/api/chat";
  const { id, model, body, headers } = options;
  const transport = useMemo(
    () =>
      new DefaultChatTransport<UIMessage>({
        api,
        ...(headers === undefined ? {} : { headers: { ...headers } }),
        prepareSendMessagesRequest: (request) => {
          const message = request.messages.findLast(
            (entry) => entry.role === "user",
          );
          return {
            body: {
              ...body,
              ...request.body,
              id: request.id,
              message,
              trigger: request.trigger,
              ...(request.messageId === undefined
                ? {}
                : { messageId: request.messageId }),
              ...(model === undefined ? {} : { model }),
            },
          };
        },
        prepareReconnectToStreamRequest: (request) => ({
          api: `${api}/${encodeURIComponent(request.id)}/stream`,
        }),
      }),
    [api, model, body, headers],
  );
  const chat = useChat({
    id,
    transport,
    resume: options.resume ?? true,
    ...(options.messages === undefined ? {} : { messages: options.messages }),
    ...(options.onError === undefined ? {} : { onError: options.onError }),
    ...(options.onFinish === undefined ? {} : { onFinish: options.onFinish }),
    ...(options.throttle === undefined ? {} : { throttle: options.throttle }),
  });
  const { stop: stopLocal } = chat;
  const stop = useCallback(async () => {
    await stopLocal();
    await fetch(`${api}/${encodeURIComponent(id)}/stop`, {
      method: "POST",
      ...(headers === undefined ? {} : { headers: { ...headers } }),
    });
  }, [api, id, headers, stopLocal]);
  return { ...chat, stop };
}
