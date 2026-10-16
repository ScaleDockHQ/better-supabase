import type { usePlanPicker as useClientPlanPicker } from "./index.ts";

export type {
  CheckoutStarted,
  PlanCatalog,
  PlanOption,
  PlanPickerState,
  UsePlanPickerOptions,
} from "./index.ts";

/** The `react-server` build of `usePlanPicker`: read the plan catalog and `billing.status()` instead. */
export const usePlanPicker: typeof useClientPlanPicker = () => {
  throw new Error(
    "better-supabase: usePlanPicker() runs in Client Components only. In Server Components read your plan catalog and `billing.status()` instead.",
  );
};
