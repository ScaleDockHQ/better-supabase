import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  CAEP_EVENTS,
  createSsfReceiver,
  createSsfTransmitter,
  sqlTransport,
} from "../../src/blocks/shared-signals/index.ts";
import { signingKey } from "../blocks/shared-signals/fixtures.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const ISSUER = "https://tx.example";
const TENANT = crypto.randomUUID();

describe.skipIf(!live)("shared-signals module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pushes through a set endpoint, holds SETs while paused and sends them on resume", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["outbox", "webhooks-out", "shared-signals"]);
      await s.service();
      await s.client.query("set local role service_role");
      const { signer } = await signingKey();

      const tx = createSsfTransmitter({
        transport: sqlTransport(s.sql),
        issuer: ISSUER,
        jwksUri: `${ISSUER}/jwks`,
        signer,
        authorize: () => null,
      });

      const stream = await tx
        .createStream({
          receiver: { receiver: "rx", tenant: TENANT },
          method: "push",
          endpointUrl: "https://rx.example/ssf",
          eventsRequested: [CAEP_EVENTS.sessionRevoked, "urn:unknown"],
        })
        .orThrow();

      expect(stream).toMatchObject({
        method: "push",
        endpointUrl: "https://rx.example/ssf",
        eventsDelivered: [CAEP_EVENTS.sessionRevoked],
        status: "enabled",
      });

      const emit = () =>
        tx
          .emit({
            tenant: TENANT,
            subject: { format: "opaque", id: "u1" },
            event: { type: CAEP_EVENTS.sessionRevoked, claims: {} },
          })
          .orThrow();

      expect(await emit()).toMatchObject({ streams: 1, dispatched: 1 });

      await tx.setStatus(stream.id, "paused").orThrow();
      expect(await emit()).toMatchObject({ held: 1 });
      await tx.setStatus(stream.id, "enabled").orThrow();

      const deliveries = await s.client.query<{
        type: string;
        format: string;
        set: string;
      }>(
        `select d.event_type as type, e.format, d.payload ->> 'set' as set
         from better_supabase.webhook_deliveries d
         join better_supabase.webhook_endpoints e on e.id = d.endpoint_id
         order by d.created_at, d.id`,
      );

      // session-revoked, stream-updated (paused), session-revoked (held), stream-updated (enabled)
      expect(deliveries.rows).toHaveLength(4);
      expect(
        deliveries.rows.every(
          (row) => row.type === "ssf.set" && row.format === "set",
        ),
      ).toBe(true);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.ssf_events)",
        ),
      ).toBe(0);

      expect(await tx.deleteStream(stream.id).orThrow()).toBe(true);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.webhook_endpoints)",
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });

  it("queues poll SETs, acknowledges them and drops replays at the receiver", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["shared-signals"]);
      await s.service();
      await s.client.query("set local role service_role");
      const { signer, jwks } = await signingKey();
      const transport = sqlTransport(s.sql);

      const tx = createSsfTransmitter({
        transport,
        issuer: ISSUER,
        jwksUri: `${ISSUER}/jwks`,
        signer,
        authorize: () => null,
      });

      const stream = await tx
        .createStream({
          receiver: { receiver: "rx", tenant: "t1" },
          method: "poll",
          eventsRequested: [CAEP_EVENTS.credentialChange],
        })
        .orThrow();

      for (const tenant of ["t1", "t2", "t1"]) {
        await tx
          .emit({
            tenant,
            subject: { format: "opaque", id: "u1" },
            event: { type: CAEP_EVENTS.credentialChange, claims: {} },
          })
          .orThrow();
      }

      const first = await tx.poll(stream.id, { maxEvents: 1 }).orThrow();
      expect(Object.keys(first.sets)).toHaveLength(1);
      expect(first.moreAvailable).toBe(true);
      const [jti, token] = Object.entries(first.sets)[0]!;

      const rx = createSsfReceiver({
        transport,
        issuer: ISSUER,
        audience: "rx",
        jwks,
      });

      expect(await rx.receive(token)).toMatchObject({
        ok: true,
        duplicate: false,
      });
      expect(await rx.receive(token)).toMatchObject({
        ok: true,
        duplicate: true,
      });

      const rest = await tx
        .poll(stream.id, { maxEvents: 10, ack: [jti] })
        .orThrow();

      expect(Object.keys(rest.sets)).toHaveLength(1);
      expect(rest.moreAvailable).toBe(false);
      expect(
        await tx
          .poll(stream.id, { maxEvents: 0, ack: Object.keys(rest.sets) })
          .orThrow(),
      ).toEqual({ sets: {}, moreAvailable: false });
      expect(
        await rx.purge(Temporal.Duration.from({ seconds: 0 })).orThrow(),
      ).toBeGreaterThanOrEqual(0);
    } finally {
      await s.close();
    }
  });

  it("refuses push streams without webhooks-out and callers other than the service role", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["shared-signals"]);
      await s.service();
      await s.client.query("set local role service_role");
      expect(
        await s.hint(
          `select better_supabase.create_ssf_stream(gen_random_uuid(), 'rx', null, '{rx}', 'urn:ietf:rfc:8935', '{}', '{}', null, 'https://rx.example')`,
        ),
      ).toBe("SSF_PUSH_UNAVAILABLE");
      await s.client.query("reset role");
      const alice = await s.user("alice");
      await s.asRole(alice);
      expect(await s.hint("select better_supabase.ssf_streams('rx')")).toMatch(
        /permission denied|SSF_FORBIDDEN/,
      );
    } finally {
      await s.close();
    }
  });
});
