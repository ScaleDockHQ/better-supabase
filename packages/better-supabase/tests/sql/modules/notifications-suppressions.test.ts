import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { customContracts, moduleBody } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("notifications", { modules })!;

const TABLE = '"better_supabase"."notification_suppressions"';

const ADOPTED: AnyBlocksConfig = {
  notifications: {
    mode: "adopt",
    schema: "public",
    idType: "uuid",
    columns: {
      events: { actor: "actor_user_id", data: "metadata" },
      recipients: { user: "recipient_user_id" },
    },
    options: { channels: ["in_app", "email"] },
  },
};

describe("notification suppressions", () => {
  it("owns a suppressions table that users read for themselves and only the service writes", () => {
    const sql = body();
    expect(sql).toContain(`create table if not exists ${TABLE} (`);
    expect(sql).toContain(
      `"address" text not null check ("address" = lower("address"))`,
    );
    expect(sql).toContain(
      `"user_id" uuid references auth.users (id) on delete cascade`,
    );
    expect(sql).toContain(
      `"reason" text not null check ("reason" in ('bounce', 'complaint', 'manual'))`,
    );
    expect(sql).toContain(`unique ("channel", "address")`);
    expect(sql).toContain(`alter table ${TABLE} enable row level security;`);
    expect(sql).toContain(`grant select on ${TABLE} to authenticated;`);
    expect(sql).toContain(`grant all on ${TABLE} to service_role;`);
    expect(sql).not.toMatch(
      /grant (insert|update|delete)[^;]*notification_suppressions"? to authenticated/,
    );
    expect(sql).toContain(
      `create policy "bs_notification_suppressions_read" on ${TABLE} for select to authenticated using ("user_id" = (select auth.uid()));`,
    );
  });

  it("joins the claim to the suppression for the delivery's channel and address", () => {
    const sql = body();
    expect(sql).toContain(
      `left join ${TABLE} s on s."channel" = l."channel" and s."address" = lower(u.email)`,
    );
    expect(sql).toContain(`'suppressed', s."reason"`);
  });

  it("writes suppressions through service-only definer functions", () => {
    const sql = body();
    expect(sql).toContain(
      `create or replace function "better_supabase"."suppress_notification_address"(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')`,
    );
    expect(sql).toContain("NOTIFICATION_SUPPRESSION_ADDRESS");
    expect(sql).toContain("NOTIFICATION_SUPPRESSION_REASON");
    expect(sql).toContain(`on conflict ("channel", "address") do nothing;`);
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."suppress_notification_address"\(text, text, text, text, text, jsonb\) to service_role/,
    );
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."unsuppress_notification_address"\(text, text\) to service_role/,
    );
    expect(sql).not.toMatch(
      /grant execute on function "better_supabase"\."(un)?suppress_notification_address"[^;]*authenticated/,
    );
    expect(sql).toContain(
      `grant execute on function "better_supabase"."list_notification_suppressions"(integer) to authenticated, service_role;`,
    );
    expect(sql).toMatch(
      /function "better_supabase"\."list_notification_suppressions"\(max_items integer default 50\)\nreturns jsonb\nlanguage sql\nstable\nset search_path = ''/,
    );
  });

  it("leaves suppressions out without deliveries, when mapped to null, and for an adopter that does not map them", () => {
    for (const modules of [
      { notifications: { tables: { deliveries: null } } },
      { notifications: { tables: { suppressions: null } } },
      ADOPTED,
    ] satisfies AnyBlocksConfig[]) {
      const sql = body(modules);
      expect(sql).not.toContain("notification_suppressions");
      expect(sql).not.toContain("'suppressed'");
    }
  });

  it("uses an adopter's mapped table without creating it", () => {
    const sql = body({
      notifications: {
        ...ADOPTED["notifications"],
        tables: { suppressions: "public.email_suppressions" },
      },
    });

    expect(sql).not.toContain("create table if not exists");
    expect(sql).toContain(`left join "public"."email_suppressions" s on`);
    expect(sql).toContain("suppress_notification_address");
  });

  it("adds the functions to a custom contract only when the table is mapped", () => {
    const names = (modules: AnyBlocksConfig) =>
      customContracts(["notifications"], { modules })[0]!.functions.map(
        (fn) => fn.name,
      );

    expect(names({ notifications: { mode: "custom" } })).not.toContain(
      "suppress_notification_address",
    );
    expect(
      names({
        notifications: {
          mode: "custom",
          tables: { suppressions: "public.email_suppressions" },
        },
      }).slice(-3),
    ).toEqual([
      "suppress_notification_address",
      "unsuppress_notification_address",
      "list_notification_suppressions",
    ]);
  });
});
