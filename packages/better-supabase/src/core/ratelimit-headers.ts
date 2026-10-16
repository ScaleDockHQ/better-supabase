/**
 * The `RateLimit` and `RateLimit-Policy` response fields of
 * draft-ietf-httpapi-ratelimit-headers (`SPEC_PINS.ratelimitHeaders`), as
 * RFC 9651 Structured Fields Lists.
 */

/** One quota policy in `RateLimit-Policy`. */
export interface RateLimitPolicy {
  /** Printable ASCII; the `RateLimit` item names the policy with it. */
  readonly name: string;
  /** The quota: requests (or `unit`) allowed per window. */
  readonly quota: number;
  /** The window in whole seconds, greater than zero. */
  readonly window?: number;
  readonly unit?: "requests" | "content-bytes" | "concurrent-requests";
}

/** The quota left under one policy, for `RateLimit`. */
export interface RateLimitState {
  readonly policy: string;
  readonly remaining: number;
  /** Seconds until the quota is restored. */
  readonly reset?: number;
}

const MAX_INTEGER = 999_999_999_999_999;
const PRINTABLE = /^[\u0020-\u007E]*$/;

/** Whether `name` can be a policy name: printable ASCII only (RFC 9651 § 3.3.3). */
export function isRateLimitPolicyName(name: string): boolean {
  return name.length > 0 && PRINTABLE.test(name);
}

function sfString(value: string): string {
  if (!isRateLimitPolicyName(value)) {
    throw new TypeError(
      `"${value}" is not a RateLimit policy name: use printable ASCII`,
    );
  }
  return `"${value.replaceAll(/[\\"]/g, (char) => `\\${char}`)}"`;
}

function sfInteger(value: number, field: string): string {
  const whole = Math.ceil(value);
  if (!Number.isFinite(whole) || whole < 0 || whole > MAX_INTEGER) {
    throw new TypeError(
      `${field} must be a non-negative integer, got ${value}`,
    );
  }
  return String(whole);
}

/** The `RateLimit-Policy` value for `policies`. */
export function rateLimitPolicyHeader(
  policies: readonly RateLimitPolicy[],
): string {
  if (policies.length === 0) {
    throw new TypeError("RateLimit-Policy needs at least one policy");
  }
  return policies
    .map((policy) => {
      let item = `${sfString(policy.name)};q=${sfInteger(policy.quota, "q")}`;
      if (policy.unit !== undefined && policy.unit !== "requests") {
        item += `;qu=${sfString(policy.unit)}`;
      }
      if (policy.window !== undefined) {
        if (policy.window <= 0) throw new TypeError("w must be greater than 0");
        item += `;w=${sfInteger(policy.window, "w")}`;
      }
      return item;
    })
    .join(", ");
}

/** The `RateLimit` value for `states`. */
export function rateLimitHeader(states: readonly RateLimitState[]): string {
  return states
    .map((state) => {
      let item = `${sfString(state.policy)};r=${sfInteger(state.remaining, "r")}`;
      if (state.reset !== undefined)
        item += `;t=${sfInteger(state.reset, "t")}`;
      return item;
    })
    .join(", ");
}

const UNIT_SECONDS: Readonly<Record<string, number>> = {
  second: 1,
  sec: 1,
  minute: 60,
  min: 60,
  hour: 3600,
  hr: 3600,
  day: 86_400,
};
const INTERVAL = /^\s*(\d+)\s*([a-z]+)\s*$/i;

/**
 * Whole seconds in a period of `count unit` (`1 minute`, `30 seconds`,
 * `2 hours`) or a number of seconds; `undefined` for any other interval.
 */
export function periodSeconds(period: number | string): number | undefined {
  if (typeof period === "number") {
    return Number.isFinite(period) && period > 0
      ? Math.ceil(period)
      : undefined;
  }
  const match = INTERVAL.exec(period);
  if (!match) return undefined;
  const word = match[2]!.toLowerCase();
  const unit =
    UNIT_SECONDS[word] ??
    (word.endsWith("s") ? UNIT_SECONDS[word.slice(0, -1)] : undefined);
  const count = Number(match[1]);
  return unit === undefined || count <= 0 ? undefined : count * unit;
}
