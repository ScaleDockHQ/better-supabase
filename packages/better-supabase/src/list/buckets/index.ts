import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";

/** The units the `@bsb buckets` function groups by. */
export type BucketUnit = "hour" | "day" | "week" | "month" | "quarter" | "year";

/** The arguments of the function the `@bsb buckets` tag renders. */
export interface DateBucketArgs {
  readonly unit: BucketUnit;
  readonly tz: string;
  readonly from_at: string | null;
  readonly to_at: string | null;
  readonly equals: Readonly<Record<string, readonly string[]>>;
}

/** The rows of one bucket: its start in the requested time zone, as ISO text. */
export interface DateBucket {
  readonly start: string;
  readonly count: number;
}

/** The facets of a list definition, as `list.facets` returns them. */
interface BucketFacet {
  readonly key: string;
  readonly column: string;
  readonly relation?: unknown;
}

export interface ListDateBucketsOptions {
  /**
   * Calls the rendered function, for example `(args) =>
   * db.$rpc("orders_date_buckets", args)`.
   */
  readonly rpc: (args: DateBucketArgs) => PromiseLike<Result<unknown>>;
  readonly unit: BucketUnit;
  /** IANA time zone the buckets start in. Default `UTC`. */
  readonly timeZone?: string;
  /** Rows at or after this instant. */
  readonly from?: string | Date;
  /** Rows before this instant. */
  readonly to?: string | Date;
  /**
   * The list's facets and the query whose facet values narrow the buckets. A
   * facet column must be in the tag's `filter` list. Facets on a related table
   * and the `__unset__` value are refused: the function filters its own columns
   * by value.
   */
  readonly list?: {
    readonly facets: readonly BucketFacet[];
    readonly query: {
      readonly facets: Readonly<Record<string, readonly string[] | undefined>>;
    };
  };
}

const UNSET = "__unset__";

const iso = (value: string | Date | undefined): string | null =>
  value === undefined
    ? null
    : typeof value === "string"
      ? value
      : value.toISOString();

function isBucket(value: unknown): value is { bucket: string; count: number } {
  return (
    typeof value === "object" &&
    value !== null &&
    "bucket" in value &&
    typeof value.bucket === "string" &&
    "count" in value &&
    typeof value.count === "number"
  );
}

/**
 * Counts the rows of a table per date bucket through the function the `@bsb
 * buckets` tag renders (ADR 0672), for a chart above a list. The filters of a
 * list narrow the count by facet value; its search text and filter tree do not
 * reach the function.
 */
export function listDateBuckets(
  options: ListDateBucketsOptions,
): AsyncResult<readonly DateBucket[]> {
  const equals: Record<string, readonly string[]> = {};

  for (const facet of options.list?.facets ?? []) {
    const values = options.list?.query.facets[facet.key];

    if (!values || values.length === 0) {
      continue;
    }

    if (facet.relation !== undefined || values.includes(UNSET)) {
      return AsyncResult.from<readonly DateBucket[]>(() =>
        Promise.resolve(
          err(
            dbError(
              "invalid_request",
              `The facet "${facet.key}" filters a related table or empty values, which date buckets cannot narrow by.`,
            ),
          ),
        ),
      );
    }

    equals[facet.column] = values;
  }

  return AsyncResult.from<readonly DateBucket[]>(async () => {
    const result = await options.rpc({
      unit: options.unit,
      tz: options.timeZone ?? "UTC",
      from_at: iso(options.from),
      to_at: iso(options.to),
      equals,
    });

    if (!result.ok) {
      return err(result.error);
    }

    const rows: unknown = result.data;

    if (!Array.isArray(rows) || !rows.every(isBucket)) {
      return err(
        dbError("unexpected", "The date bucket function returned no buckets."),
      );
    }

    return ok(rows.map((row) => ({ start: row.bucket, count: row.count })));
  });
}
