import type { UseCompletionHelpers, UseObjectHelpers } from "@ai-sdk/react";

import type {
  UseAssistantCompletionOptions,
  UseAssistantObjectOptions,
} from "./generations.ts";
import type { AssistantState, UseAssistantOptions } from "./index.ts";

export type {
  UseAssistantCompletionOptions,
  UseAssistantObjectOptions,
} from "./generations.ts";

export type { AssistantState, UseAssistantOptions } from "./index.ts";

export { assistantTransport } from "./transport.ts";

const clientOnly = (name: string): never => {
  throw new Error(`better-supabase: ${name}() runs in Client Components only.`);
};

/** The `react-server` build of `useAssistantCompletion`: it throws. */
export const useAssistantCompletion: (
  options?: UseAssistantCompletionOptions,
) => UseCompletionHelpers = () => clientOnly("useAssistantCompletion");

/** The `react-server` build of `useAssistantObject`: it throws. */
export const useAssistantObject: (
  options: UseAssistantObjectOptions<never>,
) => UseObjectHelpers<unknown, unknown> = () =>
  clientOnly("useAssistantObject");

/**
 * The `react-server` build of `useAssistant`: load the history with
 * `aiChat.messages.path()` instead.
 */
export const useAssistant: (
  options: UseAssistantOptions,
) => AssistantState = () => {
  throw new Error(
    "better-supabase: useAssistant() runs in Client Components only. In Server Components call `aiChat.messages.path()` and pass `toUIMessages(path)` as `messages` instead.",
  );
};
