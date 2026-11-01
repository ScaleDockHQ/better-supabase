import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

import type {
  BillingSummary,
  LoginGrant,
  LoginStart,
  SampleRequest,
  SampleResponse,
  UpgradeProblem,
} from "./contract.ts";

import {
  isBillingSummary,
  isLoginGrant,
  isLoginStart,
  isSampleResponse,
  isUpgradeProblem,
} from "./contract.ts";

export const DEFAULT_CLOUD_URL = "https://app.bettersupabase.com";

export type Fetch = (
  input: string,
  init?: RequestInit,
) => Promise<Pick<Response, "ok" | "status" | "json" | "text">>;

/** The saved login. */
export interface StoredLogin {
  readonly accessToken: string;
  readonly refreshToken: string;
  readonly expiresAt: number;
  readonly email: string;
}

/** `$XDG_CONFIG_HOME/better-supabase/auth.json`, or under `~/.config`. */
export function tokenPath(env: {
  readonly XDG_CONFIG_HOME?: string | undefined;
  readonly HOME?: string | undefined;
}): string {
  const base =
    env.XDG_CONFIG_HOME !== undefined && env.XDG_CONFIG_HOME !== ""
      ? env.XDG_CONFIG_HOME
      : join(env.HOME ?? homedir(), ".config");

  return join(base, "better-supabase", "auth.json");
}

function isStoredLogin(value: unknown): value is StoredLogin {
  return (
    typeof value === "object" &&
    value !== null &&
    "accessToken" in value &&
    typeof value.accessToken === "string" &&
    "refreshToken" in value &&
    typeof value.refreshToken === "string" &&
    "expiresAt" in value &&
    typeof value.expiresAt === "number" &&
    "email" in value &&
    typeof value.email === "string"
  );
}

export async function readLogin(
  path: string,
): Promise<StoredLogin | undefined> {
  let text: string;

  try {
    text = await readFile(path, "utf-8");
  } catch {
    return undefined;
  }

  try {
    const value: unknown = JSON.parse(text);

    return isStoredLogin(value) ? value : undefined;
  } catch {
    return undefined;
  }
}

/** Writes the login readable by the user only. */
export async function saveLogin(
  path: string,
  grant: LoginGrant,
): Promise<StoredLogin> {
  const { accessToken, refreshToken, expiresAt, email } = grant;
  const stored: StoredLogin = { accessToken, refreshToken, expiresAt, email };

  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  await writeFile(path, `${JSON.stringify(stored, null, 2)}\n`, {
    mode: 0o600,
  });

  return stored;
}

export async function clearLogin(path: string): Promise<boolean> {
  const existed = (await readLogin(path)) !== undefined;

  await rm(path, { force: true });

  return existed;
}

/** Whether the token has run out, with a minute of leeway. */
export const isExpired = (
  login: StoredLogin,
  now: number = Date.now(),
): boolean => login.expiresAt * 1000 - 60_000 <= now;

export class CloudError extends Error {
  readonly kind:
    | "network"
    | "unauthorized"
    | "upgrade"
    | "rejected"
    | "pending"
    | "expired";
  readonly status?: number;
  readonly upgrade?: string;

  constructor(
    kind: CloudError["kind"],
    message: string,
    extra: { status?: number; upgrade?: string } = {},
  ) {
    super(message);
    this.name = "CloudError";
    this.kind = kind;

    if (extra.status !== undefined) {
      this.status = extra.status;
    }

    if (extra.upgrade !== undefined) {
      this.upgrade = extra.upgrade;
    }
  }
}

async function send(
  fetcher: Fetch,
  url: string,
  init: RequestInit,
): Promise<{ status: number; body: unknown; ok: boolean }> {
  let response: Awaited<ReturnType<Fetch>>;

  try {
    response = await fetcher(url, init);
  } catch (error) {
    throw new CloudError(
      "network",
      `Could not reach ${new URL(url).origin}: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  let body: unknown;

  try {
    body = await response.json();
  } catch {
    body = undefined;
  }

  return { status: response.status, body, ok: response.ok };
}

const json = (token: string | undefined, body?: unknown): RequestInit => ({
  method: body === undefined ? "GET" : "POST",
  headers: {
    accept: "application/json, application/problem+json",
    ...(body === undefined ? {} : { "content-type": "application/json" }),
    ...(token === undefined ? {} : { authorization: `Bearer ${token}` }),
  },
  ...(body === undefined ? {} : { body: JSON.stringify(body) }),
});

/** Asks the cloud for sample statements. */
export async function requestSample(
  fetcher: Fetch,
  base: string,
  token: string,
  request: SampleRequest,
): Promise<SampleResponse> {
  const { status, body, ok } = await send(
    fetcher,
    `${base}/api/seeds/sample`,
    json(token, request),
  );

  if (status === 402) {
    const problem: UpgradeProblem | undefined = isUpgradeProblem(body)
      ? body
      : undefined;

    throw new CloudError(
      "upgrade",
      problem?.detail ?? problem?.title ?? "Sample data needs the Pro plan",
      { status, upgrade: problem?.upgrade ?? `${base}/billing` },
    );
  }

  if (status === 401) {
    throw new CloudError("unauthorized", "The saved login was rejected", {
      status,
    });
  }

  if (!ok || !isSampleResponse(body)) {
    throw new CloudError(
      "rejected",
      `The sample data request failed with status ${String(status)}`,
      { status },
    );
  }

  return body;
}

export async function startLogin(
  fetcher: Fetch,
  base: string,
): Promise<LoginStart> {
  const { status, body, ok } = await send(
    fetcher,
    `${base}/api/cli/auth/start`,
    json(undefined, {}),
  );

  if (!ok || !isLoginStart(body)) {
    throw new CloudError(
      "rejected",
      `The login could not start (status ${String(status)})`,
      { status },
    );
  }

  return body;
}

/** One poll: the grant, or a `pending` or `expired` error to branch on. */
export async function pollLogin(
  fetcher: Fetch,
  base: string,
  deviceCode: string,
): Promise<LoginGrant> {
  const { status, body, ok } = await send(
    fetcher,
    `${base}/api/cli/auth/poll`,
    json(undefined, { deviceCode }),
  );

  if (ok && isLoginGrant(body)) {
    return body;
  }

  if (status === 202 || (ok && !isLoginGrant(body))) {
    throw new CloudError("pending", "Waiting for approval", { status });
  }

  if (status === 410 || status === 400) {
    throw new CloudError("expired", "The login expired or was denied", {
      status,
    });
  }

  throw new CloudError(
    "rejected",
    `The login failed (status ${String(status)})`,
    { status },
  );
}

/**
 * Trades the refresh token for a new grant. The cloud rotates the refresh
 * token, so the caller must save the answer.
 */
export async function refreshLogin(
  fetcher: Fetch,
  base: string,
  refreshToken: string,
): Promise<LoginGrant> {
  const { status, body, ok } = await send(
    fetcher,
    `${base}/api/cli/auth/refresh`,
    json(undefined, { refreshToken }),
  );

  if (ok && isLoginGrant(body)) {
    return body;
  }

  if (status === 401 || status === 400 || status === 410) {
    throw new CloudError("unauthorized", "The saved login has expired", {
      status,
    });
  }

  throw new CloudError(
    "rejected",
    `The login could not be refreshed (status ${String(status)})`,
    { status },
  );
}

/**
 * The saved login, refreshed and saved again when its access token has run out.
 * A refresh the cloud refuses clears nothing: the caller reports "Not logged
 * in" and the user runs `login`. Returns undefined without a login.
 */
export async function activeLogin(
  path: string,
  fetcher: Fetch,
  base: string,
  now: number,
): Promise<StoredLogin | undefined> {
  const login = await readLogin(path);

  if (login === undefined || !isExpired(login, now)) {
    return login;
  }

  try {
    const grant = await refreshLogin(fetcher, base, login.refreshToken);

    await saveLogin(path, grant);

    const { accessToken, refreshToken, expiresAt, email } = grant;

    return { accessToken, refreshToken, expiresAt, email };
  } catch (error) {
    if (error instanceof CloudError && error.kind === "network") {
      throw error;
    }

    return undefined;
  }
}

export async function billingSummary(
  fetcher: Fetch,
  base: string,
  token: string,
): Promise<BillingSummary> {
  const { status, body, ok } = await send(
    fetcher,
    `${base}/api/billing`,
    json(token),
  );

  if (status === 401) {
    throw new CloudError("unauthorized", "The saved login was rejected", {
      status,
    });
  }

  if (!ok || !isBillingSummary(body)) {
    throw new CloudError(
      "rejected",
      `The account lookup failed (status ${String(status)})`,
      { status },
    );
  }

  return body;
}
