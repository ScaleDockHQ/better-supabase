import type { SetSigner } from "../../../src/blocks/shared-signals/set.ts";
import type { Jwks } from "../../../src/core/jws.ts";

import {
  SSF_POLL,
  SSF_PUSH,
} from "../../../src/blocks/shared-signals/methods.ts";
import {
  generateSigningKey,
  importSigningKey,
  signCompact,
} from "../../../src/core/jws.ts";
import { AsyncResult, ok } from "../../../src/core/result.ts";

/** An Ed25519 signer and the JWKS that verifies it. */
export async function signingKey(): Promise<{
  readonly signer: SetSigner;
  readonly jwks: Jwks;
}> {
  const { kid, publicKey, privateKey } = await generateSigningKey("Ed25519");
  const key = await importSigningKey(privateKey);
  return {
    signer: {
      signJwt: (claims, header) =>
        AsyncResult.from(async () =>
          ok(
            await signCompact(
              key,
              "Ed25519",
              { alg: "EdDSA", kid, typ: "JWT", ...header },
              claims,
            ),
          ),
        ),
    },
    jwks: { keys: [{ ...publicKey, kid, use: "sig" }] },
  };
}

interface Stream {
  id: string;
  tenant: string | null;
  receiver: string;
  audience: string[];
  description: string | null;
  eventsRequested: string[];
  eventsDelivered: string[];
  method: string;
  endpointUrl: string | null;
  endpointEnabled: boolean;
  status: string;
  reason: string | null;
  verifiedAt: number | null;
  createdAt: string;
  updatedAt: string;
}

type Args = Record<string, unknown>;

const strs = (value: unknown): string[] =>
  Array.isArray(value) ? value.map(String) : [];
const textOrNull = (value: unknown): string | null =>
  typeof value === "string" ? value : null;
const recordOf = (value: unknown): Args =>
  typeof value === "object" && value !== null ? { ...value } : {};

export interface Store {
  readonly streams: Stream[];
  readonly queued: { stream: string; jti: string; token: string }[];
  readonly received: Set<string>;
  readonly dispatched: { endpoint: string; jti: string; set: string }[];
  readonly calls: [string, Args][];
  call(schema: string, fn: string, args: Args): Promise<unknown>;
}

/** The shared-signals module in memory, with webhooks-out dispatch recorded. */
export function store(): Store {
  const streams: Stream[] = [];
  const queued: { stream: string; jti: string; token: string }[] = [];
  const received = new Set<string>();
  const dispatched: { endpoint: string; jti: string; set: string }[] = [];
  const calls: [string, Args][] = [];
  const json = (s: Stream) => {
    const { endpointEnabled: _e, verifiedAt: _v, ...rest } = s;
    return rest;
  };
  const find = (id: unknown) => streams.find((s) => s.id === id);
  const dispatch = (s: Stream, jti: string, token: string) =>
    dispatched.push({ endpoint: s.id, jti, set: token });
  const fns: Record<string, (args: Args) => unknown> = {
    create_ssf_stream(args) {
      const now = new Date().toISOString();
      if (args["delivery_method"] === SSF_PUSH && !args["endpoint_url"]) {
        throw new Error("SSF_ENDPOINT_REQUIRED");
      }
      const s: Stream = {
        id: String(args["id"]),
        tenant: textOrNull(args["tenant"]),
        receiver: String(args["receiver"]),
        audience: strs(args["audience"]),
        description: textOrNull(args["description"]),
        eventsRequested: strs(args["events_requested"]),
        eventsDelivered: strs(args["events_delivered"]),
        method: String(args["delivery_method"]),
        endpointUrl: textOrNull(args["endpoint_url"]),
        endpointEnabled: true,
        status: "enabled",
        reason: null,
        verifiedAt: null,
        createdAt: now,
        updatedAt: now,
      };
      streams.push(s);
      return json(s);
    },
    ssf_stream: (args) => {
      const s = find(args["id"]);
      return s ? json(s) : null;
    },
    ssf_streams: (args) =>
      streams.filter((s) => s.receiver === args["receiver"]).map(json),
    update_ssf_stream(args) {
      const s = find(args["id"]);
      if (!s) {
        return null;
      }
      const patch = recordOf(args["patch"]);
      if ("description" in patch) {
        s.description = textOrNull(patch["description"]);
      }
      if ("eventsRequested" in patch) {
        s.eventsRequested = strs(patch["eventsRequested"]);
      }
      if ("eventsDelivered" in patch) {
        s.eventsDelivered = strs(patch["eventsDelivered"]);
      }
      if ("endpointUrl" in patch && s.endpointUrl !== null) {
        s.endpointUrl = String(patch["endpointUrl"]);
      }
      return json(s);
    },
    delete_ssf_stream(args) {
      const index = streams.findIndex((s) => s.id === args["id"]);
      if (index === -1) {
        return false;
      }
      streams.splice(index, 1);
      return true;
    },
    queue_ssf_set(args) {
      const s = find(args["stream_id"])!;
      const jti = String(args["jti"]);
      const token = String(args["token"]);
      if (s.status === "disabled") {
        return "dropped";
      }
      if (
        s.method === SSF_PUSH &&
        s.status === "enabled" &&
        s.endpointEnabled
      ) {
        dispatch(s, jti, token);
        return "dispatched";
      }
      queued.push({ stream: s.id, jti, token });
      return s.method === SSF_POLL && s.status === "enabled"
        ? "queued"
        : "held";
    },
    set_ssf_stream_status(args) {
      const s = find(args["id"])!;
      const previous = s.status;
      s.status = String(args["status"]);
      s.reason = textOrNull(args["reason"]);
      const held = queued.filter((q) => q.stream === s.id);
      if (
        s.status === "disabled" ||
        (s.status === "enabled" && s.method === SSF_PUSH)
      ) {
        if (s.status === "enabled") {
          for (const q of held) {
            dispatch(s, q.jti, q.token);
          }
        }
        for (const q of held) {
          queued.splice(queued.indexOf(q), 1);
        }
      }
      return previous;
    },
    ssf_streams_for_event: (args) =>
      streams
        .filter(
          (s) =>
            s.status !== "disabled" &&
            s.eventsDelivered.includes(String(args["event_type"])) &&
            (s.tenant === null || s.tenant === args["tenant"]),
        )
        .map((s) => ({ id: s.id, audience: s.audience })),
    poll_ssf_events(args) {
      const s = find(args["stream_id"])!;
      const ack = new Set([
        ...strs(args["ack"]),
        ...Object.keys(recordOf(args["errors"])),
      ]);
      for (const q of queued.filter(
        (item) => item.stream === s.id && ack.has(item.jti),
      )) {
        queued.splice(queued.indexOf(q), 1);
      }
      const limit = Math.min(
        Math.max(
          typeof args["max_events"] === "number" ? args["max_events"] : 100,
          0,
        ),
        1000,
      );
      const mine = queued.filter((q) => q.stream === s.id);
      if (s.status !== "enabled" || limit === 0) {
        return { sets: {}, moreAvailable: false };
      }
      return {
        sets: Object.fromEntries(
          mine.slice(0, limit).map((q) => [q.jti, q.token]),
        ),
        moreAvailable: mine.length > limit,
      };
    },
    note_ssf_verification(args) {
      const s = find(args["stream_id"])!;
      if (s.verifiedAt !== null && Date.now() - s.verifiedAt < 30_000) {
        return false;
      }
      s.verifiedAt = Date.now();
      return true;
    },
    record_ssf_received(args) {
      const key = `${String(args["issuer"])} ${String(args["jti"])}`;
      if (received.has(key)) {
        return false;
      }
      received.add(key);
      return true;
    },
    forget_ssf_received: (args) =>
      received.delete(`${String(args["issuer"])} ${String(args["jti"])}`),
    purge_shared_signals: () => 0,
  };
  return {
    streams,
    queued,
    received,
    dispatched,
    calls,
    call(_schema, fn, args) {
      calls.push([fn, args]);
      const handler = fns[fn];
      if (!handler) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }
      try {
        return Promise.resolve(handler(args));
      } catch (cause) {
        return Promise.reject(cause);
      }
    },
  };
}
