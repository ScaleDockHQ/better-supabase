import type { BlockHooks } from "../../core/block-hooks.ts";
import type { DbError } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { CredentialRef } from "../../credentials/provider.ts";
import type { VaultCredentials } from "../../credentials/vault.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { AsyncResult, err, ok, type Result } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockOptions,
  isRecord,
  nullableText,
  readBodyCapped,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";
import { SSF_POLL, SSF_PUSH } from "./methods.ts";
import {
  CAEP_EVENTS,
  mintSet,
  RISC_EVENTS,
  type SecurityEvent,
  type SetSigner,
  SSF_EVENTS,
  type SubjectIdentifier,
} from "./set.ts";

export type SsfDeliveryMethod = "push" | "poll";
export type SsfStreamStatus = "enabled" | "paused" | "disabled";

/** A stream as the `shared-signals` module stores it. */
export interface SsfStream {
  readonly id: string;
  readonly tenant: string | null;
  /** Who manages the stream: the receiver `authorize` returned. */
  readonly receiver: string;
  readonly audience: readonly string[];
  readonly description: string | null;
  readonly eventsRequested: readonly string[];
  readonly eventsDelivered: readonly string[];
  readonly method: SsfDeliveryMethod;
  /** The receiver's push endpoint; `null` for a poll stream. */
  readonly endpointUrl: string | null;
  readonly status: SsfStreamStatus;
  readonly reason: string | null;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** The receiver a management request comes from, as `authorize` found it. */
export interface SsfReceiverIdentity {
  /** A stable id, such as the OAuth client id. */
  readonly receiver: string;
  /** Scopes the receiver's streams to one tenant's events; `null` for every tenant. */
  readonly tenant?: string | null;
  /** The `aud` of its SETs. Default: `receiver`. */
  readonly audience?: string | readonly string[];
}

export interface CreateSsfStreamInput {
  readonly receiver: SsfReceiverIdentity;
  readonly method: SsfDeliveryMethod;
  readonly eventsRequested: readonly string[];
  /** The receiver's RFC 8935 endpoint, for push. */
  readonly endpointUrl?: string;
  /** The `Authorization` header value the endpoint expects, kept in Vault. */
  readonly authorizationHeader?: string;
  readonly description?: string;
}

export interface UpdateSsfStreamInput {
  readonly description?: string | null;
  readonly eventsRequested?: readonly string[];
  readonly endpointUrl?: string;
}

export interface EmitSecurityEventInput {
  readonly event: SecurityEvent;
  readonly subject: SubjectIdentifier;
  /** The tenant the event belongs to: its streams and the app-wide ones get it. */
  readonly tenant?: string | null;
  readonly txn?: string;
}

/** What `emit` did, per stream. */
export interface EmitResult {
  readonly streams: number;
  readonly dispatched: number;
  readonly queued: number;
  readonly held: number;
}

export interface SsfTransmitterOptions extends BlockOptions {
  /** The transmitter's issuer: an https URL, the `iss` of every SET. */
  readonly issuer: string;
  /** Where the signer's public keys are published, e.g. `signingKeys.jwksResponse`. */
  readonly jwksUri: string;
  /** Signs the SETs: `signingKeys.signer({ type: "ssf", id: "transmitter" })`. */
  readonly signer: SetSigner;
  /**
   * Authenticates a management or poll request and names its receiver;
   * `null` answers 401. SSF requires the API to be authorized.
   */
  readonly authorize: (
    request: Request,
  ) => SsfReceiverIdentity | null | Promise<SsfReceiverIdentity | null>;
  /** The route prefix under the issuer's origin. Default: `/ssf`. */
  readonly basePath?: string;
  /** The event types receivers can request. Default: every CAEP and RISC type. */
  readonly eventsSupported?: readonly string[];
  /** Default: both. */
  readonly deliveryMethods?: readonly SsfDeliveryMethod[];
  /** Seconds between verification requests per stream. Default: 30. */
  readonly minVerificationInterval?: number;
  /** Keeps a push stream's `authorization_header` in Vault. Without it, such requests fail. */
  readonly credentials?: Pick<VaultCredentials, "set" | "revoke">;
  /** `authorization_schemes` in the metadata. Default: OAuth 2.0 (`urn:ietf:rfc:6749`). */
  readonly authorizationSchemes?: readonly { readonly spec_urn: string }[];
  /** The largest management request body, in bytes. Default: 64 KiB. */
  readonly maxBodyBytes?: number;
  /** `withBlockHooks` hooks around the transmitter's methods; the routes call through them. */
  readonly hooks?: NoInfer<BlockHooks<SsfTransmitter>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** An SSF 1.0 transmitter on the `shared-signals` module. */
export interface SsfTransmitter {
  /** The transmitter configuration metadata (SSF §7.1). */
  metadata(): Readonly<Record<string, unknown>>;
  createStream(input: CreateSsfStreamInput): AsyncResult<SsfStream>;
  stream(id: string): AsyncResult<SsfStream | null>;
  streams(receiver: string): AsyncResult<readonly SsfStream[]>;
  updateStream(
    id: string,
    input: UpdateSsfStreamInput,
  ): AsyncResult<SsfStream | null>;
  deleteStream(id: string): AsyncResult<boolean>;
  /**
   * Sets the status. Pausing or disabling sends `stream-updated` first;
   * enabling sends it after the held SETs.
   */
  setStatus(
    id: string,
    status: SsfStreamStatus,
    reason?: string,
  ): AsyncResult<SsfStreamStatus>;
  /** Sends a verification event (SSF §8.1.4). */
  verify(id: string, state?: string): AsyncResult<string>;
  /** Mints the event once per stream that delivers it and queues it. */
  emit(input: EmitSecurityEventInput): AsyncResult<EmitResult>;
  /** RFC 8936: acknowledges and returns SETs of a poll stream. */
  poll(id: string, request: SsfPollRequest): AsyncResult<SsfPollResponse>;
  /** Deletes replay entries and unpolled SETs past the retention. */
  purge(olderThan?: Temporal.Duration): AsyncResult<number>;
  /** The well-known metadata, stream management, status, verification and poll routes. */
  handler(): (request: Request) => Promise<Response>;
}

export interface SsfPollRequest {
  readonly maxEvents?: number;
  readonly ack?: readonly string[];
  readonly setErrs?: Readonly<
    Record<string, { readonly err: string; readonly description?: string }>
  >;
}

export interface SsfPollResponse {
  readonly sets: Readonly<Record<string, string>>;
  readonly moreAvailable: boolean;
}

const METHODS: Readonly<Record<SsfDeliveryMethod, string>> = {
  push: SSF_PUSH,
  poll: SSF_POLL,
};

const methodOf = (urn: unknown): SsfDeliveryMethod =>
  urn === SSF_PUSH ? "push" : "poll";

const STATUSES: readonly SsfStreamStatus[] = ["enabled", "paused", "disabled"];

const statusOf = (value: unknown): SsfStreamStatus => {
  const found = STATUSES.find((status) => status === value);
  if (found === undefined)
    throw new TypeError(`Unknown stream status ${String(value)}`);
  return found;
};

function streamOf(value: unknown): SsfStream {
  const row = recordOf(value, "ssf_stream");
  return {
    id: textOf(row["id"]),
    tenant: nullableText(row["tenant"]),
    receiver: textOf(row["receiver"]),
    audience: stringsOf(row["audience"]),
    description: nullableText(row["description"]),
    eventsRequested: stringsOf(row["eventsRequested"]),
    eventsDelivered: stringsOf(row["eventsDelivered"]),
    method: methodOf(row["method"]),
    endpointUrl: nullableText(row["endpointUrl"]),
    status: statusOf(row["status"]),
    reason: nullableText(row["reason"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

const interval = (seconds: number): string => `${String(seconds)} seconds`;

const invalid = (message: string): DbError =>
  dbError("invalid_input", message, { hint: "SSF_REQUEST_INVALID" });

const json = (
  body: unknown,
  status = 200,
  headers: Readonly<Record<string, string>> = {},
): Response => Response.json(body, { status, headers: noStore(headers) });

const noStore = (init: Readonly<Record<string, string>>): Headers => {
  const headers = new Headers(init);
  if (!headers.has("cache-control")) headers.set("cache-control", "no-store");
  return headers;
};

const strings = (value: unknown): readonly string[] | undefined =>
  Array.isArray(value) && value.every((item) => typeof item === "string")
    ? value
    : undefined;

/**
 * An SSF transmitter: streams and their status live in the `shared-signals`
 * module, push SETs go out through webhooks-out endpoints with format
 * `set`, and poll SETs wait in the module's queue. Service role only.
 */
export function createSsfTransmitter(
  options: SsfTransmitterOptions,
): SsfTransmitter {
  applyTemporal(options);
  const call = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const issuer = options.issuer.replace(/\/$/, "");
  const base = (options.basePath ?? "/ssf").replace(/\/$/, "");
  const url = (path: string): string => `${issuer}${base}${path}`;
  const supported = options.eventsSupported ?? [
    ...Object.values(CAEP_EVENTS),
    ...Object.values(RISC_EVENTS),
  ];
  const methods = options.deliveryMethods ?? ["push", "poll"];
  const minVerification = options.minVerificationInterval ?? 30;
  const maxBody = options.maxBodyBytes ?? 65_536;
  const delivered = (requested: readonly string[]): string[] =>
    requested.filter((type) => supported.includes(type));

  const queue = (
    stream: string,
    jti: string,
    token: string,
  ): AsyncResult<string> =>
    call("queue_ssf_set", { stream_id: stream, jti, token }, textOf);

  const send = (
    stream: string,
    audience: readonly string[],
    subject: SubjectIdentifier,
    event: SecurityEvent,
    txn?: string,
  ): AsyncResult<string> =>
    mintSet(options.signer, {
      issuer,
      audience,
      subject,
      event,
      ...(txn === undefined ? {} : { txn }),
    }).andThen(({ jti, token }) => queue(stream, jti, token));

  const streamSubject = (id: string): SubjectIdentifier => ({
    format: "opaque",
    id,
  });

  const stream: SsfTransmitter["stream"] = (id) =>
    call("ssf_stream", { id }, (value) =>
      value === null || value === undefined ? null : streamOf(value),
    );

  const createStream: SsfTransmitter["createStream"] = (input) =>
    AsyncResult.from(async (): Promise<Result<SsfStream>> => {
      if (!methods.includes(input.method))
        return err(
          invalid(`The delivery method ${input.method} is not supported`),
        );
      const id = crypto.randomUUID();
      const identity = input.receiver;
      const tenant = identity.tenant ?? null;
      const audience = identity.audience ?? identity.receiver;
      let credentialRef: CredentialRef | null = null;
      if (input.method === "push") {
        if (
          input.endpointUrl === undefined ||
          !/^https:\/\//i.test(input.endpointUrl)
        )
          return err(invalid("A push stream needs an https endpoint_url"));
        if (input.authorizationHeader !== undefined) {
          if (options.credentials === undefined)
            return err(
              invalid(
                "This transmitter does not accept an authorization_header",
              ),
            );
          credentialRef = {
            provider: "vault",
            secret: `ssf/${id}`,
            header: "authorization",
            scheme: null,
            ...(tenant === null ? {} : { tenant }),
          };
          const stored = await options.credentials.set(
            credentialRef,
            input.authorizationHeader,
          );
          if (!stored.ok) return stored;
        }
      }
      return call(
        "create_ssf_stream",
        {
          id,
          receiver: identity.receiver,
          tenant,
          audience: typeof audience === "string" ? [audience] : [...audience],
          delivery_method: METHODS[input.method],
          events_requested: [...input.eventsRequested],
          events_delivered: delivered(input.eventsRequested),
          description: input.description ?? null,
          endpoint_url:
            input.method === "push" ? (input.endpointUrl ?? null) : null,
          credential_ref: credentialRef,
        },
        streamOf,
      );
    });

  const setStatus: SsfTransmitter["setStatus"] = (id, status, reason) =>
    stream(id).andThen(async (found): Promise<Result<SsfStreamStatus>> => {
      if (found === null)
        return err(
          dbError("not_found", "Stream not found", {
            hint: "SSF_STREAM_NOT_FOUND",
          }),
        );
      const update = {
        type: SSF_EVENTS.streamUpdated,
        claims: { status, ...(reason === undefined ? {} : { reason }) },
      };
      if (found.status === "enabled" && status !== "enabled") {
        const sent = await send(id, found.audience, streamSubject(id), update);
        if (!sent.ok) return sent;
      }
      const previous = await call(
        "set_ssf_stream_status",
        { id, status, reason: reason ?? null },
        statusOf,
      );
      if (!previous.ok) return previous;
      if (status === "enabled" && previous.data !== "enabled") {
        const sent = await send(id, found.audience, streamSubject(id), update);
        if (!sent.ok) return sent;
      }
      return ok(previous.data);
    });

  const verify: SsfTransmitter["verify"] = (id, state) =>
    stream(id).andThen((found) =>
      found === null
        ? AsyncResult.err<string>(
            dbError("not_found", "Stream not found", {
              hint: "SSF_STREAM_NOT_FOUND",
            }),
          )
        : send(id, found.audience, streamSubject(id), {
            type: SSF_EVENTS.verification,
            claims: state === undefined ? {} : { state },
          }),
    );

  const emit: SsfTransmitter["emit"] = (input) =>
    call(
      "ssf_streams_for_event",
      { tenant: input.tenant ?? null, event_type: input.event.type },
      (value) =>
        recordsOf(value, "ssf_streams_for_event").map((row) => ({
          id: textOf(row["id"]),
          audience: stringsOf(row["audience"]),
        })),
    ).andThen(async (targets): Promise<Result<EmitResult>> => {
      const counts = { dispatched: 0, queued: 0, held: 0 };
      for (const target of targets) {
        const sent = await send(
          target.id,
          target.audience,
          input.subject,
          input.event,
          input.txn,
        );
        if (!sent.ok) return sent;
        if (
          sent.data === "dispatched" ||
          sent.data === "queued" ||
          sent.data === "held"
        )
          counts[sent.data] += 1;
      }
      return ok({ streams: targets.length, ...counts });
    });

  const poll: SsfTransmitter["poll"] = (id, request) =>
    call(
      "poll_ssf_events",
      {
        stream_id: id,
        max_events: request.maxEvents ?? null,
        ack: [...(request.ack ?? [])],
        errors: request.setErrs ?? {},
      },
      (value) => {
        const row = recordOf(value, "poll_ssf_events");
        const sets = isRecord(row["sets"]) ? row["sets"] : {};
        return {
          sets: Object.fromEntries(
            Object.entries(sets).map(([jti, token]) => [jti, textOf(token)]),
          ),
          moreAvailable: row["moreAvailable"] === true,
        };
      },
    );

  const transmitter: SsfTransmitter = {
    metadata: () => ({
      spec_version: "1_0",
      issuer,
      jwks_uri: options.jwksUri,
      delivery_methods_supported: methods.map((method) => METHODS[method]),
      configuration_endpoint: url("/stream"),
      status_endpoint: url("/status"),
      verification_endpoint: url("/verify"),
      authorization_schemes: options.authorizationSchemes ?? [
        { spec_urn: "urn:ietf:rfc:6749" },
      ],
      default_subjects: "ALL",
    }),
    createStream,
    stream,
    streams: (receiver) =>
      call("ssf_streams", { receiver }, (value) =>
        recordsOf(value, "ssf_streams").map(streamOf),
      ),
    updateStream: (id, input) =>
      call(
        "update_ssf_stream",
        {
          id,
          patch: {
            ...(input.description === undefined
              ? {}
              : { description: input.description }),
            ...(input.eventsRequested === undefined
              ? {}
              : {
                  eventsRequested: input.eventsRequested,
                  eventsDelivered: delivered(input.eventsRequested),
                }),
            ...(input.endpointUrl === undefined
              ? {}
              : { endpointUrl: input.endpointUrl }),
          },
        },
        (value) =>
          value === null || value === undefined ? null : streamOf(value),
      ),
    deleteStream: (id) =>
      stream(id).andThen(async (found): Promise<Result<boolean>> => {
        if (found === null) return ok(false);
        const deleted = await call(
          "delete_ssf_stream",
          { id },
          (value) => value === true,
        );
        if (
          deleted.ok &&
          found.method === "push" &&
          options.credentials !== undefined
        ) {
          await options.credentials.revoke(
            {
              provider: "vault",
              secret: `ssf/${id}`,
              ...(found.tenant === null ? {} : { tenant: found.tenant }),
            },
            { subject: { type: "app" } },
          );
        }
        return deleted;
      }),
    setStatus,
    verify,
    emit,
    poll,
    purge: (olderThan) =>
      call(
        "purge_shared_signals",
        {
          older_than:
            olderThan === undefined
              ? null
              : interval(olderThan.total({ unit: "seconds" })),
        },
        Number,
      ),
    handler: () =>
      routes(hooked, {
        base,
        authorize: options.authorize,
        maxBody,
        minVerification,
        call,
        supported,
      }),
  };
  const hooked = withBlockHooks(transmitter, options.hooks, {
    block: "shared-signals",
    ...(options.logger ? { logger: options.logger } : {}),
  });
  return hooked;
}

interface RouteContext {
  readonly base: string;
  readonly authorize: SsfTransmitterOptions["authorize"];
  readonly maxBody: number;
  readonly minVerification: number;
  readonly call: ReturnType<typeof blockCall>;
  readonly supported: readonly string[];
}

const failure = (error: DbError): Response => problemResponse(error);

const unauthorized = (): Response =>
  failure(
    dbError("unauthorized", "The request is not authorized", {
      hint: "SSF_UNAUTHORIZED",
    }),
  );

const notFound = (): Response =>
  failure(
    dbError("not_found", "Stream not found", { hint: "SSF_STREAM_NOT_FOUND" }),
  );

async function bodyOf(
  request: Request,
  limit: number,
): Promise<Record<string, unknown> | undefined> {
  const text = await readBodyCapped(request, limit);
  if (text === undefined || text === "") return undefined;
  try {
    const value: unknown = JSON.parse(text);
    return isRecord(value) ? value : undefined;
  } catch {
    return undefined;
  }
}

function configOf(
  stream: SsfStream,
  issuer: string,
  supported: readonly string[],
  minVerification: number,
  pollUrl: string,
): Record<string, unknown> {
  return {
    stream_id: stream.id,
    iss: issuer,
    aud: stream.audience.length === 1 ? stream.audience[0] : stream.audience,
    events_supported: supported,
    events_requested: stream.eventsRequested,
    events_delivered: stream.eventsDelivered,
    delivery: {
      method: METHODS[stream.method],
      endpoint_url: stream.method === "push" ? stream.endpointUrl : pollUrl,
    },
    min_verification_interval: minVerification,
    ...(stream.description === null ? {} : { description: stream.description }),
  };
}

function routes(
  transmitter: SsfTransmitter,
  context: RouteContext,
): (request: Request) => Promise<Response> {
  const metadata = transmitter.metadata();
  const issuer = textOf(metadata["issuer"]);
  const pollUrl = (id: string): string => `${issuer}${context.base}/poll/${id}`;
  const config = (stream: SsfStream): Record<string, unknown> =>
    configOf(
      stream,
      issuer,
      context.supported,
      context.minVerification,
      pollUrl(stream.id),
    );

  /** The stream when it belongs to the receiver; another receiver's stream is a 404. */
  const owned = async (
    id: string | null | undefined,
    identity: SsfReceiverIdentity,
  ): Promise<SsfStream | Response> => {
    if (typeof id !== "string" || id === "")
      return failure(invalid("stream_id is required"));
    if (!/^[0-9a-f-]{36}$/i.test(id)) return notFound();
    const found = await transmitter.stream(id);
    if (!found.ok) return failure(found.error);
    if (found.data === null || found.data.receiver !== identity.receiver)
      return notFound();
    return found.data;
  };

  const manage = async (
    request: Request,
    identity: SsfReceiverIdentity,
  ): Promise<Response> => {
    const query = new URL(request.url).searchParams;
    switch (request.method) {
      case "GET": {
        const id = query.get("stream_id");
        if (id === null) {
          const all = await transmitter.streams(identity.receiver);
          return all.ok ? json(all.data.map(config)) : failure(all.error);
        }
        const found = await owned(id, identity);
        return found instanceof Response ? found : json(config(found));
      }
      case "POST": {
        const body = await bodyOf(request, context.maxBody);
        const delivery = isRecord(body?.["delivery"]) ? body["delivery"] : {};
        const method =
          delivery["method"] === SSF_PUSH
            ? "push"
            : delivery["method"] === SSF_POLL
              ? "poll"
              : undefined;
        const requested = strings(body?.["events_requested"]) ?? [];
        if (body === undefined || method === undefined)
          return failure(
            invalid("delivery.method must be a supported delivery method"),
          );
        const endpoint = delivery["endpoint_url"];
        const authorization = delivery["authorization_header"];
        const created = await transmitter.createStream({
          receiver: identity,
          method,
          eventsRequested: requested,
          ...(typeof endpoint === "string" ? { endpointUrl: endpoint } : {}),
          ...(typeof authorization === "string"
            ? { authorizationHeader: authorization }
            : {}),
          ...(typeof body["description"] === "string"
            ? { description: body["description"] }
            : {}),
        });
        return created.ok
          ? json(config(created.data), 201)
          : failure(created.error);
      }
      case "PATCH":
      case "PUT": {
        const body = await bodyOf(request, context.maxBody);
        if (body === undefined)
          return failure(invalid("The body must be a stream configuration"));
        const found = await owned(textOf(body["stream_id"] ?? ""), identity);
        if (found instanceof Response) return found;
        const replace = request.method === "PUT";
        const delivery = isRecord(body["delivery"])
          ? body["delivery"]
          : undefined;
        if (
          delivery?.["method"] !== undefined &&
          delivery["method"] !== METHODS[found.method]
        )
          return failure(
            invalid("The delivery method of a stream can't change"),
          );
        const requested = strings(body["events_requested"]);
        const endpoint = delivery?.["endpoint_url"];
        const description = body["description"];
        const updated = await transmitter.updateStream(found.id, {
          ...(typeof description === "string"
            ? { description }
            : replace
              ? { description: null }
              : {}),
          ...(requested === undefined
            ? replace
              ? { eventsRequested: [] }
              : {}
            : { eventsRequested: requested }),
          ...(found.method === "push" && typeof endpoint === "string"
            ? { endpointUrl: endpoint }
            : {}),
        });
        if (!updated.ok) return failure(updated.error);
        return updated.data === null ? notFound() : json(config(updated.data));
      }
      case "DELETE": {
        const found = await owned(query.get("stream_id"), identity);
        if (found instanceof Response) return found;
        const deleted = await transmitter.deleteStream(found.id);
        return deleted.ok
          ? new Response(null, { status: 204 })
          : failure(deleted.error);
      }
      default:
        return new Response(null, {
          status: 405,
          headers: { allow: "GET, POST, PATCH, PUT, DELETE" },
        });
    }
  };

  const status = async (
    request: Request,
    identity: SsfReceiverIdentity,
  ): Promise<Response> => {
    if (request.method === "GET") {
      const found = await owned(
        new URL(request.url).searchParams.get("stream_id"),
        identity,
      );
      if (found instanceof Response) return found;
      return json({
        stream_id: found.id,
        status: found.status,
        ...(found.reason === null ? {} : { reason: found.reason }),
      });
    }
    if (request.method !== "POST")
      return new Response(null, {
        status: 405,
        headers: { allow: "GET, POST" },
      });
    const body = await bodyOf(request, context.maxBody);
    const found = await owned(
      typeof body?.["stream_id"] === "string" ? body["stream_id"] : undefined,
      identity,
    );
    if (found instanceof Response) return found;
    const next = STATUSES.find((value) => value === body?.["status"]);
    if (next === undefined)
      return failure(invalid("status is enabled, paused or disabled"));
    const reason =
      typeof body?.["reason"] === "string" ? body["reason"] : undefined;
    const changed = await transmitter.setStatus(found.id, next, reason);
    if (!changed.ok) return failure(changed.error);
    return json({
      stream_id: found.id,
      status: next,
      ...(reason === undefined ? {} : { reason }),
    });
  };

  const verification = async (
    request: Request,
    identity: SsfReceiverIdentity,
  ): Promise<Response> => {
    if (request.method !== "POST")
      return new Response(null, { status: 405, headers: { allow: "POST" } });
    const body = await bodyOf(request, context.maxBody);
    const found = await owned(
      typeof body?.["stream_id"] === "string" ? body["stream_id"] : undefined,
      identity,
    );
    if (found instanceof Response) return found;
    const noted = await context.call(
      "note_ssf_verification",
      { stream_id: found.id, min_interval: interval(context.minVerification) },
      (value) => value === true,
    );
    if (!noted.ok) return failure(noted.error);
    if (!noted.data)
      return new Response(null, {
        status: 429,
        headers: { "retry-after": String(context.minVerification) },
      });
    const state = body?.["state"];
    const sent = await transmitter.verify(
      found.id,
      typeof state === "string" ? state : undefined,
    );
    return sent.ok ? new Response(null, { status: 204 }) : failure(sent.error);
  };

  const pollRoute = async (
    request: Request,
    identity: SsfReceiverIdentity,
    id: string,
  ): Promise<Response> => {
    if (request.method !== "POST")
      return new Response(null, { status: 405, headers: { allow: "POST" } });
    const found = await owned(id, identity);
    if (found instanceof Response) return found;
    if (found.method !== "poll") return notFound();
    const body = (await bodyOf(request, context.maxBody)) ?? {};
    const max = body["maxEvents"];
    const errs = isRecord(body["setErrs"]) ? body["setErrs"] : {};
    const polled = await transmitter.poll(found.id, {
      ...(typeof max === "number" ? { maxEvents: max } : {}),
      ack: strings(body["ack"]) ?? [],
      setErrs: Object.fromEntries(
        Object.entries(errs).flatMap(([jti, value]) =>
          isRecord(value) && typeof value["err"] === "string"
            ? [[jti, { err: value["err"] }]]
            : [],
        ),
      ),
    });
    return polled.ok ? json(polled.data) : failure(polled.error);
  };

  return async (request) => {
    const path = new URL(request.url).pathname;
    if (path.includes("/.well-known/ssf-configuration")) {
      return request.method === "GET"
        ? json(metadata, 200, { "cache-control": "public, max-age=300" })
        : new Response(null, { status: 405, headers: { allow: "GET" } });
    }
    const route = path.startsWith(context.base)
      ? path.slice(context.base.length)
      : undefined;
    if (route === undefined) return notFound();
    const identity = await context.authorize(request);
    if (identity === null) return unauthorized();
    if (route === "/stream") return manage(request, identity);
    if (route === "/status") return status(request, identity);
    if (route === "/verify") return verification(request, identity);
    if (route.startsWith("/poll/"))
      return pollRoute(request, identity, route.slice(6));
    return notFound();
  };
}
