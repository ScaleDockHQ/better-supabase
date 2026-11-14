import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { errorText, isRecord, portOf } from "../shared.ts";

/** Options every `DomainProvider` call takes. */
export interface DomainProviderCallOptions {
  readonly signal?: AbortSignal;
}

/**
 * A DNS record the hosting platform asks for before it serves the hostname,
 * shown next to the block's own TXT record.
 */
export interface DomainProviderRecord {
  /** `TXT`, `CNAME`, `A`, ... */
  readonly type: string;
  readonly name: string;
  readonly value: string;
  /** Why the platform asks for it, in the platform's words. */
  readonly reason: string | undefined;
}

/** A hostname as the hosting platform sees it. */
export interface DomainProviderStatus {
  readonly hostname: string;
  /** The platform serves the hostname for this project. */
  readonly verified: boolean;
  /** The platform's challenges still to publish; empty once verified. */
  readonly records: readonly DomainProviderRecord[];
}

/**
 * Adds, verifies and removes hostnames on the platform that serves the app
 * (Vercel, Cloudflare, ...), next to the TXT check of `createDomainsAdmin`.
 * Versioned: a breaking change to this contract ships a new `apiVersion`.
 * Methods never throw; errors are `DbError`s.
 */
export interface DomainProvider {
  readonly apiVersion: 1;
  /** `vercel`, `cloudflare`, ... */
  readonly name: string;
  /**
   * Adds the hostname to the project; adding one already there returns its
   * status.
   */
  add(
    hostname: string,
    options?: DomainProviderCallOptions,
  ): AsyncResult<DomainProviderStatus>;
  /**
   * Asks the platform to check its challenges. A hostname that doesn't pass yet
   * comes back with `verified: false`, not an error.
   */
  verify(
    hostname: string,
    options?: DomainProviderCallOptions,
  ): AsyncResult<DomainProviderStatus>;
  /** `false` when the platform has no such hostname on the project. */
  remove(
    hostname: string,
    options?: DomainProviderCallOptions,
  ): AsyncResult<boolean>;
  /** `undefined` when the platform has no such hostname on the project. */
  status(
    hostname: string,
    options?: DomainProviderCallOptions,
  ): AsyncResult<DomainProviderStatus | undefined>;
}

/** Checks the provider's `apiVersion` before the block uses it. */
export function domainProviderOf(provider: DomainProvider): DomainProvider {
  portOf(`domains "${provider.name}"`, "domain provider", provider);

  return provider;
}

/** A verification challenge on a Vercel project domain. */
export interface VercelDomainVerification {
  readonly type: string;
  readonly domain: string;
  readonly value: string;
  readonly reason: string;
}

/** The fields of a Vercel project domain the provider reads. */
export interface VercelProjectDomain {
  readonly name: string;
  readonly projectId: string;
  readonly verified: boolean;
  readonly verification?: readonly VercelDomainVerification[] | undefined;
}

/** The project and team a Vercel project domain call targets. */
export interface VercelProjectDomainRequest {
  readonly idOrName: string;
  readonly domain: string;
  readonly teamId?: string;
  readonly slug?: string;
}

/** The part of the `@vercel/sdk` request options the provider passes. */
export interface VercelRequestOptions {
  readonly signal?: AbortSignal;
}

/**
 * The project domain methods of `@vercel/sdk`, typed structurally; pass `new
 * Vercel({ bearerToken })` from `@vercel/sdk`.
 */
export interface VercelDomainsSdk {
  readonly projects: {
    addProjectDomain(
      request: {
        readonly idOrName: string;
        readonly teamId?: string;
        readonly slug?: string;
        readonly requestBody: { readonly name: string };
      },
      options?: VercelRequestOptions,
    ): Promise<VercelProjectDomain>;
    verifyProjectDomain(
      request: VercelProjectDomainRequest,
      options?: VercelRequestOptions,
    ): Promise<VercelProjectDomain>;
    removeProjectDomain(
      request: VercelProjectDomainRequest,
      options?: VercelRequestOptions,
    ): Promise<unknown>;
    getProjectDomain(
      request: VercelProjectDomainRequest,
      options?: VercelRequestOptions,
    ): Promise<VercelProjectDomain>;
  };
}

export interface VercelDomainProviderOptions {
  /** The project's id (`prj_...`) that serves the app. */
  readonly projectId: string;
  /** The team that owns the project, when it isn't the token's personal account. */
  readonly teamId?: string;
  /** The team's slug, instead of `teamId`. */
  readonly slug?: string;
}

function statusCodeOf(cause: unknown): number | undefined {
  if (!isRecord(cause)) {
    return undefined;
  }

  const code = cause["statusCode"] ?? cause["status"];

  return typeof code === "number" ? code : undefined;
}

/** Vercel's `{ error: { code, message } }` body, when the error carries one. */
function bodyErrorOf(cause: unknown): {
  readonly code?: string;
  readonly message?: string;
} {
  const body = isRecord(cause) ? cause["body"] : undefined;

  if (typeof body !== "string") {
    return {};
  }

  try {
    const parsed: unknown = JSON.parse(body);
    const error = isRecord(parsed) ? parsed["error"] : undefined;

    if (!isRecord(error)) {
      return {};
    }

    const { code, message } = error;

    return {
      ...(typeof code === "string" ? { code } : {}),
      ...(typeof message === "string" ? { message } : {}),
    };
  } catch {
    return {};
  }
}

/** `Retry-After` in seconds: delta-seconds or an HTTP date. */
function retryAfterOf(cause: unknown): number | undefined {
  const headers = isRecord(cause) ? cause["headers"] : undefined;

  if (!(headers instanceof Headers)) {
    return undefined;
  }

  const value = headers.get("retry-after")?.trim();

  if (value === undefined || value === "") {
    return undefined;
  }

  if (/^\d+$/u.test(value)) {
    return Number(value);
  }

  const at = Date.parse(value);

  return Number.isNaN(at)
    ? undefined
    : Math.max(0, Math.ceil((at - Date.now()) / 1000));
}

function isAbort(cause: unknown): boolean {
  return (
    cause instanceof Error &&
    (cause.name === "AbortError" || cause.name === "RequestAbortedError")
  );
}

/** The `DbError` for a failed Vercel call. */
function vercelError(cause: unknown, signal: AbortSignal | undefined): DbError {
  if (isAbort(cause) || signal?.aborted === true) {
    return dbError("aborted", errorText(cause));
  }

  const status = statusCodeOf(cause);
  const body = bodyErrorOf(cause);
  const message = `Vercel: ${body.message ?? errorText(cause)}`;
  const code = body.code === undefined ? {} : { code: body.code };

  if (status === undefined) {
    return dbError("network", message, { hint: "DOMAIN_PROVIDER_FAILED" });
  }

  if (status === 401 || status === 403) {
    return dbError("forbidden", message, code);
  }

  if (status === 404) {
    return dbError("not_found", message, code);
  }

  if (status === 409) {
    return dbError("conflict", message, code);
  }

  if (status === 429) {
    const retryAfter = retryAfterOf(cause);

    return dbError("rate_limited", message, {
      ...code,
      ...(retryAfter === undefined ? {} : { retryAfter }),
    });
  }

  if (status === 400 || status === 422) {
    return dbError("invalid_input", message, code);
  }

  return status >= 500
    ? dbError("network", message, { ...code, hint: "DOMAIN_PROVIDER_FAILED" })
    : dbError("unexpected", message, {
        ...code,
        hint: "DOMAIN_PROVIDER_FAILED",
      });
}

function statusOf(domain: VercelProjectDomain): DomainProviderStatus {
  return {
    hostname: domain.name,
    verified: domain.verified,
    records: (domain.verification ?? []).map((challenge) => ({
      type: challenge.type,
      name: challenge.domain,
      value: challenge.value,
      reason: challenge.reason,
    })),
  };
}

/**
 * A `DomainProvider` for a Vercel project, over `@vercel/sdk`. Vercel asks for
 * its own TXT challenge when the domain is in use on another Vercel account;
 * `add` and `status` return it in `records`, and `verify` reports `verified:
 * false` until it is published. A domain on another project of the account
 * fails with `DOMAIN_PROVIDER_CONFLICT`.
 */
export function vercelDomainProvider(
  sdk: VercelDomainsSdk,
  options: VercelDomainProviderOptions,
): DomainProvider {
  const { projectId } = options;

  const scope = {
    idOrName: projectId,
    ...(options.teamId === undefined ? {} : { teamId: options.teamId }),
    ...(options.slug === undefined ? {} : { slug: options.slug }),
  };

  const run = <T>(
    call: DomainProviderCallOptions | undefined,
    body: (
      request: VercelRequestOptions | undefined,
      signal: AbortSignal | undefined,
    ) => Promise<Result<T>>,
  ): AsyncResult<T> => {
    const signal = call?.signal;

    return AsyncResult.from(() =>
      body(signal === undefined ? undefined : { signal }, signal),
    );
  };

  const current = async (
    hostname: string,
    request: VercelRequestOptions | undefined,
    signal: AbortSignal | undefined,
  ): Promise<Result<VercelProjectDomain | undefined>> => {
    try {
      return ok(
        await sdk.projects.getProjectDomain(
          { ...scope, domain: hostname },
          request,
        ),
      );
    } catch (cause) {
      return statusCodeOf(cause) === 404
        ? ok(undefined)
        : err(vercelError(cause, signal));
    }
  };

  return {
    apiVersion: 1,
    name: "vercel",
    add: (hostname, call) =>
      run(call, async (request, signal) => {
        try {
          return ok(
            statusOf(
              await sdk.projects.addProjectDomain(
                { ...scope, requestBody: { name: hostname } },
                request,
              ),
            ),
          );
        } catch (cause) {
          const status = statusCodeOf(cause);

          if (status !== 400 && status !== 409) {
            return err(vercelError(cause, signal));
          }

          const found = await current(hostname, request, signal);

          if (found.ok && found.data?.projectId === projectId) {
            return ok(statusOf(found.data));
          }

          return status === 409
            ? err(
                dbError(
                  "conflict",
                  `${hostname} is on another Vercel project; remove it there first`,
                  { hint: "DOMAIN_PROVIDER_CONFLICT" },
                ),
              )
            : err(vercelError(cause, signal));
        }
      }),
    verify: (hostname, call) =>
      run<DomainProviderStatus>(call, async (request, signal) => {
        try {
          const verified = await sdk.projects.verifyProjectDomain(
            { ...scope, domain: hostname },
            request,
          );

          if (verified.verified) {
            return ok({ hostname: verified.name, verified: true, records: [] });
          }
        } catch (cause) {
          if (statusCodeOf(cause) !== 400) {
            return err(vercelError(cause, signal));
          }
        }

        const found = await current(hostname, request, signal);

        if (!found.ok) {
          return found;
        }

        if (found.data === undefined) {
          return err(
            dbError("not_found", `${hostname} is not on the Vercel project`),
          );
        }

        return ok({ ...statusOf(found.data), verified: false });
      }),
    remove: (hostname, call) =>
      run(call, async (request, signal) => {
        try {
          await sdk.projects.removeProjectDomain(
            { ...scope, domain: hostname },
            request,
          );

          return ok(true);
        } catch (cause) {
          return statusCodeOf(cause) === 404
            ? ok(false)
            : err(vercelError(cause, signal));
        }
      }),
    status: (hostname, call) =>
      run(call, async (request, signal) => {
        const found = await current(hostname, request, signal);

        return found.ok
          ? ok(found.data === undefined ? undefined : statusOf(found.data))
          : found;
      }),
  };
}
