"use client";

import type {
  AuditFilters,
  AuditLogActions,
  AuditLogSnapshot,
} from "../client.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createAudit } from "../audit-log.ts";
import { createAuditLogController } from "../client.ts";

export type { AuditFilters } from "../client.ts";

export interface UseAuditLogOptions {
  /** The organization; the table waits without one. */
  readonly organizationId: string | null | undefined;
  /** The filters of the first page; change them with `setFilters`. */
  readonly filters?: AuditFilters;
  /** Entries per page, default 50, at most 1000. */
  readonly limit?: number;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
}

export interface AuditLogState extends AuditLogSnapshot, AuditLogActions {}

/**
 * One organization's audit trail through the browser client, newest first,
 * with filters by actor, action or text and older pages on `loadMore`.
 * The audit module's read policy decides what the caller sees. The same
 * hook runs in React DOM and React Native.
 *
 * ```tsx
 * const { entries, filters, setFilters, loadMore } = useAuditLog({ organizationId });
 * ```
 */
export function useAuditLog(options: UseAuditLogOptions): AuditLogState {
  const { supabase, auth } = useBlockEnv();
  const latest = useLatest(options);
  const { organizationId, limit, schema } = options;

  return useController(() => {
    const { filters } = latest.current;

    return createAuditLogController({
      client: createAudit({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
      auth,
      organizationId: organizationId ?? null,
      ...(filters === undefined ? {} : { filters }),
      ...(limit === undefined ? {} : { limit }),
    });
  }, [supabase, auth, organizationId, limit, schema, latest]).view;
}
