import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AuthState } from "../auth/resolve.ts";
import type { DbError, DbErrorKind } from "../core/errors.ts";
import type { ProblemFormat } from "../core/problem.ts";
import type { SqlClient } from "../postgres/executor.ts";
import type { Subscriber } from "../realtime/channels.ts";
import type { RealtimeClient, SubscriptionStatus } from "../realtime/topic.ts";
import type { ActiveSupport } from "./support.ts";

import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { validate } from "../core/standard.ts";
import { joinTopic } from "../realtime/channels.ts";

/**
 * A topic the relay serves: a `defineTopic(...)` topic, or `liveRelayTopic` for
 * the `realtime-tables` channels behind `liveQuery` and `useLiveQuery`.
 */
export interface RelayTopic {
  readonly private: boolean;
  /** Join with presence, so members' states reach the client. */
  readonly presence?: boolean;
  /** Whether clients may broadcast on it (`defineTopic`'s `send` option). */
  readonly clientSend?: boolean;
  /** Payload schemas per event; a send through the relay is validated. */
  readonly events?: Readonly<Record<string, StandardSchemaV1>>;
  /** Anything but `null` when `topic` is one of this topic's names. */
  match(topic: string): unknown;
}

/** The channels `liveQuery` joins: `bsb:t:<schema>.<table>[:...]`, private. */
export const liveRelayTopic: RelayTopic = {
  private: true,
  match: (topic) => (/^bsb:t:[^:]+\.[^:]+(?::.+)?$/.test(topic) ? {} : null),
};

/** What `authorize` decides on. */
export interface RelayAccessInput {
  readonly topic: string;
  readonly action: "receive" | "send";
  /** The caller: in a support session, the viewed user. */
  readonly auth: AuthState;
  readonly support: ActiveSupport | undefined;
  /** The claims the check runs with: the target's in a support session. */
  readonly claims: Readonly<Record<string, unknown>>;
}

/**
 * Decides whether the caller may receive or send on a topic. A throw or
 * rejection is a failure that may pass: a join ends with `unavailable` and the
 * client retries, a send answers 503.
 */
export type RelayAuthorize = (
  input: RelayAccessInput,
) => boolean | PromiseLike<boolean>;

/**
 * The part of a server the relay uses: `createServer`, `createNext` and the
 * other adapters fit.
 */
export interface RelayServer {
  context(
    request: Request,
    options?: { readonly refresh?: boolean },
  ): Promise<{
    readonly auth: AuthState;
    readonly resolution: { readonly auth: AuthState };
    readonly support?: ActiveSupport;
    apply(response: Response): Response;
  }>;
  admin(): { readonly $client: RealtimeClient };
}

/** A pool that runs a function in one transaction: `createPostgres()`. */
export interface RelayPostgres {
  transaction<T>(fn: (client: SqlClient) => Promise<T>): Promise<T>;
}

export interface RealtimeRelayOptions {
  /** The topics the relay serves; any other name answers 404. */
  readonly topics: readonly RelayTopic[];
  /**
   * Checks each join and send against the `realtime.messages` policies, run as
   * the caller (the viewed user in a support session) the way Realtime checks a
   * browser's join. Needs a pool whose role may assume `authenticated`, such as
   * `createPostgres()`.
   */
  readonly postgres?: RelayPostgres;
  /** Decides access instead of the policies. */
  readonly authorize?: RelayAuthorize;
  /**
   * The client that joins upstream. Defaults to the server's secret-key client
   * (`server.admin().$client`); joins of a topic share one channel per
   * process.
   */
  readonly upstream?: RealtimeClient;
  /** Milliseconds between keep-alive comments. Defaults to 25000. */
  readonly heartbeatMs?: number;
  /**
   * Milliseconds a stream stays open before it ends with `max_duration` and the
   * client reconnects, which checks access again. Defaults to 240000, under
   * common serverless limits.
   */
  readonly maxDurationMs?: number;
  /**
   * Events a slow client may fall behind by before its stream ends with
   * `overflow`; the reconnect reports a rejoin, so the client refetches.
   * Defaults to 256.
   */
  readonly maxQueued?: number;
  /** Milliseconds the client waits before reconnecting. Defaults to 1000. */
  readonly retryMs?: number;
  /**
   * Refresh an expiring session cookie and send the new cookies. Defaults to
   * false: the proxy refreshes, and an expired session answers 401.
   */
  readonly refresh?: boolean;
  readonly problem?: ProblemFormat;
}

/** Why the relay ended a stream, in its `end` event. */
export type RelayEndReason =
  | "expired"
  | "max_duration"
  | "overflow"
  | "closed"
  | "upstream_error"
  | "unavailable";

class Verdict extends Error {
  readonly allowed: boolean;

  constructor(allowed: boolean) {
    super(allowed ? "allowed" : "denied");
    this.allowed = allowed;
  }
}

const RLS_DENIED = "42501";

function codeOf(cause: unknown): unknown {
  return typeof cause === "object" && cause !== null && "code" in cause
    ? cause.code
    : undefined;
}

/**
 * Whether `claims` may receive or send on `topic`, by the `realtime.messages`
 * policies, checked the way Realtime checks a join: a probe message is
 * inserted, then read (receive) or written (send) as the caller, and the
 * transaction rolls back.
 */
export async function realtimeTopicAccess(
  postgres: RelayPostgres,
  input: {
    readonly claims: Readonly<Record<string, unknown>>;
    readonly topic: string;
    readonly action: "receive" | "send";
    readonly extension?: "broadcast" | "presence";
  },
): Promise<boolean> {
  const role = input.claims["role"] === "anon" ? "anon" : "authenticated";
  const sub = input.claims["sub"];
  const extension = input.extension ?? "broadcast";

  const insert =
    "insert into realtime.messages (topic, extension, event, payload, private) values ($1, $2, 'bsb_relay_probe', '{}'::jsonb, true)";

  const assume = async (sql: SqlClient): Promise<void> => {
    await sql.queryRaw(
      "select set_config('request.jwt.claims', $1, true), set_config('request.jwt.claim.sub', $2, true), set_config('request.jwt.claim.role', $3, true), set_config('realtime.topic', $4, true), set_config('role', $3, true)",
      [
        JSON.stringify({ ...input.claims, role }),
        typeof sub === "string" ? sub : "",
        role,
        input.topic,
      ],
    );
  };

  try {
    await postgres.transaction(async (sql) => {
      if (input.action === "receive") {
        const [probe] = await sql.queryRaw<{ id: string }>(
          `${insert} returning id::text as id`,
          [input.topic, extension],
        );

        await assume(sql);

        const [row] = await sql.queryRaw<{ allowed: boolean }>(
          "select exists (select 1 from realtime.messages m where m.id::text = $1) as allowed",
          [probe?.id ?? ""],
        );

        throw new Verdict(row?.allowed === true);
      }

      await assume(sql);

      try {
        await sql.queryRaw(insert, [input.topic, extension]);
      } catch (cause) {
        if (codeOf(cause) === RLS_DENIED) {
          throw new Verdict(false);
        }

        throw cause;
      }

      throw new Verdict(true);
    });
  } catch (cause) {
    if (cause instanceof Verdict) {
      return cause.allowed;
    }

    throw cause;
  }

  return false;
}

const encoder = new TextEncoder();

const frame = (event: string, data: unknown): Uint8Array =>
  encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);

const PING = encoder.encode(": ping\n\n");

const TRANSIENT_AUTH: ReadonlySet<DbErrorKind> = new Set([
  "network",
  "unexpected",
]);

const STREAM_HEADERS = {
  "content-type": "text/event-stream; charset=utf-8",
  "cache-control": "no-store, no-transform",
  "x-accel-buffering": "no",
};

function readOnlyError(): DbError {
  return {
    ...dbError("forbidden", "The support session is read-only"),
    code: "SUPPORT_READ_ONLY",
  };
}

interface SendBody {
  readonly topic: string;
  readonly event: string;
  readonly payload: unknown;
}

function isSendBody(value: unknown): value is SendBody {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const body: Partial<Record<keyof SendBody, unknown>> = value;

  return (
    typeof body.topic === "string" &&
    typeof body.event === "string" &&
    body.event !== ""
  );
}

/**
 * Realtime for callers without a browser token of their own: a support session
 * ("view as user"), or an app that keeps sessions in httpOnly cookies. `GET
 * ?topic=<name>` resolves the caller, checks the topic's access as that caller
 * (the viewed user in a support session), joins upstream with the secret key
 * and streams the topic's broadcasts and presence as server-sent events. `POST
 * { topic, event, payload }` broadcasts for the caller after the same check on
 * the send policy; read-only support sessions can't send.
 * `relayRealtimeClient(url)` from `better-supabase/realtime` is the client.
 *
 * ```ts
 * // app/api/realtime/route.ts
 * export const { GET, POST } = realtimeRelay(bsb, {
 *   topics: [notifications, liveRelayTopic],
 *   postgres,
 * });
 * ```
 */
export function realtimeRelay(
  server: RelayServer,
  options: RealtimeRelayOptions,
): {
  readonly GET: (request: Request) => Promise<Response>;
  readonly POST: (request: Request) => Promise<Response>;
} {
  const { postgres, authorize } = options;

  if (!postgres && !authorize) {
    throw new TypeError(
      "realtimeRelay needs `postgres` to check the realtime.messages policies, or `authorize`",
    );
  }

  const heartbeatMs = options.heartbeatMs ?? 25_000;
  const maxDurationMs = options.maxDurationMs ?? 240_000;
  const maxQueued = Math.max(1, options.maxQueued ?? 256);
  const retryMs = options.retryMs ?? 1000;
  const refresh = options.refresh ?? false;
  let upstream = options.upstream;

  const upstreamClient = (): RealtimeClient => {
    upstream ??= server.admin().$client;

    return upstream;
  };

  const problem = (error: DbError): Response =>
    problemResponse(error, { format: options.problem });

  const unavailableStream = (): Response =>
    new Response(
      `retry: ${String(retryMs)}\n\nevent: end\ndata: ${JSON.stringify({ reason: "unavailable" })}\n\n`,
      { status: 200, headers: STREAM_HEADERS },
    );

  const topicOf = (name: string): RelayTopic | undefined =>
    options.topics.find((each) => each.match(name) !== null);

  const allowed = async (
    input: RelayAccessInput,
  ): Promise<boolean | "unavailable"> => {
    try {
      if (authorize) {
        return await authorize(input);
      }

      if (input.auth.kind === "secret") {
        return true;
      }

      return postgres
        ? await realtimeTopicAccess(postgres, {
            claims: input.claims,
            topic: input.topic,
            action: input.action,
          })
        : false;
    } catch {
      return "unavailable";
    }
  };

  const claimsOf = (
    auth: AuthState,
    support: ActiveSupport | undefined,
  ): Readonly<Record<string, unknown>> => {
    if (support) {
      return support.claims;
    }

    switch (auth.kind) {
      case "user": {
        return auth.claims;
      }

      case "apiKey": {
        return auth.claims;
      }

      case "none": {
        return { role: "anon" };
      }

      case "secret": {
        return { role: "service_role" };
      }

      case "invalid": {
        return { role: "anon" };
      }

      default: {
        const unknown: never = auth;

        return unknown;
      }
    }
  };

  /** Resolves the caller and checks `action` on `name`; a Response refuses. */
  const admit = async (
    request: Request,
    name: string,
    action: "receive" | "send",
  ) => {
    const topic = topicOf(name);

    if (!topic) {
      return {
        refusal: problem(dbError("not_found", `No relayed topic "${name}"`)),
      };
    }

    const ctx = await server.context(request, { refresh });
    const { auth, support } = ctx;

    if (auth.kind === "invalid") {
      return {
        refusal: ctx.apply(
          action === "receive" && TRANSIENT_AUTH.has(auth.error.kind)
            ? unavailableStream()
            : problem(auth.error),
        ),
      };
    }

    const signedIn = auth.kind !== "none";

    if (!signedIn && (topic.private || action === "send")) {
      return {
        refusal: ctx.apply(
          problem(dbError("unauthorized", "Sign in to join this topic")),
        ),
      };
    }

    if (action === "send" && support?.session.readOnly === true) {
      return { refusal: ctx.apply(problem(readOnlyError())) };
    }

    const ok =
      !topic.private && action === "receive"
        ? true
        : await allowed({
            topic: name,
            action,
            auth,
            support,
            claims: claimsOf(auth, support),
          });

    if (ok === "unavailable") {
      return {
        refusal: ctx.apply(
          action === "receive"
            ? unavailableStream()
            : problem(
                dbError("network", `Could not check access to "${name}"`),
              ),
        ),
      };
    }

    if (!ok) {
      return {
        refusal: ctx.apply(
          problem(
            dbError("forbidden", `Not allowed to ${action} on "${name}"`),
          ),
        ),
      };
    }

    return { topic, ctx };
  };

  const expiryOf = (
    auth: AuthState,
    support: ActiveSupport | undefined,
  ): number | undefined => {
    const times: number[] = [];

    if (auth.kind === "user" && auth.expiresAt !== null) {
      times.push(auth.expiresAt * 1000);
    }

    if (support) {
      times.push(support.session.expiresAt.epochMilliseconds);
    }

    return times.length === 0 ? undefined : Math.min(...times);
  };

  const GET = async (request: Request): Promise<Response> => {
    const name = new URL(request.url).searchParams.get("topic");

    if (!name) {
      return problem(dbError("invalid_request", "Pass ?topic=<name>"));
    }

    const admitted = await admit(request, name, "receive");

    if ("refusal" in admitted) {
      return admitted.refusal;
    }

    const { topic, ctx } = admitted;
    const expiresAt = expiryOf(ctx.resolution.auth, ctx.support);
    const client = upstreamClient();
    let finish: (reason: RelayEndReason | null) => void = () => undefined;

    const stream = new ReadableStream<Uint8Array>(
      {
        start(controller) {
          let closed = false;
          let subscribed = false;
          let leave: (() => Promise<void>) | undefined;
          const timers: ReturnType<typeof setTimeout>[] = [];

          const enqueue = (chunk: Uint8Array): void => {
            try {
              controller.enqueue(chunk);
            } catch {
              finish(null);
            }
          };

          const push = (chunk: Uint8Array): void => {
            if (closed) {
              return;
            }

            if ((controller.desiredSize ?? 1) <= 0) {
              finish("overflow");

              return;
            }

            enqueue(chunk);
          };

          finish = (reason) => {
            if (closed) {
              return;
            }

            closed = true;

            for (const timer of timers) {
              clearTimeout(timer);
              clearInterval(timer);
            }

            request.signal.removeEventListener("abort", aborted);
            void leave?.();

            if (reason !== null) {
              enqueue(frame("end", { reason }));
            }

            try {
              controller.close();
            } catch {
              // The client already went away.
            }
          };

          const aborted = (): void => {
            finish(null);
          };

          const onStatus = (status: SubscriptionStatus): void => {
            switch (status) {
              case "joining": {
                return;
              }

              case "subscribed": {
                push(frame("status", { status, rejoin: subscribed }));
                subscribed = true;

                return;
              }

              case "error": {
                if (subscribed) {
                  push(frame("status", { status }));
                } else {
                  finish("upstream_error");
                }

                return;
              }

              case "closed": {
                finish("closed");

                return;
              }

              default: {
                const unknown: never = status;
                finish(unknown);
              }
            }
          };

          const subscriber: Subscriber = {
            onStatus,
            receive: (message) => {
              push(
                frame("broadcast", {
                  event: message.event,
                  payload: message.payload,
                }),
              );
            },
            ...(topic.presence
              ? {
                  sync: (state) => {
                    push(frame("presence", state));
                  },
                }
              : {}),
          };

          enqueue(encoder.encode(`retry: ${String(retryMs)}\n\n`));

          if (request.signal.aborted) {
            finish(null);

            return;
          }

          request.signal.addEventListener("abort", aborted);

          timers.push(
            setInterval(() => {
              push(PING);
            }, heartbeatMs),
            setTimeout(() => {
              finish("max_duration");
            }, maxDurationMs),
          );

          if (expiresAt !== undefined) {
            timers.push(
              setTimeout(
                () => {
                  finish("expired");
                },
                Math.max(0, expiresAt - Date.now()),
              ),
            );
          }

          try {
            leave = joinTopic(
              client,
              name,
              topic.private,
              false,
              topic.presence === true,
              subscriber,
            ).leave;
          } catch {
            finish("upstream_error");
          }
        },
        cancel() {
          finish(null);
        },
      },
      new CountQueuingStrategy({ highWaterMark: maxQueued }),
    );

    return ctx.apply(
      new Response(stream, { status: 200, headers: STREAM_HEADERS }),
    );
  };

  const POST = async (request: Request): Promise<Response> => {
    const body: unknown = await request.json().catch(() => undefined);

    if (!isSendBody(body)) {
      return problem(
        dbError(
          "invalid_request",
          "Send a JSON body with `topic`, `event` and `payload`",
        ),
      );
    }

    const known = topicOf(body.topic);

    if (known && !known.clientSend) {
      return problem(
        dbError("forbidden", `"${body.topic}" takes no client broadcasts`),
      );
    }

    const admitted = await admit(request, body.topic, "send");

    if ("refusal" in admitted) {
      return admitted.refusal;
    }

    const { topic, ctx } = admitted;
    const schema = topic.events?.[body.event];

    const checked = schema
      ? await validate(schema, body.payload, "payload")
      : { ok: true as const, data: body.payload };

    if (!checked.ok) {
      return ctx.apply(problem(checked.error));
    }

    const client = upstreamClient();

    const open = client
      .getChannels()
      .some((existing) => existing.topic === `realtime:${body.topic}`);

    const channel = client.channel(body.topic, {
      config: { private: topic.private },
    });

    try {
      const sent = await channel.httpSend(body.event, checked.data);

      return ctx.apply(
        sent.success
          ? new Response(null, { status: 202 })
          : problem(dbError("network", sent.error)),
      );
    } finally {
      if (!open) {
        await client.removeChannel(channel);
      }
    }
  };

  return { GET, POST };
}
