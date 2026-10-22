import type {
  MessagesState,
  ConversationsState,
  UseMessagesOptions,
  UseConversationsOptions,
} from "./index.ts";

export type {
  MessagesState,
  ConversationsState,
  MessageDraft,
  UseMessagesOptions,
  UseConversationsOptions,
} from "./index.ts";

/** The `react-server` build of `useMessages`: call `messaging.list()` instead. */
export const useMessages: (
  options: UseMessagesOptions,
) => MessagesState = () => {
  throw new Error(
    "better-supabase: useMessages() runs in Client Components only. In Server Components call `messaging.list()` instead.",
  );
};

/**
 * The `react-server` build of `useConversations`: call
 * `messaging.conversations()` instead.
 */
export const useConversations: (
  options?: UseConversationsOptions,
) => ConversationsState = () => {
  throw new Error(
    "better-supabase: useConversations() runs in Client Components only. In Server Components call `messaging.conversations()` instead.",
  );
};
