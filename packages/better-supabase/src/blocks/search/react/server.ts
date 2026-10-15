import type { CommandSearchState, UseCommandSearchOptions } from "./index.ts";

export type { CommandSearchState, UseCommandSearchOptions } from "./index.ts";
export {
  groupHits,
  type CommandSearchGroup,
  type CommandSearchItem,
} from "../groups.ts";

/** The `react-server` build of `useCommandSearch`: call `search.search()` instead. */
export const useCommandSearch: (
  options?: UseCommandSearchOptions,
) => CommandSearchState = () => {
  throw new Error(
    "better-supabase: useCommandSearch() runs in Client Components only. In Server Components call `search.search()` instead.",
  );
};
