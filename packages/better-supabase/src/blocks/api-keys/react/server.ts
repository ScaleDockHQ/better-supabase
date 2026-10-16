import type { ApiKeysState, UseApiKeysOptions } from "./index.ts";

export type {
  ApiKeyChange,
  ApiKeyDraft,
  ApiKeysState,
  UseApiKeysOptions,
} from "./index.ts";

/** The `react-server` build of `useApiKeys`: call `apiKeys.list()` instead. */
export const useApiKeys: (options: UseApiKeysOptions) => ApiKeysState = () => {
  throw new Error(
    "better-supabase: useApiKeys() runs in Client Components only. In Server Components call `apiKeys.list()` instead.",
  );
};
