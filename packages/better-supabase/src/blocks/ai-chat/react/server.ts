import type {
  AiChatsState,
  AiChatTreeState,
  AiModelsState,
  AiShareState,
  UseAiChatsOptions,
  UseAiChatTreeOptions,
} from "./index.ts";

export type {
  AiChatsState,
  AiChatTreeState,
  AiModelsState,
  AiShareState,
  UseAiChatsOptions,
  UseAiChatTreeOptions,
} from "./index.ts";

const clientOnly = (hook: string, instead: string): never => {
  throw new Error(
    `better-supabase: ${hook}() runs in Client Components only. In Server Components call \`${instead}\` instead.`,
  );
};

/** The `react-server` build of `useAiChats`: call `aiChat.chats.list()` instead. */
export const useAiChats: (options?: UseAiChatsOptions) => AiChatsState = () =>
  clientOnly("useAiChats", "aiChat.chats.list()");

/** The `react-server` build of `useAiChatTree`: call `aiChat.messages.path()` instead. */
export const useAiChatTree: (
  chatId: string | null | undefined,
  options?: UseAiChatTreeOptions,
) => AiChatTreeState = () =>
  clientOnly("useAiChatTree", "aiChat.messages.path()");

/** The `react-server` build of `useAiModels`: call `aiChat.models.allowed()` instead. */
export const useAiModels: (
  organizationId?: string | null,
  options?: { readonly schema?: string },
) => AiModelsState = () => clientOnly("useAiModels", "aiChat.models.allowed()");

/** The `react-server` build of `useAiShare`: call `aiChat.shares.list()` instead. */
export const useAiShare: (
  chatId: string | null | undefined,
  options?: { readonly schema?: string },
) => AiShareState = () => clientOnly("useAiShare", "aiChat.shares.list()");
