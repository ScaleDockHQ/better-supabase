import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createAdmissionPasses } from "../../src/blocks/admission-passes/index.ts";
import {
  createSigningKeys,
  sqlTransport,
} from "../../src/blocks/signing-keys/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("passes", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("signs a ticket, checks it in once and counts drop-ins against capacity", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install([
        "organizations",
        "outbox",
        "bookings",
        "signing-keys",
        "passes",
      ]);
      const owner = await s.user("owner");
      const holder = await s.user("holder");
      const tenant = await s.organization(owner);

      await s.client.query("reset role");

      const [room] = await s.rows<{ id: string }>(
        "insert into better_supabase.booking_resources (tenant_id, name, capacity) values ($1, 'Studio', 2) returning id",
        [tenant],
      );

      const [service] = await s.rows<{ id: string }>(
        "insert into better_supabase.booking_services (tenant_id, name, duration) values ($1, 'Class', interval '1 hour') returning id",
        [tenant],
      );

      const [booking] = await s.rows<{ id: string }>(
        `insert into better_supabase.bookings (tenant_id, resource_id, service_id, seat, during, blocked, status)
         values ($1, $2, $3, 1, tstzrange(now() - interval '5 minutes', now() + interval '55 minutes'),
           tstzrange(now() - interval '5 minutes', now() + interval '55 minutes'), 'confirmed')
         returning id`,
        [tenant, room!.id, service!.id],
      );

      const owned = { type: "organization", id: tenant };
      const keys = createSigningKeys({ transport: sqlTransport(s.sql) });

      const asService = async () => {
        await s.service();
        await s.client.query("set local role service_role");
      };

      await asService();
      await keys.create(owned).orThrow();
      const jwks = await keys.jwks(owned).orThrow();

      const passes = createAdmissionPasses({
        transport: sqlTransport(s.sql),
        tenant,
        signer: keys.signer(owned),
        jwks,
      });

      await s.asRole(owner);

      const ticket = await passes
        .issue({ bookingId: booking!.id, holderUserId: holder.id })
        .orThrow();

      expect(ticket).toMatchObject({
        kind: "ticket",
        resourceId: room!.id,
        usesAllowed: 1,
      });

      await asService();
      const token = await passes.token(ticket).orThrow();

      await s.asRole(holder);
      expect((await passes.mine().orThrow()).map((pass) => pass.id)).toEqual([
        ticket.id,
      ]);

      await s.asRole(owner);
      const [head, body] = token.split(".");
      const forged = await passes.checkIn(`${head}.${body}.${"A".repeat(86)}`);
      expect(forged.ok ? undefined : forged.error.hint).toBe(
        "PASS_TOKEN_INVALID",
      );

      expect(
        await passes.checkIn(token, { gate: "north" }).orThrow(),
      ).toMatchObject({ admitted: true, gate: "north", pass: { uses: 1 } });
      expect(await passes.checkIn(token).orThrow()).toMatchObject({
        admitted: false,
        reason: "used_up",
      });

      const first = await passes
        .issue({ kind: "day", resourceId: room!.id, usesAllowed: 5 })
        .orThrow();

      const second = await passes
        .issue({ kind: "day", resourceId: room!.id, usesAllowed: 5 })
        .orThrow();

      expect((await passes.checkInManually(first.id).orThrow()).admitted).toBe(
        true,
      );
      expect(await passes.checkInManually(second.id).orThrow()).toMatchObject({
        admitted: false,
        reason: "full",
      });
      expect(await passes.occupancy(room!.id).orThrow()).toEqual({
        resourceId: room!.id,
        capacity: 2,
        booked: 1,
        dropIns: 1,
        free: 0,
      });

      await passes.revoke(second.id).orThrow();
      await asService();
      const revokedToken = await passes.token(second).orThrow();
      await s.asRole(owner);
      expect(await passes.checkIn(revokedToken).orThrow()).toMatchObject({
        admitted: false,
        reason: "revoked",
      });

      expect(
        (await passes.checkIns(ticket.id).orThrow())
          .map((scan) => scan.reason ?? "admitted")
          .toSorted(),
      ).toEqual(["admitted", "used_up"]);

      await s.asRole(holder);
      expect(
        await passes.issue({ resourceId: room!.id }).then((r) => r.ok),
      ).toBe(false);
    } finally {
      await s.close();
    }
  });
});
