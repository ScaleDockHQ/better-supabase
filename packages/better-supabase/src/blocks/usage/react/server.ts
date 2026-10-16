import type { useUsageMeter as useClientUsageMeter } from "./index.ts";

export type {
  MeterReading,
  UsageMeterState,
  UseUsageMeterOptions,
} from "./index.ts";

/** The `react-server` build of `useUsageMeter`: call `usage.overview()` instead. */
export const useUsageMeter: typeof useClientUsageMeter = () => {
  throw new Error(
    "better-supabase: useUsageMeter() runs in Client Components only. In Server Components call `usage.overview(organizationId)` instead.",
  );
};
