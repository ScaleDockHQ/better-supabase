import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createPushDevices,
  sqlTransport,
} from "../../src/blocks/push/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("push", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("registers devices per user, hides them from others and prunes them as the service", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["outbox", "push"]);
      const ada = await s.user("ada");
      const bob = await s.user("bob");
      const devices = createPushDevices({ transport: sqlTransport(s.sql) });

      await s.as(ada);
      const first = await devices
        .register({
          token: "ExponentPushToken[a]",
          platform: "ios",
          deviceName: "iPhone",
        })
        .orThrow();
      expect(
        await devices
          .register({
            token: "ExponentPushToken[a]",
            platform: "ios",
            appVersion: "2.0",
          })
          .orThrow(),
      ).toBe(first);
      await devices
        .register({ token: "ExponentPushToken[b]", platform: "android" })
        .orThrow();
      expect(
        await devices
          .register({ token: "x", platform: "tv" as never })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("PUSH_PLATFORM");
      expect(
        await devices.tokensFor([ada.id]).then((r) => !r.ok && r.error.hint),
      ).toBe("PUSH_FORBIDDEN");

      await s.asRole(ada);
      expect(
        await s.rows(
          "select token, device_name, app_version from better_supabase.push_devices order by token",
        ),
      ).toEqual([
        {
          token: "ExponentPushToken[a]",
          device_name: "iPhone",
          app_version: "2.0",
        },
        { token: "ExponentPushToken[b]", device_name: null, app_version: null },
      ]);
      await s.asRole(bob);
      expect(
        await s.rows("select token from better_supabase.push_devices"),
      ).toEqual([]);
      await s.as(bob);
      expect(await devices.unregister("ExponentPushToken[a]").orThrow()).toBe(
        false,
      );
      await devices
        .register({ token: "ExponentPushToken[b]", platform: "android" })
        .orThrow();

      await s.service();
      expect(await devices.tokensFor([ada.id, bob.id]).orThrow()).toEqual(
        [
          {
            userId: ada.id,
            token: "ExponentPushToken[a]",
            platform: "ios",
            provider: "expo",
          },
          {
            userId: bob.id,
            token: "ExponentPushToken[b]",
            platform: "android",
            provider: "expo",
          },
        ].sort((x, y) => (x.userId < y.userId ? -1 : 1)),
      );
      expect(
        await s.rows(
          "select type from better_supabase.outbox_events where type like 'push.%' order by type",
        ),
      ).toEqual([
        { type: "push.device_registered" },
        { type: "push.device_registered" },
      ]);
      expect(
        await devices.prune(["ExponentPushToken[b]", "missing"]).orThrow(),
      ).toBe(1);

      await s.as(ada);
      expect(await devices.unregister("ExponentPushToken[a]").orThrow()).toBe(
        true,
      );
      await s.as("anon");
      expect(
        await s.hint("better_supabase.register_push_device('t', 'ios')"),
      ).toBe("PUSH_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
