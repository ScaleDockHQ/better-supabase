"use client";

import { type UseChatHelpers, useChat } from "@ai-sdk/react";
import {
  type ChatOnFinishCallback,
  type ChatTransport,
  DefaultChatTransport,
  type UIMessage,
} from "ai";
import { useCallback, useMemo } from "react";

import { type AssistantTransportConfig, assistantBody } from "./body.ts";

export type { AssistantTransportConfig } from "./body.ts";

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
  /**
   * Makes the transport instead of the default one, such as
   * `durableTransport` from `better-supabase/ai-sdk/workflow/react`. Pass a
   * function defined outside the component, so the transport is kept.
   */
  readonly transport?: (
    config: AssistantTransportConfig,
  ) => ChatTransport<UIMessage>;
  /** Sends again without user input, such as once every approval is answered. */
  readonly sendAutomaticallyWhen?: (options: {
    messages: UIMessage[];
  }) => boolean | PromiseLike<boolean>;
}

function defaultTransport(
  config: AssistantTransportConfig,
): ChatTransport<UIMessage> {
  const { api, headers } = config;
  return new DefaultChatTransport<UIMessage>({
    api,
    ...(headers === undefined ? {} : { headers: { ...headers } }),
    prepareSendMessagesRequest: (request) => ({
      body: assistantBody(config, request),
    }),
    prepareReconnectToStreamRequest: (request) => ({
      api: `${api}/${encodeURIComponent(request.id)}/stream`,
    }),
  });
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
  const makeTransport = options.transport ?? defaultTransport;
  const transport = useMemo(
    () => makeTransport({ api, model, body, headers }),
    [makeTransport, api, model, body, headers],
  );
  const chat = useChat({
    id,
    transport,
    resume: options.resume ?? true,
    ...(options.messages === undefined ? {} : { messages: options.messages }),
    ...(options.onError === undefined ? {} : { onError: options.onError }),
    ...(options.onFinish === undefined ? {} : { onFinish: options.onFinish }),
    ...(options.throttle === undefined ? {} : { throttle: options.throttle }),
    ...(options.sendAutomaticallyWhen === undefined
      ? {}
      : { sendAutomaticallyWhen: options.sendAutomaticallyWhen }),
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
