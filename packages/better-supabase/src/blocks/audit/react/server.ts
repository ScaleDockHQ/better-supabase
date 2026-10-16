import type { AuditLogState, UseAuditLogOptions } from "./index.ts";

export type {
  AuditFilters,
  AuditLogState,
  UseAuditLogOptions,
} from "./index.ts";

/** The `react-server` build of `useAuditLog`: call `audit.list()` instead. */
export const useAuditLog: (
  options: UseAuditLogOptions,
) => AuditLogState = () => {
  throw new Error(
    "better-supabase: useAuditLog() runs in Client Components only. In Server Components call `audit.list()` instead.",
  );
};
