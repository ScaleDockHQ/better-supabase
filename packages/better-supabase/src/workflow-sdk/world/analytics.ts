import type {
  Analytics,
  AnalyticsAttributeKey,
  AnalyticsEvent,
  AnalyticsHook,
  AnalyticsListEventsParams,
  AnalyticsRun,
  AnalyticsStep,
  AnalyticsWait,
  PaginatedResponse,
  PaginationOptions,
} from "@workflow/world";
import type { Pool } from "pg";

/** world-postgres stores UTC in `timestamp without time zone` columns. */
const utc = (column: string): string => `(${column} at time zone 'UTC')`;

const RUN_COLUMNS = `
  r.id as "runId", r.status::text as status, r.deployment_id as "deploymentId",
  r.name as "workflowName", nullif(r.spec_version, '')::int as "specVersion",
  coalesce(r.attributes, '{}'::jsonb) as attributes,
  ${utc("r.created_at")} as "createdAt", ${utc("r.updated_at")} as "updatedAt",
  ${utc("r.started_at")} as "startedAt", ${utc("r.completed_at")} as "completedAt",
  r.error_code as "errorCode",
  r.encryption_public_key is not null as "workflowEncryptionEnabled"`;

const STEP_COLUMNS = `
  s.run_id as "runId", s.step_id as "stepId", s.step_name as "stepName",
  s.status::text as status, s.attempt,
  ${utc("s.created_at")} as "createdAt", ${utc("s.updated_at")} as "updatedAt",
  ${utc("s.started_at")} as "startedAt", ${utc("s.completed_at")} as "completedAt",
  ${utc("s.retry_after")} as "retryAfter"`;

const EVENT_COLUMNS = `
  e.run_id as "runId", e.id as "eventId", e.type as "eventType",
  e.correlation_id as "correlationId", e.correlation_id as "entityId",
  (select s.step_name from workflow.workflow_steps s
    where s.run_id = e.run_id and s.step_id = e.correlation_id) as "stepName",
  r.name as "workflowName", r.deployment_id as "deploymentId",
  e.spec_version as "specVersion", ${utc("r.created_at")} as "runCreatedAt",
  ${utc("e.created_at")} as "createdAt",
  case when e.payload ? 'resumeAt' then (e.payload ->> 'resumeAt')::timestamptz end as "resumeAt",
  case when e.payload ? 'retryAfter' then (e.payload ->> 'retryAfter')::timestamptz end as "retryAfter",
  e.payload ->> 'errorCode' as "errorCode"`;

/** world-postgres keys waits `<runId>-<correlationId>`; analytics names them by the correlation id, as steps and hooks. */
const WAIT_COLUMNS = `
  w.run_id as "runId",
  case when starts_with(w.wait_id, w.run_id || '-')
    then substr(w.wait_id, length(w.run_id) + 2) else w.wait_id end as "waitId",
  w.status::text as status,
  ${utc("w.resume_at")} as "resumeAt", ${utc("w.created_at")} as "createdAt",
  ${utc("w.updated_at")} as "updatedAt", ${utc("w.completed_at")} as "completedAt"`;

/** Hooks keep their row only while active, so the status comes from the event log. */
const HOOKS = `
  select e.run_id as "runId", e.correlation_id as "hookId",
    case
      when bool_or(e.type = 'hook_conflict') then 'conflict'
      when bool_or(e.type = 'hook_disposed') then 'disposed'
      when bool_or(e.type = 'hook_received') then 'received'
      else 'created'
    end as status,
    ${utc("min(e.created_at)")} as "createdAt",
    ${utc("max(e.created_at)")} as "updatedAt",
    ${utc("max(e.created_at) filter (where e.type = 'hook_received')")} as "receivedAt",
    ${utc("max(e.created_at) filter (where e.type = 'hook_disposed')")} as "disposedAt",
    bool_or(h.is_webhook) as "isWebhook", bool_or(h.is_system) as "isSystem"
  from workflow.workflow_events e
  left join workflow.workflow_hooks h on h.hook_id = e.correlation_id
  where e.type like 'hook\\_%' and e.correlation_id is not null`;

function page(
  pagination: PaginationOptions | undefined,
  max: number,
): { limit: number; offset: number; order: "asc" | "desc" } {
  const limit = Math.min(max, Math.max(1, pagination?.limit ?? max));
  if (pagination?.limit !== undefined && pagination.limit > max) {
    throw new RangeError(
      `better-supabase: the analytics page limit is ${String(max)}, got ${String(pagination.limit)}`,
    );
  }
  const offset = Number(pagination?.cursor ?? 0);
  return {
    limit,
    offset: Number.isSafeInteger(offset) && offset > 0 ? offset : 0,
    order: pagination?.sortOrder === "asc" ? "asc" : "desc",
  };
}

function paged<T>(
  rows: readonly T[],
  limit: number,
  offset: number,
): PaginatedResponse<T> {
  const hasMore = rows.length > limit;
  return {
    data: rows.slice(0, limit),
    hasMore,
    cursor: hasMore ? String(offset + limit) : null,
  };
}

/** Converts SQL nulls to the optional fields the analytics schemas allow. */
function compact<T>(row: Record<string, unknown>): T {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(row))
    if (value !== null) out[key] = value;
  // SAFETY: each query selects the columns of its analytics schema under their names.
  return out as T;
}

function notFound(what: string, id: string): Error {
  return new Error(`better-supabase: workflow ${what} "${id}" not found`);
}

const RUN_SCOPED_LIMIT = 1000;
const LIMIT = 100;
const MAX_ATTRIBUTE_FILTERS = 8;

/**
 * The World's `analytics` namespace over the world-postgres tables: the run
 * listing filters by status, name, window and latest attributes (the GIN
 * index on `workflow_runs.attributes` serves the filter).
 */
export function createAnalytics(pool: Pool): Analytics {
  const rows = async <T>(
    sql: string,
    params: readonly unknown[],
  ): Promise<T[]> => {
    const result = await pool.query(sql, [...params]);
    return result.rows.map((row: Record<string, unknown>) => compact<T>(row));
  };
  const one = async <T>(
    sql: string,
    params: readonly unknown[],
    what: string,
    id: string,
  ): Promise<T> => {
    const [row] = await rows<T>(sql, params);
    if (row === undefined) throw notFound(what, id);
    return row;
  };
  const window = (
    params: { startTime?: string; endTime?: string },
    column: string,
    values: unknown[],
  ): string => {
    if ((params.startTime === undefined) !== (params.endTime === undefined)) {
      throw new TypeError(
        "better-supabase: analytics startTime and endTime go together",
      );
    }
    if (params.startTime === undefined || params.endTime === undefined)
      return "";
    values.push(params.startTime, params.endTime);
    return ` and ${utc(column)} between $${String(values.length - 1)}::timestamptz and $${String(values.length)}::timestamptz`;
  };

  const listEvents = async (
    params: AnalyticsListEventsParams,
  ): Promise<PaginatedResponse<AnalyticsEvent>> => {
    const { limit, offset, order } = page(params.pagination, RUN_SCOPED_LIMIT);
    const values: unknown[] = [params.runId];
    let where = "e.run_id = $1";
    if (params.eventType !== undefined) {
      values.push(params.eventType);
      where += ` and e.type = $${String(values.length)}`;
    }
    if (params.correlationId !== undefined) {
      values.push(params.correlationId);
      where += ` and e.correlation_id = $${String(values.length)}`;
    }
    values.push(limit + 1, offset);
    const data = await rows<AnalyticsEvent>(
      `select ${EVENT_COLUMNS} from workflow.workflow_events e
       join workflow.workflow_runs r on r.id = e.run_id
       where ${where} order by e.id ${order}
       limit $${String(values.length - 1)} offset $${String(values.length)}`,
      values,
    );
    return paged(data, limit, offset);
  };

  return {
    runs: {
      get: (runId) =>
        one<AnalyticsRun>(
          `select ${RUN_COLUMNS} from workflow.workflow_runs r where r.id = $1`,
          [runId],
          "run",
          runId,
        ),
      async list(params = {}) {
        const { limit, offset, order } = page(params.pagination, LIMIT);
        const values: unknown[] = [];
        let where = "true";
        if (params.workflowName !== undefined) {
          values.push(params.workflowName);
          where += ` and r.name = $${String(values.length)}`;
        }
        if (params.status !== undefined) {
          values.push(params.status);
          where += ` and r.status::text = $${String(values.length)}`;
        }
        if (params.attributes !== undefined) {
          if (Object.keys(params.attributes).length > MAX_ATTRIBUTE_FILTERS) {
            throw new RangeError(
              `better-supabase: analytics filters by at most ${String(MAX_ATTRIBUTE_FILTERS)} attributes`,
            );
          }
          values.push(JSON.stringify(params.attributes));
          where += ` and r.attributes @> $${String(values.length)}::jsonb`;
        }
        where += window(params, "r.updated_at", values);
        values.push(limit + 1, offset);
        const data = await rows<AnalyticsRun>(
          `select ${RUN_COLUMNS} from workflow.workflow_runs r where ${where}
           order by r.created_at ${order}, r.id ${order}
           limit $${String(values.length - 1)} offset $${String(values.length)}`,
          values,
        );
        return paged(data, limit, offset);
      },
    },
    attributes: {
      async list(params = {}) {
        const { limit, offset } = page(params.pagination, LIMIT);
        const values: unknown[] = [];
        let where = "true";
        if (params.workflowName !== undefined) {
          values.push(params.workflowName);
          where += ` and r.name = $${String(values.length)}`;
        }
        where += window(params, "r.updated_at", values);
        values.push(limit + 1, offset);
        const data = await rows<AnalyticsAttributeKey>(
          `select k.key, count(*)::int as "runCount",
             ${utc("min(r.created_at)")} as "firstSeenAt",
             ${utc("max(r.updated_at)")} as "lastSeenAt"
           from workflow.workflow_runs r
           cross join lateral jsonb_object_keys(coalesce(r.attributes, '{}'::jsonb)) as k(key)
           where ${where}
           group by k.key order by k.key
           limit $${String(values.length - 1)} offset $${String(values.length)}`,
          values,
        );
        return paged(data, limit, offset);
      },
    },
    steps: {
      get: (runId, stepId) =>
        one<AnalyticsStep>(
          `select ${STEP_COLUMNS} from workflow.workflow_steps s where s.run_id = $1 and s.step_id = $2`,
          [runId, stepId],
          "step",
          stepId,
        ),
      async list(params) {
        const { limit, offset, order } = page(
          params.pagination,
          RUN_SCOPED_LIMIT,
        );
        const data = await rows<AnalyticsStep>(
          `select ${STEP_COLUMNS} from workflow.workflow_steps s where s.run_id = $1
           order by s.created_at ${order}, s.step_id ${order} limit $2 offset $3`,
          [params.runId, limit + 1, offset],
        );
        return paged(data, limit, offset);
      },
    },
    events: {
      get: (runId, eventId) =>
        one<AnalyticsEvent>(
          `select ${EVENT_COLUMNS} from workflow.workflow_events e
           join workflow.workflow_runs r on r.id = e.run_id
           where e.run_id = $1 and e.id = $2`,
          [runId, eventId],
          "event",
          eventId,
        ),
      getMany(runId, eventIds) {
        if (eventIds.length > LIMIT) {
          throw new RangeError(
            `better-supabase: analytics looks up at most ${String(LIMIT)} events at once`,
          );
        }
        return rows<AnalyticsEvent>(
          `select ${EVENT_COLUMNS} from workflow.workflow_events e
           join workflow.workflow_runs r on r.id = e.run_id
           where e.run_id = $1 and e.id = any($2::text[])`,
          [runId, [...new Set(eventIds)]],
        );
      },
      list: listEvents,
      // oxlint-disable-next-line typescript/no-deprecated -- the World interface still requires it until its next major.
      listByCorrelationId(params) {
        return listEvents({
          runId: params.runId,
          correlationId: params.correlationId,
          ...(params.pagination === undefined
            ? {}
            : { pagination: params.pagination }),
        });
      },
    },
    hooks: {
      get: (hookId, params) =>
        one<AnalyticsHook>(
          `${HOOKS} and e.correlation_id = $1 and ($2::text is null or e.run_id = $2)
           group by e.run_id, e.correlation_id`,
          [hookId, params?.runId ?? null],
          "hook",
          hookId,
        ),
      async list(params) {
        const { limit, offset, order } = page(params.pagination, LIMIT);
        const data = await rows<AnalyticsHook>(
          `${HOOKS} and e.run_id = $1 group by e.run_id, e.correlation_id
           order by "createdAt" ${order}, "hookId" ${order} limit $2 offset $3`,
          [params.runId, limit + 1, offset],
        );
        return paged(data, limit, offset);
      },
    },
    waits: {
      get: (runId, waitId) =>
        one<AnalyticsWait>(
          `select ${WAIT_COLUMNS} from workflow.workflow_waits w
           where w.run_id = $1 and w.wait_id in ($2::text, $1::text || '-' || $2::text)`,
          [runId, waitId],
          "wait",
          waitId,
        ),
      async list(params) {
        const { limit, offset, order } = page(
          params.pagination,
          RUN_SCOPED_LIMIT,
        );
        const values: unknown[] = [params.runId];
        let where = "w.run_id = $1";
        if (params.status !== undefined) {
          values.push(params.status);
          where += ` and w.status::text = $${String(values.length)}`;
        }
        values.push(limit + 1, offset);
        const data = await rows<AnalyticsWait>(
          `select ${WAIT_COLUMNS} from workflow.workflow_waits w where ${where}
           order by w.created_at ${order}, w.wait_id ${order}
           limit $${String(values.length - 1)} offset $${String(values.length)}`,
          values,
        );
        return paged(data, limit, offset);
      },
    },
  };
}
