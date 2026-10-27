import type { ChatTransport, UIMessage } from "ai";

import { DefaultChatTransport } from "ai";

import type { AssistantTransportConfig } from "./body.ts";

import { assistantBody } from "./body.ts";

/**
 * The transport `useAssistant` uses by default: it sends only the new message
 * and reconnects to `${api}/${id}/stream`. Wrap it to add your own `fetch`.
 */
export function assistantTransport<UI_MESSAGE extends UIMessage = UIMessage>(
  config: AssistantTransportConfig,
): ChatTransport<UI_MESSAGE> {
  const { api, headers } = config;

  return new DefaultChatTransport<UI_MESSAGE>({
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
