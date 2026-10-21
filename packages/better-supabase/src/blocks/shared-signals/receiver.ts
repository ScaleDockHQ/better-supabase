import type { BlockHooks } from "../../core/block-hooks.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { type Jwks, jwksOf } from "../../core/jws.ts";
import { consoleLogger, type Logger } from "../../core/logger.ts";
import { AsyncResult, err, ok, type Result } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockOptions,
  errorText,
  isRecord,
  readBodyCapped,
} from "../shared.ts";
import { SSF_POLL, SSF_PUSH } from "./methods.ts";
import {
  SET_CONTENT_TYPE,
  type SetErrorCode,
  type VerifiedSet,
  verifySet,
} from "./set.ts";

/**
 * Handles one event type; a throw leaves the SET unprocessed, so the
 * transmitter sends it again.
 */
export type SsfEventHandler = (set: VerifiedSet) => void | Promise<void>;

export interface SsfReceiverOptions extends BlockOptions {
  /**
   * The transmitter's issuer, compared exactly with its metadata and each
   * `iss`.
   */
  readonly issuer: string;
  /** This receiver's `aud`. */
  readonly audience: string;
  /** The transmitter's keys. Default: its metadata's `jwks_uri`, cached. */
  readonly jwks?: Jwks | (() => Promise<Jwks>);
  /**
   * Handlers by event type URI; `"*"` takes the rest. Unhandled events are
   * acknowledged.
   */
  readonly handlers?: Readonly<Record<string, SsfEventHandler>>;
  /**
   * The `Authorization` header value the transmitter pushes with; checked when
   * set.
   */
  readonly authorization?: string;
  /** The transmitter's `critical_subject_members`. */
  readonly criticalSubjectMembers?: readonly string[];
  /** How long fetched metadata and keys stay cached, in seconds. Default: 300. */
  readonly cacheSeconds?: number;
  /** The largest pushed SET, in bytes. Default: 64 KiB. */
  readonly maxBodyBytes?: number;
  readonly fetch?: typeof fetch;
  /**
   * Receives handler errors and the errors `after` hooks throw. Default:
   * `consoleLogger`.
   */
  readonly logger?: Logger;
  /** `withBlockHooks` hooks around the receiver's methods. */
  readonly hooks?: NoInfer<BlockHooks<SsfReceiver>>;
}

export type SsfReceiveResult =
  | {
      readonly ok: true;
      readonly set: VerifiedSet;
      readonly duplicate: boolean;
    }
  | {
      readonly ok: false;
      readonly err: SetErrorCode;
      readonly description: string;
    };

export interface SsfPollOptions {
  /** The stream's `delivery.endpoint_url`. */
  readonly endpoint: string;
  /** The `Authorization` header value the transmitter's API takes. */
  readonly authorization: string;
  /** SETs per request. Default: 100. */
  readonly maxEvents?: number;
  /** Requests before returning. Default: 10. */
  readonly maxRequests?: number;
}

export interface SsfPollResult {
  readonly received: number;
  readonly rejected: number;
  /** SETs whose handler threw: not acknowledged, so the next poll returns them. */
  readonly failed: number;
  readonly moreAvailable: boolean;
}

export interface SsfStreamRequest {
  readonly method: "push" | "poll";
  /** Required for push: this receiver's RFC 8935 endpoint. */
  readonly endpointUrl?: string;
  /** The `Authorization` header the transmitter pushes with. */
  readonly authorizationHeader?: string;
  readonly eventsRequested: readonly string[];
  readonly description?: string;
}

/** The transmitter's stream management API, as a receiver calls it. */
export interface SsfStreamClient {
  create(
    request: SsfStreamRequest,
  ): AsyncResult<Readonly<Record<string, unknown>>>;
  read(streamId: string): AsyncResult<Readonly<Record<string, unknown>>>;
  remove(streamId: string): AsyncResult<void>;
  status(streamId: string): AsyncResult<Readonly<Record<string, unknown>>>;
  setStatus(
    streamId: string,
    status: "enabled" | "paused" | "disabled",
    reason?: string,
  ): AsyncResult<Readonly<Record<string, unknown>>>;
  /** Asks for a verification event; `false` when the transmitter answered 429. */
  verify(streamId: string, state?: string): AsyncResult<boolean>;
}

/** An SSF 1.0 receiver on the `shared-signals` module's replay table. */
export interface SsfReceiver {
  /** The transmitter's metadata, with its `issuer` checked. */
  discover(): AsyncResult<Readonly<Record<string, unknown>>>;
  /** Verifies a SET, drops a replay, and runs its handler. */
  receive(token: string): Promise<SsfReceiveResult>;
  /** The RFC 8935 push endpoint: 202, or 400 with `{ err, description }`. */
  pushHandler(): (request: Request) => Promise<Response>;
  /**
   * RFC 8936: polls until no more SETs are available, acknowledging what it
   * processed.
   */
  poll(options: SsfPollOptions): AsyncResult<SsfPollResult>;
  /** The management API with this `Authorization` header value. */
  streams(authorization: string): SsfStreamClient;
  /** Deletes replay entries past the retention. */
  purge(olderThan?: Temporal.Duration): AsyncResult<number>;
}

const failure = (
  code: SetErrorCode,
  description: string,
): SsfReceiveResult => ({ ok: false, err: code, description });

const rejected = (
  code: SetErrorCode,
  description: string,
  status = 400,
): Response => Response.json({ err: code, description }, { status });

function wellKnown(issuer: string): string {
  const parsed = new URL(issuer);

  const path =
    parsed.pathname === "/" ? "" : parsed.pathname.replace(/\/$/, "");

  return `${parsed.origin}/.well-known/ssf-configuration${path}`;
}

/**
 * An SSF receiver: verifies pushed or polled SETs with the transmitter's keys,
 * drops replays through the `shared-signals` module's `(iss, jti)` table, and
 * calls the handler for the event type. Service role only.
 */
export function createSsfReceiver(options: SsfReceiverOptions): SsfReceiver {
  applyTemporal(options);

  const call = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const http = options.fetch ?? fetch;
  const cacheMs = (options.cacheSeconds ?? 300) * 1000;
  const maxBody = options.maxBodyBytes ?? 65_536;
  const logger = options.logger ?? consoleLogger;

  let metadata:
    | { readonly value: Record<string, unknown>; readonly at: number }
    | undefined;

  let keys: { readonly value: Jwks; readonly at: number } | undefined;

  const getJson = async (
    url: string,
    init: RequestInit = {},
  ): Promise<Result<unknown>> => {
    let response: Response;

    try {
      const headers = new Headers(init.headers);

      if (!headers.has("accept")) {
        headers.set("accept", "application/json");
      }

      response = await http(url, { ...init, headers });
    } catch (cause) {
      return err(dbError("network", `${url}: ${errorText(cause)}`));
    }

    if (!response.ok) {
      return err(
        dbError(
          response.status === 404 ? "not_found" : "unexpected",
          `${url} answered ${String(response.status)}`,
        ),
      );
    }

    if (response.status === 204) {
      return ok(null);
    }

    try {
      const value: unknown = await response.json();

      return ok(value);
    } catch {
      return err(dbError("unexpected", `${url} did not answer JSON`));
    }
  };

  const discover: SsfReceiver["discover"] = () =>
    AsyncResult.from(async () => {
      if (metadata && Date.now() - metadata.at < cacheMs) {
        return ok(metadata.value);
      }

      const fetched = await getJson(wellKnown(options.issuer));

      if (!fetched.ok) {
        return fetched;
      }

      if (
        !isRecord(fetched.data) ||
        fetched.data["issuer"] !== options.issuer
      ) {
        return err(
          dbError(
            "unexpected",
            "The transmitter metadata names another issuer",
            { hint: "SSF_ISSUER_MISMATCH" },
          ),
        );
      }

      metadata = { value: fetched.data, at: Date.now() };

      return ok(fetched.data);
    });

  const jwks = async (refresh: boolean): Promise<Result<Jwks>> => {
    if (options.jwks !== undefined) {
      return ok(
        typeof options.jwks === "function"
          ? await options.jwks()
          : options.jwks,
      );
    }

    if (keys && !refresh && Date.now() - keys.at < cacheMs) {
      return ok(keys.value);
    }

    // A refresh for an unknown kid waits 30 seconds between fetches.
    if (keys && refresh && Date.now() - keys.at < 30_000) {
      return ok(keys.value);
    }

    const meta = await discover();

    if (!meta.ok) {
      return meta;
    }

    const uri = meta.data["jwks_uri"];

    if (typeof uri !== "string") {
      return err(
        dbError("unexpected", "The transmitter metadata has no jwks_uri"),
      );
    }

    const fetched = await getJson(uri);

    if (!fetched.ok) {
      return fetched;
    }

    keys = { value: jwksOf(fetched.data), at: Date.now() };

    return ok(keys.value);
  };

  const verify = async (token: string) => {
    for (const refresh of [false, true]) {
      const found = await jwks(refresh);

      if (!found.ok) {
        return failure("invalid_key", found.error.message);
      }

      const verified = await verifySet(token, {
        jwks: found.data,
        issuer: options.issuer,
        audience: options.audience,
        ...(options.criticalSubjectMembers === undefined
          ? {}
          : { criticalSubjectMembers: options.criticalSubjectMembers }),
      });

      if (
        verified.ok ||
        verified.err !== "invalid_key" ||
        options.jwks !== undefined
      ) {
        return verified;
      }
    }

    return failure("invalid_key", "No transmitter key verifies the SET");
  };

  const receive: SsfReceiver["receive"] = async (token) => {
    const verified = await verify(token);

    if (!verified.ok) {
      return verified;
    }

    const { set } = verified;

    const fresh = await call(
      "record_ssf_received",
      { issuer: set.issuer, jti: set.jti },
      (value) => value === true,
    );

    if (!fresh.ok) {
      throw new Error(fresh.error.message, { cause: fresh.error });
    }

    if (!fresh.data) {
      return { ok: true, set, duplicate: true };
    }

    const handler = options.handlers?.[set.type] ?? options.handlers?.["*"];

    try {
      await handler?.(set);
    } catch (cause) {
      await call(
        "forget_ssf_received",
        { issuer: set.issuer, jti: set.jti },
        () => undefined,
      );
      throw cause;
    }

    return { ok: true, set, duplicate: false };
  };

  const pushHandler: SsfReceiver["pushHandler"] = () => async (request) => {
    if (request.method !== "POST") {
      return new Response(null, { status: 405, headers: { allow: "POST" } });
    }

    if (
      options.authorization !== undefined &&
      request.headers.get("authorization") !== options.authorization
    ) {
      return rejected(
        "authentication_failed",
        "The Authorization header is not accepted",
        401,
      );
    }

    const type = (request.headers.get("content-type") ?? "")
      .split(";")[0]
      ?.trim()
      .toLowerCase();

    if (type !== SET_CONTENT_TYPE) {
      return rejected(
        "invalid_request",
        `The content type must be ${SET_CONTENT_TYPE}`,
      );
    }

    const token = await readBodyCapped(request, maxBody);

    if (token === undefined) {
      return rejected("invalid_request", "The SET is too large");
    }

    try {
      const result = await receive(token.trim());

      return result.ok
        ? new Response(null, { status: 202 })
        : rejected(result.err, result.description);
    } catch (cause) {
      logger.error("shared-signals: a SET handler failed", {
        error: errorText(cause),
      });

      return new Response(null, { status: 500 });
    }
  };

  const poll: SsfReceiver["poll"] = (pollOptions) =>
    AsyncResult.from(async (): Promise<Result<SsfPollResult>> => {
      const totals = { received: 0, rejected: 0, failed: 0 };
      let ack: string[] = [];
      let setErrs: Record<string, { err: string; description: string }> = {};
      let more = true;
      const maxRequests = pollOptions.maxRequests ?? 10;

      for (let request = 0; request < maxRequests && more; request += 1) {
        const response = await getJson(pollOptions.endpoint, {
          method: "POST",
          headers: {
            authorization: pollOptions.authorization,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            maxEvents: pollOptions.maxEvents ?? 100,
            returnImmediately: true,
            ack,
            ...(Object.keys(setErrs).length === 0 ? {} : { setErrs }),
          }),
        });

        if (!response.ok) {
          return response;
        }

        const body = isRecord(response.data) ? response.data : {};
        const sets = isRecord(body["sets"]) ? body["sets"] : {};
        ack = [];
        setErrs = {};

        for (const [jti, token] of Object.entries(sets)) {
          if (typeof token !== "string") {
            continue;
          }

          try {
            const result = await receive(token);

            if (result.ok) {
              ack.push(jti);
              totals.received += result.duplicate ? 0 : 1;
            } else {
              setErrs[jti] = {
                err: result.err,
                description: result.description,
              };
              totals.rejected += 1;
            }
          } catch (cause) {
            logger.error("shared-signals: a SET handler failed", {
              error: errorText(cause),
            });
            totals.failed += 1;
          }
        }

        more = body["moreAvailable"] === true;
      }

      if (ack.length > 0 || Object.keys(setErrs).length > 0) {
        const final = await getJson(pollOptions.endpoint, {
          method: "POST",
          headers: {
            authorization: pollOptions.authorization,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            maxEvents: 0,
            returnImmediately: true,
            ack,
            ...(Object.keys(setErrs).length === 0 ? {} : { setErrs }),
          }),
        });

        if (!final.ok) {
          return final;
        }
      }

      return ok({ ...totals, moreAvailable: more });
    });

  const streams: SsfReceiver["streams"] = (authorization) => {
    const endpoint = (key: string): AsyncResult<string> =>
      discover().andThen((meta) => {
        const value = meta[key];

        return Promise.resolve(
          typeof value === "string"
            ? ok(value)
            : err(
                dbError("unsupported", `The transmitter publishes no ${key}`),
              ),
        );
      });

    const send = (
      key: string,
      method: string,
      body?: unknown,
      query?: string,
    ): AsyncResult<unknown> =>
      endpoint(key).andThen((url) =>
        getJson(
          query === undefined
            ? url
            : `${url}?stream_id=${encodeURIComponent(query)}`,
          {
            method,
            headers: {
              authorization,
              ...(body === undefined
                ? {}
                : { "content-type": "application/json" }),
            },
            ...(body === undefined ? {} : { body: JSON.stringify(body) }),
          },
        ),
      );

    const record = (value: unknown): Readonly<Record<string, unknown>> =>
      isRecord(value) ? value : {};

    return {
      create: (request) =>
        send("configuration_endpoint", "POST", {
          delivery: {
            method: request.method === "push" ? SSF_PUSH : SSF_POLL,
            ...(request.endpointUrl === undefined
              ? {}
              : { endpoint_url: request.endpointUrl }),
            ...(request.authorizationHeader === undefined
              ? {}
              : { authorization_header: request.authorizationHeader }),
          },
          events_requested: request.eventsRequested,
          ...(request.description === undefined
            ? {}
            : { description: request.description }),
        }).andThen((value) => {
          const config = record(value);
          const aud = config["aud"];

          const audience =
            typeof aud === "string" ? [aud] : Array.isArray(aud) ? aud : [];

          return Promise.resolve(
            audience.includes(options.audience)
              ? ok(config)
              : err(
                  dbError(
                    "unexpected",
                    "The created stream's aud does not name this receiver",
                    { hint: "SSF_AUDIENCE_MISMATCH" },
                  ),
                ),
          );
        }),
      read: (streamId) =>
        send("configuration_endpoint", "GET", undefined, streamId).map(record),
      remove: (streamId) =>
        send("configuration_endpoint", "DELETE", undefined, streamId).map(
          () => undefined,
        ),
      status: (streamId) =>
        send("status_endpoint", "GET", undefined, streamId).map(record),
      setStatus: (streamId, status, reason) =>
        send("status_endpoint", "POST", {
          stream_id: streamId,
          status,
          ...(reason === undefined ? {} : { reason }),
        }).map(record),
      verify: (streamId, state) =>
        endpoint("verification_endpoint").andThen(async (url) => {
          let response: Response;

          try {
            response = await http(url, {
              method: "POST",
              headers: { authorization, "content-type": "application/json" },
              body: JSON.stringify({
                stream_id: streamId,
                ...(state === undefined ? {} : { state }),
              }),
            });
          } catch (cause) {
            return err(dbError("network", errorText(cause)));
          }

          if (response.status === 429) {
            return ok(false);
          }

          return response.ok
            ? ok(true)
            : err(
                dbError(
                  "unexpected",
                  `${url} answered ${String(response.status)}`,
                ),
              );
        }),
    };
  };

  const receiver: SsfReceiver = {
    discover,
    receive,
    pushHandler,
    poll,
    streams,
    purge: (olderThan) =>
      call(
        "purge_shared_signals",
        {
          older_than:
            olderThan === undefined
              ? null
              : `${String(olderThan.total({ unit: "seconds" }))} seconds`,
        },
        Number,
      ),
  };

  return withBlockHooks(receiver, options.hooks, {
    block: "shared-signals",
    logger,
  });
}
