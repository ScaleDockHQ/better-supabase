/**
 * The contract between the CLI and the cloud app for sample data and login (ADR
 * 0196). The cloud implements it in `better-supabase-cloud`; the CLI is the
 * only client the library ships.
 *
 * - `POST /api/seeds/sample` with a Bearer token and a `SampleRequest`. It
 *   answers 200 with a `SampleResponse`, or 402 `application/problem+json` with
 *   an `upgrade` URL when the account's plan lacks `sampleData`.
 * - `POST /api/cli/auth/start` answers a `LoginStart`; `POST /api/cli/auth/poll`
 *   with `{ deviceCode }` answers 202 `{ status: "pending" }` until the user
 *   approves in the browser, then 200 with a `LoginGrant`, or 410 `{ status:
 *   "expired" | "denied" }`.
 * - `GET /api/billing` with a Bearer token answers a `BillingSummary`.
 */

export type SampleTarget = "tenant" | "demoOrg";

export interface SampleRequest {
  /** The resolved design: blocks, instances and options, or a preset by name. */
  readonly design?: unknown;
  readonly preset?: string;
  /** Block instance names, so the data lands in the right tables. */
  readonly instances?: readonly string[];
  /** The variant each block seeds, keyed by block name. */
  readonly variants: Readonly<Record<string, string>>;
  readonly locale: string;
  readonly size: "s" | "m" | "l";
  /** The random seed: the same number gives the same statements. */
  readonly seed: number;
  readonly target: SampleTarget;
  /** The organization slug or id when `target` is `tenant`. */
  readonly tenant?: string;
}

export interface SampleResponse {
  /** SQL statements in the order they run; each is one statement. */
  readonly statements: readonly string[];
  readonly summary: string;
  readonly estimatedRows: number;
}

/** `application/problem+json` the cloud answers with on 402. */
export interface UpgradeProblem {
  readonly type?: string;
  readonly title: string;
  readonly status: 402;
  readonly detail?: string;
  /** Where the user upgrades. */
  readonly upgrade: string;
}

export interface LoginStart {
  readonly deviceCode: string;
  readonly userCode: string;
  /** The page the user opens to approve the login. */
  readonly verificationUrl: string;
  /** Seconds between polls. */
  readonly interval: number;
  /** Seconds until the device code expires. */
  readonly expiresIn: number;
}

export interface LoginGrant {
  readonly status: "approved";
  readonly accessToken: string;
  readonly refreshToken: string;
  /** Unix seconds. */
  readonly expiresAt: number;
  readonly email: string;
}

export interface BillingSummary {
  readonly plan: string;
  readonly email?: string;
}

function isRecord(value: unknown): value is object {
  return typeof value === "object" && value !== null;
}

const field = (value: object, key: string): unknown =>
  Object.entries(value).find(([name]) => name === key)?.[1];

const isStringArray = (value: unknown): boolean =>
  Array.isArray(value) && value.every((entry) => typeof entry === "string");

export function isSampleResponse(value: unknown): value is SampleResponse {
  return (
    isRecord(value) &&
    isStringArray(field(value, "statements")) &&
    typeof field(value, "summary") === "string" &&
    typeof field(value, "estimatedRows") === "number"
  );
}

export function isUpgradeProblem(value: unknown): value is UpgradeProblem {
  return (
    isRecord(value) &&
    field(value, "status") === 402 &&
    typeof field(value, "title") === "string" &&
    typeof field(value, "upgrade") === "string"
  );
}

export function isLoginStart(value: unknown): value is LoginStart {
  return (
    isRecord(value) &&
    typeof field(value, "deviceCode") === "string" &&
    typeof field(value, "userCode") === "string" &&
    typeof field(value, "verificationUrl") === "string" &&
    typeof field(value, "interval") === "number" &&
    typeof field(value, "expiresIn") === "number"
  );
}

export function isLoginGrant(value: unknown): value is LoginGrant {
  return (
    isRecord(value) &&
    field(value, "status") === "approved" &&
    typeof field(value, "accessToken") === "string" &&
    typeof field(value, "refreshToken") === "string" &&
    typeof field(value, "expiresAt") === "number" &&
    typeof field(value, "email") === "string"
  );
}

export function isBillingSummary(value: unknown): value is BillingSummary {
  return isRecord(value) && typeof field(value, "plan") === "string";
}
