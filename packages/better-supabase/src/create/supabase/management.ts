import type { Reader } from "./guards.ts";

import { arrayOf, isRecord } from "./guards.ts";
import { SUPABASE_API } from "./oauth.ts";

export const SMART_REGIONS = ["americas", "emea", "apac"] as const;

export type SmartRegion = (typeof SMART_REGIONS)[number];

/** A Supabase project ref: lowercase letters and digits, never a path. */
export function isProjectRef(value: string): boolean {
  return /^[a-z0-9]{1,64}$/u.test(value);
}

export interface SupabaseOrganization {
  readonly id: string;
  readonly slug: string;
  readonly name: string;
}

export interface SupabaseProject {
  readonly ref: string;
  readonly name: string;
  readonly organization_slug: string;
  readonly region: string;
  readonly status: string;
}

export interface SupabaseLint {
  readonly name: string;
  readonly title: string;
  readonly level: "ERROR" | "WARN" | "INFO";
  readonly detail?: string | undefined;
  readonly remediation?: string | undefined;
}

function text(
  record: Record<string, unknown>,
  key: string,
): string | undefined {
  const value = record[key];

  return typeof value === "string" ? value : undefined;
}

const readOrganization: Reader<SupabaseOrganization> = (value) => {
  if (!isRecord(value)) {
    return;
  }

  const id = text(value, "id");
  const slug = text(value, "slug");
  const name = text(value, "name");

  return id === undefined || slug === undefined || name === undefined
    ? undefined
    : { id, slug, name };
};

const readProject: Reader<SupabaseProject> = (value) => {
  if (!isRecord(value)) {
    return;
  }

  const ref = text(value, "ref");
  const name = text(value, "name");
  const organization_slug = text(value, "organization_slug");
  const region = text(value, "region");
  const status = text(value, "status");

  return ref === undefined ||
    name === undefined ||
    organization_slug === undefined ||
    region === undefined ||
    status === undefined
    ? undefined
    : { ref, name, organization_slug, region, status };
};

const readHealthy: Reader<boolean> = (value) =>
  Array.isArray(value)
    ? value.some(
        (service) =>
          isRecord(service) &&
          service["name"] === "db" &&
          service["healthy"] === true,
      )
    : undefined;

const readLint: Reader<SupabaseLint> = (value) => {
  if (!isRecord(value)) {
    return;
  }

  const name = text(value, "name");
  const title = text(value, "title");
  const level = value["level"];

  if (
    name === undefined ||
    title === undefined ||
    (level !== "ERROR" && level !== "WARN" && level !== "INFO")
  ) {
    return;
  }

  return {
    name,
    title,
    level,
    detail: text(value, "detail"),
    remediation: text(value, "remediation"),
  };
};

const readLints: Reader<SupabaseLint[]> = (value) =>
  isRecord(value) ? arrayOf(readLint)(value["lints"]) : undefined;

const readTableCount: Reader<number> = (value) => {
  if (!Array.isArray(value)) {
    return;
  }

  const first: unknown = value[0];

  if (first === undefined) {
    return 0;
  }

  if (!isRecord(first)) {
    return;
  }

  const count = Number(first["count"]);

  return Number.isNaN(count) ? undefined : count;
};

const readAny: Reader<true> = () => true;

/**
 * A Management API call that failed; `status` is the HTTP status, 0 for a bad
 * response.
 */
export class ManagementError extends Error {
  override readonly name = "ManagementError";
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

/** The Management API calls the deploy flow makes. */
export interface ManagementClient {
  organizations(): Promise<SupabaseOrganization[]>;
  projects(): Promise<SupabaseProject[]>;
  createProject(input: {
    name: string;
    organizationSlug: string;
    region: SmartRegion;
    dbPass: string;
  }): Promise<SupabaseProject>;
  project(ref: string): Promise<SupabaseProject>;
  databaseHealthy(ref: string): Promise<boolean>;
  publicTableCount(ref: string): Promise<number>;
  applyMigration(ref: string, name: string, query: string): Promise<void>;
  securityLints(ref: string): Promise<readonly SupabaseLint[]>;
}

const PUBLIC_TABLES = `select count(*) as count
from pg_catalog.pg_tables
where schemaname = 'public'`;

/**
 * The Management API calls the deploy dialog makes, with the user's OAuth
 * access token. Responses are parsed, and every failure is a
 * `ManagementError`.
 */
export function managementClient(
  accessToken: string,
  fetchImpl: typeof fetch = fetch,
): ManagementClient {
  async function call<TValue>(
    path: string,
    read: Reader<TValue>,
    init: { method?: string; body?: unknown } = {},
  ): Promise<TValue> {
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
      const message = isRecord(json) ? text(json, "message") : undefined;

      throw new ManagementError(
        message ?? `Supabase answered ${String(response.status)}.`,
        response.status,
      );
    }

    const parsed = read(json);

    if (parsed === undefined) {
      throw new ManagementError(
        `Supabase sent an unexpected response for ${path}.`,
        0,
      );
    }

    return parsed;
  }

  return {
    organizations: () => call("/v1/organizations", arrayOf(readOrganization)),

    projects: () => call("/v1/projects", arrayOf(readProject)),

    createProject: (input: {
      name: string;
      organizationSlug: string;
      region: SmartRegion;
      dbPass: string;
    }) =>
      call("/v1/projects", readProject, {
        method: "POST",
        body: {
          name: input.name,
          organization_slug: input.organizationSlug,
          db_pass: input.dbPass,
          region_selection: { type: "smartGroup", code: input.region },
        },
      }),

    project: (ref: string) =>
      call(`/v1/projects/${encodeURIComponent(ref)}`, readProject),

    databaseHealthy: async (ref: string): Promise<boolean> =>
      call(
        `/v1/projects/${encodeURIComponent(ref)}/health?services=db`,
        readHealthy,
      ),

    publicTableCount: async (ref: string): Promise<number> =>
      call(
        `/v1/projects/${encodeURIComponent(ref)}/database/query/read-only`,
        readTableCount,
        { method: "POST", body: { query: PUBLIC_TABLES } },
      ),

    applyMigration: async (
      ref: string,
      name: string,
      query: string,
    ): Promise<void> => {
      await call(
        `/v1/projects/${encodeURIComponent(ref)}/database/migrations`,
        readAny,
        { method: "POST", body: { name, query } },
      );
    },

    securityLints: async (ref: string): Promise<readonly SupabaseLint[]> =>
      call(
        `/v1/projects/${encodeURIComponent(ref)}/advisors/security`,
        readLints,
      ),
  };
}
