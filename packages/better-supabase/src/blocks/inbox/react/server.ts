import type {
  ConversationState,
  InboxListState,
  InboxWidgetState,
  UseConversationOptions,
  UseInboxOptions,
  UseInboxWidgetOptions,
} from "./index.ts";

export type {
  ConversationState,
  InboxListState,
  InboxSource,
  InboxWidgetState,
  UseConversationOptions,
  UseInboxOptions,
  UseInboxWidgetOptions,
} from "./index.ts";

const clientOnly = (hook: string, instead: string): never => {
  throw new Error(
    `better-supabase: ${hook}() runs in Client Components only. In Server Components call ${instead} instead.`,
  );
};

/** The `react-server` build of `useInbox`: call `inbox.conversations.list()` instead. */
export const useInbox: <T>(
  options: UseInboxOptions<T>,
) => InboxListState<T> = () =>
  clientOnly("useInbox", "`inbox.conversations.list()`");

/** The `react-server` build of `useConversation`: call `inbox.messages.list()` instead. */
export const useConversation: <T>(
  options: UseConversationOptions<T>,
) => ConversationState<T> = () =>
  clientOnly("useConversation", "`inbox.messages.list()`");

/** The `react-server` build of `useInboxWidget`. */
export const useInboxWidget: <T>(
  options: UseInboxWidgetOptions<T>,
) => InboxWidgetState<T> = () =>
  clientOnly("useInboxWidget", "`inbox.messages.list()`");
