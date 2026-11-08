import type { ChatTransport, UIMessage } from "ai";

import type { AssistantTransportConfig } from "../react/body.ts";
import type { AssistantState } from "../react/index.ts";
import type {
  DurableTransportOptions,
  UseDurableAssistantOptions,
} from "./index.ts";

export type { AssistantState } from "../react/index.ts";

export type {
  DurableTransportOptions,
  UseDurableAssistantOptions,
} from "./index.ts";

const CLIENT_ONLY =
  "better-supabase: the durable chat hooks run in Client Components only. In Server Components read the chat row and pass `resume` and `messages` to the client.";

/** The `react-server` build of `durableTransport`. */
export const durableTransport: <UI_MESSAGE extends UIMessage = UIMessage>(
  config: AssistantTransportConfig,
  options?: DurableTransportOptions<UI_MESSAGE>,
) => ChatTransport<UI_MESSAGE> = () => {
  throw new Error(CLIENT_ONLY);
};

/** The `react-server` build of `useDurableAssistant`. */
export const useDurableAssistant: <UI_MESSAGE extends UIMessage = UIMessage>(
  options: UseDurableAssistantOptions<UI_MESSAGE>,
) => AssistantState<UI_MESSAGE> = () => {
  throw new Error(CLIENT_ONLY);
};
