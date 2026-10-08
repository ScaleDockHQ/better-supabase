import type { ChatTransport, UIMessage } from "ai";

import type { AssistantTransportConfig } from "../../react/body.ts";
import type { AssistantState } from "../../react/index.ts";
import type { UseDurableAssistantOptions } from "./index.ts";

export type { AssistantState } from "../../react/index.ts";
export type { UseDurableAssistantOptions } from "./index.ts";

const CLIENT_ONLY =
  "better-supabase: the durable chat hooks run in Client Components only. In Server Components read the chat row and pass `resume` and `messages` to the client.";

/** The `react-server` build of `durableTransport`. */
export const durableTransport: (
  config: AssistantTransportConfig,
) => ChatTransport<UIMessage> = () => {
  throw new Error(CLIENT_ONLY);
};

/** The `react-server` build of `useDurableAssistant`. */
export const useDurableAssistant: (
  options: UseDurableAssistantOptions,
) => AssistantState = () => {
  throw new Error(CLIENT_ONLY);
};
