import type { RuleBuilderState, UseRuleBuilderOptions } from "./index.ts";

export type { RuleBuilderState, UseRuleBuilderOptions } from "./index.ts";

/** The `react-server` build of `useRuleBuilder`: call `rules.get()` instead. */
export const useRuleBuilder: (
  options: UseRuleBuilderOptions,
) => RuleBuilderState = () => {
  throw new Error(
    "better-supabase: useRuleBuilder() runs in Client Components only. In Server Components call `rules.get()` instead.",
  );
};
