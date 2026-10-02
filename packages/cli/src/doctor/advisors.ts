import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import type { Queryable } from "../introspect/source.ts";

/**
 * splinter (https://github.com/supabase/splinter), the linter behind the
 * dashboard's Security and Performance Advisors. It has no license, so it is
 * downloaded at this commit and checked against the hash instead of bundled.
 */
const SPLINTER_COMMIT = "e74a9e36cb12258cb67d1464bc1cb196e9cd8446";
const SPLINTER_SHA256 =
  "d8d558baad3e03832e521c527907fa50a9a172fabd899dd0f5c2504a5a0e9349";
const SPLINTER_URL: string = `https://raw.githubusercontent.com/supabase/splinter/${SPLINTER_COMMIT}/splinter.sql`;

export type AdvisorCategory = "security" | "performance";

/** One advisor result, as returned by splinter and the Management API. */
export interface Lint {
  readonly name: string;
  readonly title: string;
  readonly level: "ERROR" | "WARN" | "INFO";
  readonly facing: string;
  readonly categories: readonly string[];
  readonly description: string;
  readonly detail: string;
  readonly remediation: string;
  readonly metadata: Readonly<Record<string, unknown>> | null;
  readonly cache_key: string;
}

export interface AdvisorSource {
  /** Where the lints come from, for messages. */
  readonly describe: string;
  lints(category: AdvisorCategory): Promise<readonly Lint[]>;
}

type Fetch = typeof fetch;

function isLint(value: unknown): value is Lint {
  // SAFETY: every field is checked below before value counts as a Lint.
  const lint = value as Partial<Lint> | null;
  return (
    typeof lint === "object" &&
    lint !== null &&
    typeof lint.name === "string" &&
    typeof lint.level === "string" &&
    Array.isArray(lint.categories)
  );
}

export interface ManagementAdvisorOptions {
  readonly projectRef: string;
  readonly accessToken: string;
  readonly apiUrl?: string;
  readonly fetch?: Fetch;
}

/** The hosted project's advisors (`GET /v1/projects/{ref}/advisors/{category}`). */
export function managementAdvisors(
  options: ManagementAdvisorOptions,
): AdvisorSource {
  const base = (options.apiUrl ?? "https://api.supabase.com").replace(
    /\/$/,
    "",
  );
  const doFetch = options.fetch ?? fetch;
  return {
    describe: `project ${options.projectRef} advisors (Management API)`,
    async lints(category) {
      const url = `${base}/v1/projects/${encodeURIComponent(options.projectRef)}/advisors/${category}`;
      const response = await doFetch(url, {
        headers: { authorization: `Bearer ${options.accessToken}` },
      });
      const text = await response.text();
      if (!response.ok) {
        throw new Error(
          `Management API ${category} advisors failed (${response.status}): ${text.slice(0, 300)}`,
        );
      }
      // SAFETY: JSON.parse returns any, and lints is checked below.
      const body = JSON.parse(text) as { lints?: unknown };
      if (!Array.isArray(body.lints)) {
        throw new TypeError(
          `Management API ${category} advisors returned no "lints".`,
        );
      }
      return body.lints.filter(isLint);
    },
  };
}

export interface SplinterOptions {
  /** Directory for the downloaded `splinter.sql`. */
  readonly cacheDir: string;
  readonly fetch?: Fetch;
}

const sha256 = (text: string): string =>
  createHash("sha256").update(text).digest("hex");

/** Downloads (once) and verifies the pinned `splinter.sql`. */
async function splinterSql(options: SplinterOptions): Promise<string> {
  const file = resolve(options.cacheDir, `splinter-${SPLINTER_COMMIT}.sql`);
  if (existsSync(file)) {
    const cached = await readFile(file, "utf8");
    if (sha256(cached) === SPLINTER_SHA256) return cached;
  }
  const response = await (options.fetch ?? fetch)(SPLINTER_URL);
  if (!response.ok) {
    throw new Error(
      `Downloading splinter.sql failed (${response.status}) from ${SPLINTER_URL}`,
    );
  }
  const text = await response.text();
  if (sha256(text) !== SPLINTER_SHA256) {
    throw new Error(
      `splinter.sql from ${SPLINTER_URL} does not match the pinned hash; refusing to run it.`,
    );
  }
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, text);
  return text;
}

interface QueryResultLike {
  readonly rows?: readonly unknown[];
  readonly fields?: readonly { readonly name: string }[];
}

/** `pg` returns one result per statement for a multi-statement query. */
function lintRows(result: unknown): readonly unknown[] {
  // SAFETY: pg returns one result object, or one per statement for a multi-statement query.
  const results = (
    Array.isArray(result) ? result : [result]
  ) as QueryResultLike[];
  const match = results.find((entry) =>
    entry.fields?.some((field) => field.name === "cache_key"),
  );
  return match?.rows ?? results.at(-1)?.rows ?? [];
}

/**
 * Runs splinter against a database (local stack or `--db-url`) in a
 * read-only transaction that is rolled back.
 */
export function splinterAdvisors(
  queryable: Queryable,
  describe: string,
  options: SplinterOptions,
): AdvisorSource {
  let all: Promise<readonly Lint[]> | undefined;
  const run = async (): Promise<readonly Lint[]> => {
    const sql = await splinterSql(options);
    const result: unknown = await queryable.query(
      `begin read only;\n${sql}\n;\nrollback;`,
    );
    return lintRows(result).filter(isLint);
  };
  return {
    describe: `${describe} (splinter ${SPLINTER_COMMIT.slice(0, 7)})`,
    async lints(category) {
      all ??= run();
      const wanted = category.toUpperCase();
      return (await all).filter((lint) => lint.categories.includes(wanted));
    },
  };
}
