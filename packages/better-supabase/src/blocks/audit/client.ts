import type { DbError } from "../../core/errors.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type {
  AuditCursor,
  AuditListOptions,
  AuditLog,
  AuditRecord,
} from "./audit-log.ts";

import { defineController, whileSignedIn } from "../controller.ts";

/** What an audit table filters by; an empty value matches every entry. */
export interface AuditFilters {
  /** One actor's entries, by user id. */
  readonly actorId?: string | undefined;
  /** One action's entries, by event type such as `invitation.created`. */
  readonly eventType?: string | undefined;
  /** Text in the summary, the labels or the event type. */
  readonly search?: string | undefined;
}

export interface AuditLogControllerOptions {
  readonly client: Pick<AuditLog, "list">;
  readonly auth: AuthPort;
  /** The organization; the table waits without one. */
  readonly organizationId: string | null;
  /** The filters of the first page. */
  readonly filters?: AuditFilters;
  /** Entries per page, default 50, at most 1000. */
  readonly limit?: number;
}

export interface AuditLogSnapshot {
  /** The pages loaded so far, newest first; `undefined` until the first one. */
  readonly entries: readonly AuditRecord[] | undefined;
  readonly filters: AuditFilters;
  /** Whether a page is loading. */
  readonly loading: boolean;
  /** Whether `loadMore` has older entries to load. */
  readonly hasMore: boolean;
  readonly error: DbError | undefined;
}

export interface AuditLogActions {
  /** Replaces the filters and loads the first page again. */
  readonly setFilters: (filters: AuditFilters) => Promise<void>;
  /** Appends the next, older page. */
  readonly loadMore: () => Promise<void>;
  /** Loads the first page again with the current filters. */
  readonly refresh: () => Promise<void>;
}

export type AuditLogController = Controller<AuditLogSnapshot, AuditLogActions>;

function listOptions(
  organizationId: string,
  filters: AuditFilters,
  limit: number | undefined,
  cursor: AuditCursor | undefined,
): AuditListOptions {
  const { actorId, eventType, search } = filters;

  return {
    organizationId,
    order: "desc",
    ...(actorId ? { actorId } : {}),
    ...(eventType ? { eventType } : {}),
    ...(search?.trim() ? { search: search.trim() } : {}),
    ...(limit === undefined ? {} : { limit }),
    ...(cursor === undefined ? {} : { cursor }),
  };
}

/**
 * One organization's audit trail for an audit table: the newest page as
 * the caller may read it, `setFilters` to narrow it by actor, action or
 * text, and `loadMore` for older pages.
 */
export function createAuditLogController(
  options: AuditLogControllerOptions,
): AuditLogController {
  const { client, organizationId, limit } = options;

  return defineController<AuditLogSnapshot, AuditLogActions>(
    {
      entries: undefined,
      filters: options.filters ?? {},
      loading: false,
      hasMore: false,
      error: undefined,
    },
    (state) => {
      let ticket = 0;
      let next: AuditCursor | undefined;

      const load = async (more: boolean): Promise<void> => {
        if (organizationId === null) {
          return;
        }

        if (more && next === undefined) {
          return;
        }

        const request = ++ticket;
        state.set({ loading: true });

        const result = await client.list(
          listOptions(
            organizationId,
            state.get().filters,
            limit,
            more ? next : undefined,
          ),
        );

        if (request !== ticket) {
          return;
        }

        if (!result.ok) {
          state.set({ loading: false, error: result.error });

          return;
        }

        next = result.data.next;
        state.set((current) => ({
          loading: false,
          error: undefined,
          hasMore: next !== undefined,
          entries: more
            ? [...(current.entries ?? []), ...result.data.entries]
            : result.data.entries,
        }));
      };

      const refresh = (): Promise<void> => load(false);

      return {
        actions: {
          refresh,
          loadMore: () => load(true),
          setFilters: (filters) => {
            next = undefined;
            state.set({ filters, entries: undefined, hasMore: false });

            return refresh();
          },
        },
        start: () =>
          organizationId === null
            ? undefined
            : whileSignedIn(options.auth, () => {
                void refresh();

                return;
              }),
      };
    },
  );
}
