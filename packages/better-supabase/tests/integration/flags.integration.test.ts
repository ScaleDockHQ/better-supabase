import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createAnnouncements } from "../../src/blocks/announcements/index.ts";
import {
  createFlagsProvider,
  type FlagContext,
  sqlTransport,
} from "../../src/blocks/flags/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

/** The same vectors as tests/blocks/flags/flags.test.ts. */
const BUCKET_VECTORS = [
  ["new_editor", "8c5a3d3e-0000-4000-8000-000000000001", 1154],
  ["new_editor", "org-1", 697],
  ["checkout_v2", "user-42", 8741],
] as const;

describe.skipIf(!live)("flags", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("buckets like the TypeScript provider", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["flags"]);
      for (const [key, target, bucket] of BUCKET_VECTORS) {
        expect(
          await s.value<number>("better_supabase.flag_bucket($1, $2)", [
            key,
            target,
          ]),
        ).toBe(bucket);
      }
    } finally {
      await s.close();
    }
  });

  it("serves a service-role server through the API schema wrappers", async () => {
    const s = await BlockSession.open(pool);
    const api = `bs_api_${crypto.randomUUID().slice(0, 8)}`;
    try {
      await s.install(["flags", "announcements"], {
        modules: { flags: { api }, announcements: { api } },
      });
      await s.rows(
        "insert into better_supabase.flags (key, rules) values ('beta', '[]')",
      );
      await s.service();
      await s.client.query("set local role service_role");
      const sql = sqlTransport(s.sql);
      const calls: string[] = [];
      const transport = {
        call: (
          _schema: string,
          fn: string,
          args: Readonly<Record<string, unknown>>,
        ) => {
          calls.push(fn);
          return sql.call(api, fn, args);
        },
      };
      const provider = createFlagsProvider({ transport });
      const resolved = await provider.resolveBooleanEvaluation(
        "beta",
        true,
        {},
      );
      expect(resolved.errorCode).toBeUndefined();
      const announcements = createAnnouncements({ transport });
      expect((await announcements.list()).ok).toBe(true);
      expect(calls).toEqual(["flag_definitions", "list_announcements"]);
    } finally {
      await s.close();
    }
  });

  it("evaluates rules, overrides and rollouts as evaluateFlag() does", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "flags"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { member });
      const other = await s.organization(outsider);

      await s.service();
      await s.rows(
        `insert into better_supabase.flags (key, rules, rollout_percentage, rollout_variant)
         values ('new_editor', $1, 50, 'on'),
                ('dark_mode', '[]', 0, null)`,
        [JSON.stringify([{ variant: "on", roles: ["owner"] }])],
      );
      await s.rows(
        `insert into better_supabase.flags (key, type, variants, default_variant, enabled)
         values ('theme', 'string', '{"a": "light", "b": "dark"}', 'a', false)`,
      );
      await s.rows(
        `insert into better_supabase.flag_overrides (flag_key, organization_id, user_id, variant)
         values ('dark_mode', $1, null, 'on'), ('dark_mode', null, $2, 'off')`,
        [organization, member.id],
      );

      const provider = createFlagsProvider({ transport: sqlTransport(s.sql) });
      const definitions = new Map(
        (
          await s.value<readonly { key: string }[]>(
            "better_supabase.flag_definitions()",
          )
        ).map((row) => [row.key, row]),
      );
      expect([...definitions.keys()]).toEqual([
        "dark_mode",
        "new_editor",
        "theme",
      ]);

      const cases: readonly [string, string | null, string][] = [
        ["new_editor", organization, owner.id],
        ["new_editor", organization, member.id],
        ["new_editor", other, outsider.id],
        ["dark_mode", organization, owner.id],
        ["dark_mode", organization, member.id],
        ["dark_mode", other, outsider.id],
        ["theme", organization, owner.id],
      ];
      for (const [key, tenant, user] of cases) {
        const sql = await s.value<Record<string, unknown>>(
          "better_supabase.flag_evaluation($1, $2, $3)",
          [key, tenant, user],
        );
        const role =
          user === owner.id
            ? "owner"
            : user === member.id && tenant === organization
              ? "member"
              : user === outsider.id
                ? "owner"
                : undefined;
        const context: FlagContext = {
          targetingKey: user,
          ...(tenant !== null && { tenant }),
          ...(role !== undefined && { role }),
        };
        const typed =
          key === "theme"
            ? await provider.resolveStringEvaluation(key, "", context)
            : await provider.resolveBooleanEvaluation(key, false, context);
        expect({ key, user, ...typed }).toEqual({ key, user, ...sql });
      }
      expect(
        await s.value("better_supabase.flag_evaluation('missing', null, null)"),
      ).toBeNull();
      await s.asRole(owner);
      expect(
        await s.value("better_supabase.flag_enabled('new_editor', $1)", [
          organization,
        ]),
      ).toBe(true);
      expect(
        await s.value("better_supabase.flag_enabled('dark_mode', $1)", [
          organization,
        ]),
      ).toBe(true);
      expect(
        await s.value("better_supabase.flag_enabled('missing', $1)", [
          organization,
        ]),
      ).toBe(false);
      await s.asRole(member);
      expect(
        await s.value("better_supabase.flag_enabled('dark_mode', $1)", [
          organization,
        ]),
      ).toBe(false);
      expect(await s.hint("select better_supabase.flag_definitions()")).toMatch(
        /permission denied/,
      );
      expect(await s.hint("select * from better_supabase.flags")).toMatch(
        /GRANT SELECT/,
      );
    } finally {
      await s.close();
    }
  });
});
