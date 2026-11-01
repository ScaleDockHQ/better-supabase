import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";

/** A vulnerability as OSV describes it, reduced to what the block stores. */
export interface OsvRecord {
  /** The record's id, such as `GHSA-xxxx-xxxx-xxxx` or `CVE-2026-1234`. */
  readonly id: string;
  readonly aliases: readonly string[];
  readonly summary: string | undefined;
  readonly details: string | undefined;
  /** RFC 3339 timestamps, as OSV wrote them. */
  readonly published: string | undefined;
  readonly modified: string | undefined;
  /** CVSS vectors from `severity`, keyed by OSV type (`CVSS_V3`, `CVSS_V4`). */
  readonly severity: readonly {
    readonly type: string;
    readonly score: string;
  }[];
  /** The rating the source database gives, such as `HIGH`, when it has one. */
  readonly databaseSeverity: string | undefined;
  /** Package URLs without a version of the packages the record affects. */
  readonly affectedPurls: readonly string[];
  readonly references: readonly {
    readonly type: string;
    readonly url: string;
  }[];
}

/** One day's EPSS score for a CVE. */
export interface EpssScore {
  /** The probability of exploitation in the next 30 days, 0 to 1. */
  readonly score: number;
  /** The share of scored CVEs with a lower score, 0 to 1. */
  readonly percentile: number;
  /** The day the score is for, `YYYY-MM-DD`. */
  readonly date: string;
}

/** An entry of the CISA Known Exploited Vulnerabilities catalog. */
export interface KevEntry {
  readonly cveId: string;
  /** `YYYY-MM-DD`. */
  readonly dateAdded: string;
  /** `YYYY-MM-DD`, the remediation due date the entry carries. */
  readonly dueDate: string | undefined;
  readonly knownRansomwareUse: boolean;
  readonly requiredAction: string | undefined;
}

/** What a feed call takes besides its subject. */
export interface FeedCallOptions {
  readonly signal?: AbortSignal;
}

/**
 * Looks vulnerabilities up in OSV, EPSS and the CISA KEV catalog. Versioned: a
 * breaking change to this contract ships a new `apiVersion`. `osv` answers
 * `undefined` for an id the source does not know. Errors are `DbError`s:
 * `rate_limited` with `retryAfter`, `network` for an outage.
 */
export interface VulnerabilityFeed {
  readonly apiVersion: 1;
  /** The name the enrichment is attributed to, such as `public`. */
  readonly name: string;
  osv(
    id: string,
    options?: FeedCallOptions,
  ): AsyncResult<OsvRecord | undefined>;
  /** Scores for the CVE ids it knows; the others are left out. */
  epss(
    cveIds: readonly string[],
    options?: FeedCallOptions,
  ): AsyncResult<Readonly<Record<string, EpssScore>>>;
  /** The whole catalog, by CVE id. */
  kev(
    options?: FeedCallOptions,
  ): AsyncResult<Readonly<Record<string, KevEntry>>>;
}

/** Checks the feed's `apiVersion` and name before the block uses it. */
export function vulnerabilityFeedOf(
  feed: VulnerabilityFeed,
): VulnerabilityFeed {
  const version: unknown = feed.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `advisories feed "${feed.name}" targets vulnerability feed API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the feed for API 1.`,
    );
  }

  if (!/^[a-z][a-z0-9_-]{0,62}$/u.test(feed.name)) {
    throw new TypeError(
      `advisories feed name "${feed.name}" must be lowercase letters, digits, "-" or "_"`,
    );
  }

  return feed;
}

export interface PublicVulnerabilityFeedOptions {
  /** Defaults to the global `fetch`. */
  readonly fetch?: typeof fetch;
  /** The OSV API origin. Default: `https://api.osv.dev`. */
  readonly osvUrl?: string;
  /** The FIRST EPSS API origin. Default: `https://api.first.org`. */
  readonly epssUrl?: string;
  /** The KEV catalog JSON. Default: the CISA feed. */
  readonly kevUrl?: string;
}

const KEV_URL =
  "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json";

const CVE_ID = /^CVE-\d{4}-\d{4,}$/u;

/** Whether `value` is a CVE id. */
export const isCveId = (value: string): boolean => CVE_ID.test(value);

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : undefined;

const PURL_TYPES: Readonly<Record<string, string>> = {
  npm: "npm",
  PyPI: "pypi",
  Go: "golang",
  "crates.io": "cargo",
  Maven: "maven",
  RubyGems: "gem",
  NuGet: "nuget",
  Packagist: "composer",
  Hex: "hex",
  Pub: "pub",
  SwiftURL: "swift",
};

/** A package URL (without a version) for an OSV `package` object. */
function purlOf(pack: Record<string, unknown>): string | undefined {
  const purl = text(pack["purl"]);

  if (purl !== undefined) {
    return purl.split("@")[0]?.split("?")[0];
  }

  const ecosystem = text(pack["ecosystem"])?.split(":")[0];
  const name = text(pack["name"]);
  const type = ecosystem === undefined ? undefined : PURL_TYPES[ecosystem];

  if (type === undefined || name === undefined) {
    return undefined;
  }

  const path =
    type === "maven"
      ? name.split(":").map(encodeURIComponent).join("/")
      : name.split("/").map(encodeURIComponent).join("/");

  return `pkg:${type}/${path}`;
}

function stringsOf(value: unknown): readonly string[] {
  return Array.isArray(value)
    ? value.flatMap((entry) => {
        const found = text(entry);

        return found === undefined ? [] : [found];
      })
    : [];
}

/** Reduces an OSV JSON record to an `OsvRecord`; `undefined` without an id. */
export function osvRecordOf(body: unknown): OsvRecord | undefined {
  if (!isRecord(body)) {
    return undefined;
  }

  const id = text(body["id"]);

  if (id === undefined) {
    return undefined;
  }

  const severity = Array.isArray(body["severity"])
    ? body["severity"].flatMap((entry) => {
        if (!isRecord(entry)) {
          return [];
        }

        const type = text(entry["type"]);
        const score = text(entry["score"]);

        return type === undefined || score === undefined
          ? []
          : [{ type, score }];
      })
    : [];

  const purls = new Set<string>();

  if (Array.isArray(body["affected"])) {
    for (const entry of body["affected"]) {
      const pack = isRecord(entry) ? entry["package"] : undefined;
      const purl = isRecord(pack) ? purlOf(pack) : undefined;

      if (purl !== undefined) {
        purls.add(purl);
      }
    }
  }

  const references = Array.isArray(body["references"])
    ? body["references"].flatMap((entry) => {
        if (!isRecord(entry)) {
          return [];
        }

        const url = text(entry["url"]);

        return url === undefined
          ? []
          : [{ type: text(entry["type"]) ?? "WEB", url }];
      })
    : [];

  const database = body["database_specific"];

  return {
    id,
    aliases: stringsOf(body["aliases"]),
    summary: text(body["summary"]),
    details: text(body["details"]),
    published: text(body["published"]),
    modified: text(body["modified"]),
    severity,
    databaseSeverity: isRecord(database)
      ? text(database["severity"])
      : undefined,
    affectedPurls: [...purls],
    references,
  };
}

async function httpError(
  source: string,
  response: Response,
): Promise<Result<never>> {
  const body = await response.text().catch(() => "");
  const message = `${source} answered ${String(response.status)}${body.length > 0 ? `: ${body.slice(0, 300)}` : ""}`;
  const retry = Number(response.headers.get("retry-after"));

  const retrying =
    Number.isFinite(retry) && retry > 0 ? { retryAfter: retry } : {};

  return err(
    dbError(
      response.status === 429 ? "rate_limited" : "network",
      message,
      retrying,
    ),
  );
}

const number = (value: unknown): number | undefined => {
  const parsed = typeof value === "string" ? Number(value) : value;

  return typeof parsed === "number" && Number.isFinite(parsed)
    ? parsed
    : undefined;
};

/**
 * OSV (`api.osv.dev`), FIRST EPSS (`api.first.org`) and the CISA KEV catalog,
 * over `fetch`. None of them needs a key. Point the URLs at a mirror or a test
 * server when the app runs behind a proxy.
 */
export function publicVulnerabilityFeed(
  options: PublicVulnerabilityFeedOptions = {},
): VulnerabilityFeed {
  const run = options.fetch ?? fetch;
  const osvUrl = options.osvUrl ?? "https://api.osv.dev";
  const epssUrl = options.epssUrl ?? "https://api.first.org";
  const kevUrl = options.kevUrl ?? KEV_URL;

  const get = (
    source: string,
    url: string,
    signal: AbortSignal | undefined,
  ): AsyncResult<unknown> =>
    AsyncResult.from(async () => {
      let response: Response;

      try {
        response = await run(url, {
          method: "GET",
          headers: { accept: "application/json" },
          ...(signal === undefined ? {} : { signal }),
        });
      } catch (cause) {
        if (signal?.aborted === true) {
          throw cause;
        }

        return err(
          dbError(
            "network",
            `${source} could not be reached: ${cause instanceof Error ? cause.message : String(cause)}`,
          ),
        );
      }

      if (response.status === 404) {
        return ok(undefined);
      }

      if (!response.ok) {
        return httpError(source, response);
      }

      return ok(await response.json());
    });

  return {
    apiVersion: 1,
    name: "public",
    osv: (id, call = {}) =>
      get(
        "osv",
        `${osvUrl}/v1/vulns/${encodeURIComponent(id)}`,
        call.signal,
      ).map(osvRecordOf),
    epss: (cveIds, call = {}) => {
      const ids = cveIds.filter(isCveId);

      if (ids.length === 0) {
        return AsyncResult.from(() => Promise.resolve(ok({})));
      }

      return get(
        "epss",
        `${epssUrl}/data/v1/epss?cve=${ids.map(encodeURIComponent).join(",")}`,
        call.signal,
      ).map((body) => {
        const scores: Record<string, EpssScore> = {};

        const rows =
          isRecord(body) && Array.isArray(body["data"]) ? body["data"] : [];

        for (const row of rows) {
          if (!isRecord(row)) {
            continue;
          }

          const cve = text(row["cve"]);
          const score = number(row["epss"]);
          const percentile = number(row["percentile"]);
          const date = text(row["date"]);

          if (
            cve !== undefined &&
            score !== undefined &&
            percentile !== undefined &&
            date !== undefined
          ) {
            scores[cve] = { score, percentile, date };
          }
        }

        return scores;
      });
    },
    kev: (call = {}) =>
      get("kev", kevUrl, call.signal).map((body) => {
        const entries: Record<string, KevEntry> = {};

        const rows =
          isRecord(body) && Array.isArray(body["vulnerabilities"])
            ? body["vulnerabilities"]
            : [];

        for (const row of rows) {
          if (!isRecord(row)) {
            continue;
          }

          const cveId = text(row["cveID"]);
          const dateAdded = text(row["dateAdded"]);

          if (cveId !== undefined && dateAdded !== undefined) {
            entries[cveId] = {
              cveId,
              dateAdded,
              dueDate: text(row["dueDate"]),
              knownRansomwareUse: row["knownRansomwareCampaignUse"] === "Known",
              requiredAction: text(row["requiredAction"]),
            };
          }
        }

        return entries;
      }),
  };
}
