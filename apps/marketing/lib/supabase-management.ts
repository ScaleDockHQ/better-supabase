import * as v from "valibot";

import { SUPABASE_API } from "./supabase-oauth";

export const SMART_REGIONS = ["americas", "emea", "apac"] as const;

export type SmartRegion = (typeof SMART_REGIONS)[number];

/** A Supabase project ref: lowercase letters and digits, never a path. */
export function isProjectRef(value: string): boolean {
  return /^[a-z0-9]{1,64}$/u.test(value);
}

const organization = v.object({
  id: v.string(),
  slug: v.string(),
  name: v.string(),
});

const project = v.object({
  ref: v.string(),
  name: v.string(),
  organization_slug: v.string(),
  region: v.string(),
  status: v.string(),
});

const serviceHealth = v.object({
  name: v.string(),
  healthy: v.boolean(),
  status: v.string(),
});

const lint = v.object({
  name: v.string(),
  title: v.string(),
  level: v.picklist(["ERROR", "WARN", "INFO"]),
  detail: v.optional(v.string()),
  remediation: v.optional(v.string()),
});

const tableCount = v.array(
  v.object({ count: v.union([v.number(), v.string()]) }),
);

const errorBody = v.object({ message: v.string() });

export type SupabaseOrganization = v.InferOutput<typeof organization>;

export type SupabaseProject = v.InferOutput<typeof project>;

export type SupabaseLint = v.InferOutput<typeof lint>;

/** A Management API call that failed; `status` is the HTTP status, 0 for a bad response. */
export class ManagementError extends Error {
  override readonly name = "ManagementError";
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

const PUBLIC_TABLES = `select count(*) as count
from pg_catalog.pg_tables
where schemaname = 'public'`;

/**
 * The Management API calls the deploy dialog makes, with the user's OAuth
 * access token. Responses are parsed, and every failure is a `ManagementError`.
 */
export function managementClient(
  accessToken: string,
  fetchImpl: typeof fetch = fetch,
) {
  async function call<const TSchema extends v.GenericSchema<unknown, unknown>>(
    path: string,
    schema: TSchema,
    init: { method?: string; body?: unknown } = {},
  ): Promise<v.InferOutput<TSchema>> {
    const response = await fetchImpl(new URL(path, SUPABASE_API), {
      method: init.method ?? "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: init.body === undefined ? null : JSON.stringify(init.body),
    });

    // An empty or non-JSON body (a proxy error page) reads as `null`.
    const json: unknown = await response.json().catch(() => null);

    if (!response.ok) {
      const detail = v.safeParse(errorBody, json);

      throw new ManagementError(
        detail.success
          ? detail.output.message
          : `Supabase answered ${String(response.status)}.`,
        response.status,
      );
    }

    const parsed = v.safeParse(schema, json);

    if (!parsed.success) {
      throw new ManagementError(
        `Supabase sent an unexpected response for ${path}.`,
        0,
      );
    }

    return parsed.output;
  }

  return {
    organizations: () => call("/v1/organizations", v.array(organization)),

    projects: () => call("/v1/projects", v.array(project)),

    createProject: (input: {
      name: string;
      organizationSlug: string;
      region: SmartRegion;
      dbPass: string;
    }) =>
      call("/v1/projects", project, {
        method: "POST",
        body: {
          name: input.name,
          organization_slug: input.organizationSlug,
          db_pass: input.dbPass,
          region_selection: { type: "smartGroup", code: input.region },
        },
      }),

    project: (ref: string) =>
      call(`/v1/projects/${encodeURIComponent(ref)}`, project),

    databaseHealthy: async (ref: string): Promise<boolean> => {
      const services = await call(
        `/v1/projects/${encodeURIComponent(ref)}/health?services=db`,
        v.array(serviceHealth),
      );

      return services.some(
        (service) => service.name === "db" && service.healthy,
      );
    },

    publicTableCount: async (ref: string): Promise<number> => {
      const rows = await call(
        `/v1/projects/${encodeURIComponent(ref)}/database/query/read-only`,
        tableCount,
        { method: "POST", body: { query: PUBLIC_TABLES } },
      );

      return Number(rows[0]?.count ?? 0);
    },

    applyMigration: async (
      ref: string,
      name: string,
      query: string,
    ): Promise<void> => {
      await call(
        `/v1/projects/${encodeURIComponent(ref)}/database/migrations`,
        v.unknown(),
        { method: "POST", body: { name, query } },
      );
    },

    securityLints: async (ref: string): Promise<readonly SupabaseLint[]> => {
      const body = await call(
        `/v1/projects/${encodeURIComponent(ref)}/advisors/security`,
        v.object({ lints: v.array(lint) }),
      );

      return body.lints;
    },
  };
}

export type ManagementClient = ReturnType<typeof managementClient>;
