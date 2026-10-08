import type { AssistantState, UseAssistantOptions } from "./index.ts";

export type { AssistantState, UseAssistantOptions } from "./index.ts";

/** The `react-server` build of `useAssistant`: load the history with `aiChat.messages.path()` instead. */
export const useAssistant: (
  options: UseAssistantOptions,
) => AssistantState = () => {
  throw new Error(
    "better-supabase: useAssistant() runs in Client Components only. In Server Components call `aiChat.messages.path()` and pass `toUIMessages(path)` as `messages` instead.",
  );
};
