import type { Checklist, ChecklistScope } from "../onboarding.ts";
import type { OnboardingState, UseOnboardingOptions } from "./index.ts";

export type { OnboardingState, UseOnboardingOptions } from "./index.ts";

/** The `react-server` build of `useOnboarding`: call the checklist's `progress()` instead. */
export const useOnboarding: <Id extends string, Scope extends ChecklistScope>(
  checklist: Checklist<Id, Scope>,
  options?: UseOnboardingOptions,
) => OnboardingState<Id> = () => {
  throw new Error(
    "better-supabase: useOnboarding() runs in Client Components only. In Server Components call `checklist.connect(...).progress()` instead.",
  );
};
