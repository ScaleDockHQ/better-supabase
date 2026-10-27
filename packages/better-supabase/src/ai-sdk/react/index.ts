"use client";

import type { UseChatHelpers } from "@ai-sdk/react";
import type {
  ChatInit,
  ChatOnFinishCallback,
  ChatTransport,
  UIMessage,
} from "ai";

import { useChat } from "@ai-sdk/react";
import { useCallback, useMemo } from "react";

import type { AssistantTransportConfig } from "./body.ts";

import { assistantTransport } from "./transport.ts";

export type { AssistantTransportConfig } from "./body.ts";

export { assistantTransport } from "./transport.ts";

/** `useChat` options passed through as they are. */
type PassedChatOptions<UI_MESSAGE extends UIMessage> = Pick<
  ChatInit<UI_MESSAGE>,
  "onToolCall" | "onData" | "messageMetadataSchema" | "dataPartSchemas"
>;

export interface UseAssistantOptions<
  UI_MESSAGE extends UIMessage = UIMessage,
> extends PassedChatOptions<UI_MESSAGE> {
  /** The chat id; make one on the client for a new chat. */
  readonly id: string;
  /** The route of `createAssistant`. Defaults to `/api/chat`. */
  readonly api?: string;
  /** The model the next answer uses; the server checks it against the catalog. */
  readonly model?: string;
  /** The stored history, such as `toUIMessages(path)` from the server. */
  readonly messages?: UI_MESSAGE[];
  /** Picks up an answer that is still being written. Defaults to true. */
  readonly resume?: boolean;
  /** Extra fields for the request body. */
  readonly body?: Readonly<Record<string, unknown>>;
  readonly headers?: Readonly<Record<string, string>>;
  readonly onError?: (error: Error) => void;
  readonly onFinish?: ChatOnFinishCallback<UI_MESSAGE>;
  /** Custom throttle wait in ms for message updates. */
  readonly throttle?: number;
  /**
   * Makes the transport instead of the default one, such as `durableTransport`
   * from `better-supabase/ai-sdk/workflow/react`. Pass a function defined
   * outside the component, so the transport is kept.
   */
  readonly transport?: (
    config: AssistantTransportConfig,
  ) => ChatTransport<UI_MESSAGE>;
  /** Sends again without user input, such as once every approval is answered. */
  readonly sendAutomaticallyWhen?: (options: {
    messages: UI_MESSAGE[];
  }) => boolean | PromiseLike<boolean>;
}

export type AssistantState<UI_MESSAGE extends UIMessage = UIMessage> =
  UseChatHelpers<UI_MESSAGE> & {
    /** Stops the answer on the server too, so it is stored as stopped. */
    stop: () => Promise<void>;
  };

/**
 * `useChat` wired to `createAssistant`: it sends only the new message (the
 * server keeps the history), resumes a running answer after a reload and stops
 * it on the server.
 */
export function useAssistant<UI_MESSAGE extends UIMessage = UIMessage>(
  options: UseAssistantOptions<UI_MESSAGE>,
): AssistantState<UI_MESSAGE> {
  const api = options.api ?? "/api/chat";
  const { id, model, body, headers } = options;
  const makeTransport = options.transport ?? assistantTransport<UI_MESSAGE>;

  const transport = useMemo(
    () => makeTransport({ api, model, body, headers }),
    [makeTransport, api, model, body, headers],
  );

  const chat = useChat<UI_MESSAGE>({
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
    ...(options.onToolCall === undefined
      ? {}
      : { onToolCall: options.onToolCall }),
    ...(options.onData === undefined ? {} : { onData: options.onData }),
    ...(options.messageMetadataSchema === undefined
      ? {}
      : { messageMetadataSchema: options.messageMetadataSchema }),
    ...(options.dataPartSchemas === undefined
      ? {}
      : { dataPartSchemas: options.dataPartSchemas }),
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

export {
  type UseAssistantCompletionOptions,
  type UseAssistantObjectOptions,
  useAssistantCompletion,
  useAssistantObject,
} from "./generations.ts";
