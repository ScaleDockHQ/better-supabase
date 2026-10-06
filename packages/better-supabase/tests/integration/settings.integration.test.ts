import { toStandardJsonSchema } from "@valibot/to-json-schema";
import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import {
  defineSettings,
  sqlTransport,
} from "../../src/blocks/settings/index.ts";
import { mapDbError } from "../../src/core/errors.ts";
import { fromPgError } from "../../src/postgres/executor.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const settings = defineSettings({
  user: {
    theme: {
      schema: toStandardJsonSchema(v.picklist(["light", "dark"])),
      default: "light",
    },
  },
  organization: {
    seats: {
      schema: toStandardJsonSchema(
        v.pipe(v.number(), v.integer(), v.minValue(1)),
      ),
      default: 5,
    },
  },
});

describe.skipIf(!live)("settings", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("reaches the module through API schema wrappers", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "settings"], {
        modules: { settings: { api: "bs_settings_api" } },
      });
      const member = await s.user("member");
      const client = settings.connect({
        transport: sqlTransport(s.sql),
        schema: "bs_settings_api",
      });
      await s.asRole(member);
      expect(await client.user.set("theme", "dark").orThrow()).toBe("dark");
      expect(await client.user.get("theme").orThrow()).toBe("dark");
      expect(
        await s.value<string>(
          "(select prosecdef::text from pg_proc where proname = 'set_user_setting' and pronamespace = 'bs_settings_api'::regnamespace)",
        ),
      ).toBe("false");
      await s.asRole("anon");
      expect(
        await s.hint("select bs_settings_api.get_user_settings()"),
      ).toContain("permission denied");
    } finally {
      await s.close();
    }
  });

  it("keeps user settings private and checks organization permissions", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "jsonb-schemas", "settings"], {
        modules: { settings: { options: { schemas: settings } } },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { member });
      const client = settings.connect({ transport: sqlTransport(s.sql) });

      await s.asRole(member);
      expect(await client.user.get().orThrow()).toEqual({ theme: "light" });
      expect(await client.user.set("theme", "dark").orThrow()).toBe("dark");
      expect(await client.user.get("theme").orThrow()).toBe("dark");

      await s.asRole(owner);
      expect(await client.user.get("theme").orThrow()).toBe("light");
      expect(
        await client.organization.set(organization, "seats", 12).orThrow(),
      ).toBe(12);

      // A member reads organization settings but cannot change them.
      await s.asRole(member);
      expect(
        await client.organization.get(organization, "seats").orThrow(),
      ).toBe(12);
      expect(
        await client.organization.set(organization, "seats", 3),
      ).toMatchObject({ ok: false });
      expect(
        await client.organization.reset(organization, "seats").orThrow(),
      ).toBe(false);

      await s.asRole(outsider);
      expect(
        await client.organization.get(organization, "seats").orThrow(),
      ).toBe(5);

      // The pg_jsonschema check rejects what the schema rejects, and the
      // trigger's errors map to a validation error.
      await s.service();
      const insert = `insert into better_supabase.organization_settings (organization_id, key, value)
           values ('${organization}', 'seats', '"many"')`;
      expect(await s.hint(insert)).toBe("JSON_SCHEMA_INVALID");
      await s.client.query("savepoint json");
      const raw = await s.client.query(insert).then(
        () => undefined,
        (error: unknown) => fromPgError(error),
      );
      await s.client.query("rollback to savepoint json");
      expect(mapDbError(raw!)).toMatchObject({
        kind: "validation",
        status: 422,
        issues: [
          { message: expect.stringContaining("integer"), path: ["value"] },
        ],
      });
      // The check constraint stays, for rows written with triggers off.
      await s.client.query("savepoint json");
      await s.client.query("set local session_replication_role = replica");
      expect(await s.hint(insert)).toMatch(/bs_json_value_seats/);
      await s.client.query("rollback to savepoint json");

      await s.asRole(owner);
      expect(await client.user.reset("theme").orThrow()).toBe(false);
      await s.asRole(member);
      expect(await client.user.reset("theme").orThrow()).toBe(true);
      expect(await client.user.get("theme").orThrow()).toBe("light");
    } finally {
      await s.close();
    }
  });

  it("guards platform settings with a permission and a read rule per key", async () => {
    const platform = defineSettings({
      platform: {
        feePercent: {
          schema: toStandardJsonSchema(v.pipe(v.number(), v.minValue(0))),
          default: 1,
          permission: "billing.platform",
          read: "public",
        },
        routing: {
          schema: toStandardJsonSchema(v.string()),
          permission: "routing.platform",
          read: "staff",
        },
        banner: { schema: toStandardJsonSchema(v.string()), default: "" },
      },
    });
    const s = await BlockSession.open(pool);
    try {
      await s.install(["jsonb-schemas", "settings"], {
        modules: { settings: { options: { schemas: platform } } },
      });
      const staff = await s.user("staff");
      const user = await s.user("user");
      const client = platform.connect({ transport: sqlTransport(s.sql) });
      const as = (who: typeof user, permissions: string[] = []) =>
        s.asRole(who, { platform_permissions: permissions });

      await as(staff, ["billing.platform"]);
      expect(await client.platform.set("feePercent", 2.5).orThrow()).toBe(2.5);
      expect((await client.platform.set("routing", "eu")).ok).toBe(false);
      expect((await client.platform.set("banner", "Hi")).ok).toBe(false);
      await as(staff, ["routing.platform", "settings.manage"]);
      await client.platform.set("routing", "eu").orThrow();
      await client.platform.set("banner", "Maintenance at 6").orThrow();
      expect(await client.platform.get().orThrow()).toEqual({
        feePercent: 2.5,
        routing: "eu",
        banner: "Maintenance at 6",
      });

      expect(
        await s.hint(
          "select better_supabase.set_platform_setting('unlisted', '{\"value\": 1}')",
        ),
      ).not.toBe("no error");

      await as(user);
      expect(await client.platform.get().orThrow()).toEqual({
        feePercent: 2.5,
        routing: undefined,
        banner: "Maintenance at 6",
      });
      expect((await client.platform.reset("feePercent")).ok).toBe(true);
      expect(await client.platform.get("feePercent").orThrow()).toBe(2.5);

      await s.asRole("anon");
      expect(await client.platform.get().orThrow()).toEqual({
        feePercent: 2.5,
        routing: undefined,
        banner: "",
      });

      await s.service();
      expect(
        await s.hint(
          `insert into better_supabase.platform_settings (key, value) values ('feePercent', '-1')
           on conflict (key) do update set value = excluded.value`,
        ),
      ).not.toBe("no error");
    } finally {
      await s.close();
    }
  });
});
