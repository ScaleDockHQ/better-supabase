import type { DbError } from "../core/errors.ts";

/** A bucket's object versioning state in Storage. */
export type VersioningStatus = "DISABLED" | "ENABLED" | "SUSPENDED";

/** One rule of a bucket lifecycle policy. Storage only expires noncurrent versions today. */
export interface BucketLifecycleRule {
  /** Storage generates one when you omit it. */
  readonly id?: string;
  /** Defaults to `Enabled`. `Disabled` keeps the rule stored but inactive. */
  readonly status?: "Enabled" | "Disabled";
  readonly noncurrentVersionExpiration: {
    /** How old a noncurrent version must be before it expires, in days (at least 1). */
    readonly noncurrentDays: number;
    /** Keep this many of the newest noncurrent versions regardless of age (1 to 100). */
    readonly newerNoncurrentVersions?: number;
  };
}

/** A bucket lifecycle policy: 1 to 1000 rules, applied by `bucket.apply()`. */
export interface BucketLifecycle {
  readonly rules: readonly [BucketLifecycleRule, ...BucketLifecycleRule[]];
}

/** The lifecycle payload Storage takes and stores in `storage.buckets.lifecycle_configuration`. */
export interface LifecyclePayload {
  rules: {
    id?: string;
    status: "Enabled" | "Disabled";
    filter: Record<string, never>;
    noncurrentVersionExpiration: {
      noncurrentDays: number;
      newerNoncurrentVersions?: number;
    };
  }[];
}

/** One version of an object, newest first in `versions()`. */
export interface ObjectVersion {
  readonly versionId: string;
  /** The version the path serves now. */
  readonly current: boolean;
  /** A delete marker hides the object without removing its versions. */
  readonly deleteMarker: boolean;
  readonly size?: number;
  readonly contentType?: string;
  readonly createdAt: string | null;
  /** When the version stopped being current. */
  readonly archivedAt: string | null;
}

const MAX_DAYS = 2_147_483_647;

function wholeIn(value: number, min: number, max: number): boolean {
  return Number.isInteger(value) && value >= min && value <= max;
}

/** Checks a lifecycle policy and fills Storage's defaults; throws a `TypeError` for one Storage would refuse. */
export function lifecyclePayload(
  id: string,
  lifecycle: BucketLifecycle,
): LifecyclePayload {
  const rules = lifecycle.rules;
  if (rules.length === 0 || rules.length > 1000)
    throw new TypeError(
      `defineBucket("${id}"): lifecycle needs 1 to 1000 rules`,
    );
  const ids = rules.flatMap((rule) => (rule.id === undefined ? [] : [rule.id]));
  if (new Set(ids).size !== ids.length)
    throw new TypeError(`defineBucket("${id}"): lifecycle rule ids repeat`);
  return {
    rules: rules.map((rule) => {
      const { noncurrentDays, newerNoncurrentVersions } =
        rule.noncurrentVersionExpiration;
      if (!wholeIn(noncurrentDays, 1, MAX_DAYS))
        throw new TypeError(
          `defineBucket("${id}"): noncurrentDays must be a whole number of days, at least 1`,
        );
      if (
        newerNoncurrentVersions !== undefined &&
        !wholeIn(newerNoncurrentVersions, 1, 100)
      )
        throw new TypeError(
          `defineBucket("${id}"): newerNoncurrentVersions must be 1 to 100`,
        );
      return {
        ...(rule.id === undefined ? {} : { id: rule.id }),
        status: rule.status ?? "Enabled",
        filter: {},
        noncurrentVersionExpiration: {
          noncurrentDays,
          ...(newerNoncurrentVersions === undefined
            ? {}
            : { newerNoncurrentVersions }),
        },
      };
    }),
  };
}

function ruleKey(rule: unknown): string {
  if (typeof rule !== "object" || rule === null) return JSON.stringify(rule);
  // SAFETY: rule is an object; every field read below is checked or stringified.
  const entry = rule as {
    status?: unknown;
    noncurrentVersionExpiration?: {
      noncurrentDays?: unknown;
      newerNoncurrentVersions?: unknown;
    };
  };
  const expiration = entry.noncurrentVersionExpiration ?? {};
  return JSON.stringify([
    entry.status ?? "Enabled",
    expiration.noncurrentDays,
    expiration.newerNoncurrentVersions ?? null,
  ]);
}

/**
 * Whether a stored `lifecycle_configuration` matches the expected payload.
 * Generated rule ids are ignored; the rules compare as a set.
 */
export function sameLifecycle(
  expected: LifecyclePayload | undefined,
  actual: unknown,
): boolean {
  const stored: readonly unknown[] =
    typeof actual === "object" &&
    actual !== null &&
    "rules" in actual &&
    Array.isArray(actual.rules)
      ? actual.rules
      : [];
  const want = (expected?.rules ?? []).map(ruleKey).sort();
  const have = stored.map(ruleKey).sort();
  return want.length === have.length && want.every((key, i) => key === have[i]);
}

/** Storage codes for a lifecycle that is absent or a feature the project doesn't have. */
export function lifecycleAbsent(error: DbError): boolean {
  return (
    error.code === "NoSuchLifecycleConfiguration" ||
    error.kind === "unsupported"
  );
}

interface ListedVersion {
  readonly version?: string | null;
  readonly archived_at?: string | null;
  readonly is_delete_marker?: boolean | null;
  readonly created_at?: string | null;
  readonly metadata?: Readonly<Record<string, unknown>> | null;
}

export function toVersion(item: ListedVersion): ObjectVersion | undefined {
  if (!item.version) return undefined;
  const metadata = item.metadata ?? {};
  const size = metadata["size"];
  const type = metadata["mimetype"];
  return {
    versionId: item.version,
    current: !item.archived_at,
    deleteMarker: item.is_delete_marker === true,
    ...(typeof size === "number" ? { size } : {}),
    ...(typeof type === "string" ? { contentType: type } : {}),
    createdAt: item.created_at ?? null,
    archivedAt: item.archived_at ?? null,
  };
}
