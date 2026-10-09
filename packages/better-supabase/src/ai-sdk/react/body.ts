import type { UIMessage } from "ai";

/** What a transport factory gets from `useAssistant`. */
export interface AssistantTransportConfig {
  readonly api: string;
  readonly model: string | undefined;
  readonly body: Readonly<Record<string, unknown>> | undefined;
  readonly headers: Readonly<Record<string, string>> | undefined;
}

/** The body `useAssistant` sends for the user's newest message. */
export function assistantBody(
  config: AssistantTransportConfig,
  request: {
    readonly id: string;
    readonly messages: readonly UIMessage[];
    readonly body?: object | undefined;
    readonly trigger: string;
    readonly messageId?: string | undefined;
  },
): Record<string, unknown> {
  const message = request.messages.findLast((entry) => entry.role === "user");
  return {
    ...config.body,
    ...request.body,
    id: request.id,
    message,
    trigger: request.trigger,
    ...(request.messageId === undefined
      ? {}
      : { messageId: request.messageId }),
    ...(config.model === undefined ? {} : { model: config.model }),
  };
}
