import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";

/** What a provider looks up a company by. */
export interface CompanyLookup {
  readonly name: string;
  readonly domain?: string;
  readonly website?: string;
  readonly signal?: AbortSignal;
}

/** What a provider looks up a person by. */
export interface PersonLookup {
  readonly name: string;
  readonly email?: string;
  readonly phone?: string;
  /** The domain of the person's primary company, when it has one. */
  readonly companyDomain?: string;
  readonly signal?: AbortSignal;
}

/**
 * A company as a provider describes it. `domain` and `website` fill the
 * company's empty columns; everything is stored with the result.
 */
export interface CompanyProfile {
  readonly name?: string;
  readonly domain?: string;
  readonly website?: string;
  readonly industry?: string;
  readonly employees?: number;
  readonly foundedYear?: number;
  readonly country?: string;
  readonly city?: string;
  readonly linkedinUrl?: string;
  readonly description?: string;
}

/**
 * A person as a provider describes them. `title` and `phone` fill the person's
 * empty columns; everything is stored with the result.
 */
export interface PersonProfile {
  readonly title?: string;
  readonly phone?: string;
  readonly companyName?: string;
  readonly country?: string;
  readonly city?: string;
  readonly linkedinUrl?: string;
}

/**
 * Looks up companies and people. Versioned: a breaking change to this contract
 * ships a new `apiVersion`. A lookup without a match returns `undefined`;
 * errors are `DbError`s: `unauthorized` for a key the provider refuses,
 * `rate_limited` with `retryAfter`, `network` for an outage.
 */
export interface EnrichmentProvider {
  readonly apiVersion: 1;
  /** The name results are stored under, such as `peopledatalabs`. */
  readonly name: string;
  company(input: CompanyLookup): AsyncResult<CompanyProfile | undefined>;
  person(input: PersonLookup): AsyncResult<PersonProfile | undefined>;
}

/** Checks the provider's `apiVersion` and name before the block uses it. */
export function enrichmentProviderOf(
  provider: EnrichmentProvider,
): EnrichmentProvider {
  const version: unknown = provider.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `enrichment "${provider.name}" targets enrichment provider API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the provider for API 1.`,
    );
  }

  if (!/^[a-z][a-z0-9_-]{0,62}$/u.test(provider.name)) {
    throw new TypeError(
      `enrichment provider name "${provider.name}" must be lowercase letters, digits, "-" or "_"`,
    );
  }

  return provider;
}

/** The bare host of a website or domain: no scheme, `www.`, port or path. */
export function domainOf(value: string | undefined): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  const host = value
    .trim()
    .toLowerCase()
    .replace(/^[a-z][a-z0-9+.-]*:\/\//u, "")
    .replace(/^www\./u, "")
    .split(/[/:?#]/u)[0];

  return host !== undefined && /^[a-z0-9.-]+\.[a-z]{2,}$/u.test(host)
    ? host
    : undefined;
}

export interface PeopleDataLabsOptions {
  /** A People Data Labs API key. */
  readonly apiKey: string;
  /** Defaults to the global `fetch`. */
  readonly fetch?: typeof fetch;
  /** The API origin, for a proxy or a test server. */
  readonly baseUrl?: string;
  /** The lowest match likelihood (1 to 10) a person lookup accepts. Default: 6. */
  readonly minLikelihood?: number;
}

type Json = Readonly<Record<string, unknown>>;

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : undefined;

const count = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isFinite(value) ? value : undefined;

/** Leaves out the keys whose value is undefined, so results store as JSON. */
function defined<T extends object>(value: {
  readonly [K in keyof T]-?: T[K] | undefined;
}): T {
  // SAFETY: only keys whose optional value is undefined were removed.
  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  ) as T;
}

function companyProfile(body: Json): CompanyProfile {
  const location = isRecord(body["location"]) ? body["location"] : {};
  const website = text(body["website"]);

  return defined<CompanyProfile>({
    name: text(body["display_name"]) ?? text(body["name"]),
    domain: domainOf(website),
    website,
    industry: text(body["industry"]),
    employees: count(body["employee_count"]),
    foundedYear: count(body["founded"]),
    country: text(location["country"]),
    city: text(location["locality"]),
    linkedinUrl: text(body["linkedin_url"]),
    description: text(body["summary"]),
  });
}

function personProfile(data: Json): PersonProfile {
  return defined<PersonProfile>({
    title: text(data["job_title"]),
    phone: text(data["mobile_phone"]),
    companyName: text(data["job_company_name"]),
    country: text(data["location_country"]),
    city: text(data["location_locality"]),
    linkedinUrl: text(data["linkedin_url"]),
  });
}

async function httpError(
  provider: string,
  response: Response,
): Promise<Result<never>> {
  const body = await response.text().catch(() => "");
  const message = `${provider} answered ${String(response.status)}${body.length > 0 ? `: ${body.slice(0, 300)}` : ""}`;
  const retry = Number(response.headers.get("retry-after"));
  const retryAfter = Number.isFinite(retry) && retry > 0 ? retry : undefined;
  const retrying = retryAfter === undefined ? {} : { retryAfter };

  if (response.status === 401 || response.status === 403) {
    return err(
      dbError("unauthorized", message, { hint: "ENRICHMENT_KEY_REFUSED" }),
    );
  }

  if (response.status === 429) {
    return err(dbError("rate_limited", message, retrying));
  }

  return err(dbError("network", message, retrying));
}

/**
 * The People Data Labs company and person enrichment APIs (v5), over `fetch`. A
 * company is matched by its website or domain and name, a person by email, name
 * and company domain.
 */
export function peopleDataLabsEnrichment(
  options: PeopleDataLabsOptions,
): EnrichmentProvider {
  const run = options.fetch ?? fetch;
  const base = options.baseUrl ?? "https://api.peopledatalabs.com";
  const minLikelihood = options.minLikelihood ?? 6;

  const get = (
    path: string,
    query: Readonly<Record<string, string | undefined>>,
    signal: AbortSignal | undefined,
  ): AsyncResult<Json | undefined> =>
    AsyncResult.from(async () => {
      const params = new URLSearchParams();

      for (const [key, value] of Object.entries(query)) {
        if (value !== undefined) {
          params.set(key, value);
        }
      }

      const response = await run(`${base}${path}?${params.toString()}`, {
        method: "GET",
        headers: { accept: "application/json", "x-api-key": options.apiKey },
        ...(signal === undefined ? {} : { signal }),
      });

      if (response.status === 404) {
        return ok(undefined);
      }

      if (!response.ok) {
        return httpError("peopledatalabs", response);
      }

      const body: unknown = await response.json();

      return ok(isRecord(body) ? body : {});
    });

  return {
    apiVersion: 1,
    name: "peopledatalabs",
    company: (input) =>
      get(
        "/v5/company/enrich",
        {
          website: domainOf(input.domain) ?? domainOf(input.website),
          name: input.name,
        },
        input.signal,
      ).map((body) => (body === undefined ? undefined : companyProfile(body))),
    person: (input) =>
      get(
        "/v5/person/enrich",
        {
          email: input.email,
          phone: input.phone,
          name: input.name,
          company: input.companyDomain,
          min_likelihood: String(minLikelihood),
        },
        input.signal,
      ).map((body) =>
        body !== undefined && isRecord(body["data"])
          ? personProfile(body["data"])
          : undefined,
      ),
  };
}
