import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createPushDevices,
  sqlTransport,
} from "../../src/blocks/push/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("push module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("registers, moves, reads and prunes device tokens", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["push"]);
      const alice = await s.user("alice");
      const bob = await s.user("bob");
      const devices = createPushDevices({ transport: sqlTransport(s.sql) });
      const token = `ExponentPushToken[${crypto.randomUUID()}]`;

      await s.as(alice);
      const first = await devices
        .register({ token, platform: "ios", deviceName: "Alice's phone" })
        .orThrow();
      const again = await devices
        .register({ token, platform: "ios", appVersion: "1.2.0" })
        .orThrow();
      expect(again).toBe(first);

      await s.asRole(alice);
      expect(
        await s.rows(
          "select device_name, app_version from better_supabase.push_devices where token = $1",
          [token],
        ),
      ).toEqual([{ device_name: "Alice's phone", app_version: "1.2.0" }]);

      await s.as(bob);
      await devices.register({ token, platform: "ios" }).orThrow();
      await s.asRole(alice);
      expect(
        await s.rows(
          "select id from better_supabase.push_devices where token = $1",
          [token],
        ),
      ).toEqual([]);

      await s.as(alice);
      expect(await devices.unregister(token).orThrow()).toBe(false);
      const refused = await devices.tokensFor([bob.id]);
      expect(refused).toMatchObject({
        ok: false,
        error: { kind: "forbidden" },
      });

      await s.service();
      expect(await devices.tokensFor([alice.id, bob.id]).orThrow()).toEqual([
        { userId: bob.id, token, platform: "ios", provider: "expo" },
      ]);
      expect(await devices.prune([token, "unknown"]).orThrow()).toBe(1);
      expect(await devices.tokensFor([bob.id]).orThrow()).toEqual([]);
    } finally {
      await s.close();
    }
  });

  it("refuses anonymous callers and unknown platforms", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["push"]);
      const user = await s.user("reader");
      await s.as("anon");
      expect(
        await s.hint("better_supabase.register_push_device('t', 'ios')"),
      ).toBe("PUSH_FORBIDDEN");
      await s.as(user);
      expect(
        await s.hint("better_supabase.register_push_device('t', 'symbian')"),
      ).toBe("PUSH_PLATFORM");
      expect(await s.hint("better_supabase.unregister_push_device('t')")).toBe(
        "no error",
      );
    } finally {
      await s.close();
    }
  });
});
