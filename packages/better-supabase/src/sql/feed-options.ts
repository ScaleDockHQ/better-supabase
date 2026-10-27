import type { BlockSqlContext } from "./context.ts";

import { isRecord } from "../core/guards.ts";

/** `blocks.<name>.options.feed`: how a share-link feed reads. */
export interface FeedOptions {
  /**
   * `access`: what the link's creator may read. `public`: events that aren't
   * private, plus the creator's own private ones.
   */
  readonly visibility: "access" | "public";
  /** Days back a finished item still shows. */
  readonly pastDays: number;
  /** Days ahead an item may start, or `undefined` for no bound. */
  readonly futureDays: number | undefined;
  /** The most items one fetch returns. */
  readonly limit: number;
  /** A new link revokes the creator's earlier live links to the same record. */
  readonly single: boolean;
}

const whole = (value: unknown, min: number, max: number): value is number =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value >= min &&
  value <= max;

/** The `feed` option of a block whose share links serve a feed. */
export function feedOptions(ctx: BlockSqlContext, where: string): FeedOptions {
  const raw = ctx.option("feed") ?? {};

  if (!isRecord(raw)) {
    throw new TypeError(
      `${where}.feed takes { visibility, pastDays, futureDays, limit, single }`,
    );
  }

  const {
    visibility = "access",
    pastDays = 366,
    futureDays,
    limit = 5000,
    single = true,
  } = raw;

  if (visibility !== "access" && visibility !== "public") {
    throw new TypeError(`${where}.feed.visibility is "access" or "public"`);
  }

  if (!whole(pastDays, 0, 36_600)) {
    throw new TypeError(`${where}.feed.pastDays is a whole number of days`);
  }

  if (futureDays !== undefined && !whole(futureDays, 0, 36_600)) {
    throw new TypeError(`${where}.feed.futureDays is a whole number of days`);
  }

  if (!whole(limit, 1, 100_000)) {
    throw new TypeError(`${where}.feed.limit is between 1 and 100000`);
  }

  if (typeof single !== "boolean") {
    throw new TypeError(`${where}.feed.single is a boolean`);
  }

  return { visibility, pastDays, futureDays, limit, single };
}

/** SQL bounding an item that starts at `starts` and ends at `ends`. */
export function feedWindow(
  feed: FeedOptions,
  starts: string,
  ends: string,
  open = "false",
): string {
  return `(${open} or ${ends} > now() - interval '${String(feed.pastDays)} days')${
    feed.futureDays === undefined
      ? ""
      : ` and ${starts} < now() + interval '${String(feed.futureDays)} days'`
  }`;
}

export function feedDateWindow(
  feed: FeedOptions,
  starts: string,
  ends: string,
): string {
  return `${ends} >= current_date - ${String(feed.pastDays)}${
    feed.futureDays === undefined
      ? ""
      : ` and ${starts} <= current_date + ${String(feed.futureDays)}`
  }`;
}
