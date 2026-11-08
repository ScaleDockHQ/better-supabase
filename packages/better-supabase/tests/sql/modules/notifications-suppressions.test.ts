import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import {
  customContracts,
  moduleBody,
  renderBlocks,
} from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";
import { unnamedChecks } from "../unnamed-checks.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("notifications", { modules })!;

const overApp = (modules: AnyBlocksConfig) =>
  renderBlocks(["notifications"], { modules, ownTables: ownTablesOf(modules) })
    .filter((file) => file.module === "notifications")
    .map((file) => file.contents)
    .join("\n");

const TABLE = '"better_supabase"."notification_suppressions"';

const APP_TABLES: AnyBlocksConfig = {
  notifications: {
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
    expect(unnamedChecks(sql)).toContain(`create table ${TABLE} (`);
    expect(unnamedChecks(sql)).toContain(
      `"address" text not null check ("address" = lower("address"))`,
    );
    expect(unnamedChecks(sql)).toContain(
      `"user_id" uuid references auth.users (id) on delete cascade`,
    );
    expect(unnamedChecks(sql)).toContain(
      `"reason" text not null check ("reason" in ('bounce', 'complaint', 'manual'))`,
    );
    expect(unnamedChecks(sql)).toContain(`unique ("channel", "address")`);
    expect(unnamedChecks(sql)).toContain(
      `alter table ${TABLE} enable row level security;`,
    );
    expect(unnamedChecks(sql)).toContain(
      `grant select on ${TABLE} to authenticated;`,
    );
    expect(unnamedChecks(sql)).toContain(
      `grant all on ${TABLE} to service_role;`,
    );
    expect(unnamedChecks(sql)).not.toMatch(
      /grant (insert|update|delete)[^;]*notification_suppressions"? to authenticated/,
    );
    expect(unnamedChecks(sql)).toContain(
      `create policy bsb_notification_suppressions_read on ${TABLE}\n  for select to authenticated\n  using ("user_id" = (select auth.uid()));`,
    );
  });

  it("joins the claim to the suppression for the delivery's channel and address", () => {
    const sql = body();
    expect(unnamedChecks(sql)).toContain(
      `left join ${TABLE} s on s."channel" = l."channel" and s."address" = lower(u.email)`,
    );
    expect(unnamedChecks(sql)).toContain(`'suppressed', s."reason"`);
  });

  it("writes suppressions through service-only definer functions", () => {
    const sql = body();
    expect(unnamedChecks(sql)).toContain(
      `create or replace function "better_supabase"."suppress_notification_address"(address text, reason text, channel text default 'email', provider text default null, provider_event_id text default null, detail jsonb default '{}')`,
    );
    expect(unnamedChecks(sql)).toContain("NOTIFICATION_SUPPRESSION_ADDRESS");
    expect(unnamedChecks(sql)).toContain("NOTIFICATION_SUPPRESSION_REASON");
    expect(unnamedChecks(sql)).toContain(
      `on conflict ("channel", "address") do nothing;`,
    );
    expect(unnamedChecks(sql)).toMatch(
      /grant execute on function "better_supabase"\."suppress_notification_address"\(text, text, text, text, text, jsonb\) to service_role/,
    );
    expect(unnamedChecks(sql)).toMatch(
      /grant execute on function "better_supabase"\."unsuppress_notification_address"\(text, text\) to service_role/,
    );
    expect(unnamedChecks(sql)).not.toMatch(
      /grant execute on function "better_supabase"\."(un)?suppress_notification_address"[^;]*authenticated/,
    );
    expect(unnamedChecks(sql)).toContain(
      `grant execute on function "better_supabase"."list_notification_suppressions"(integer) to authenticated, service_role;`,
    );
    expect(unnamedChecks(sql)).toMatch(
      /function "better_supabase"\."list_notification_suppressions"\(max_items integer default 50\)\nreturns jsonb\nlanguage sql\nstable\nset search_path = ''/,
    );
  });

  it("leaves suppressions out without deliveries and when mapped to null", () => {
    for (const modules of [
      { notifications: { tables: { deliveries: null } } },
      { notifications: { tables: { suppressions: null } } },
    ] satisfies AnyBlocksConfig[]) {
      const sql = body(modules);
      expect(unnamedChecks(sql)).not.toContain("notification_suppressions");
      expect(unnamedChecks(sql)).not.toContain("'suppressed'");
    }
  });

  it("creates its own suppressions table next to the app's tables when the app maps none", () => {
    const sql = overApp(APP_TABLES);
    expect(unnamedChecks(sql)).toContain(
      `create table "public"."notification_suppressions" (`,
    );
    expect(unnamedChecks(sql)).not.toContain(
      `create table "public"."notification_deliveries" (`,
    );
  });

  it("uses the app's mapped suppressions table without creating it", () => {
    const modules: AnyBlocksConfig = {
      notifications: {
        ...APP_TABLES["notifications"],
        tables: { suppressions: "public.email_suppressions" },
      },
    };

    const sql = overApp(modules);

    expect(unnamedChecks(sql)).not.toContain(
      `create table if not exists "public"."email_suppressions"`,
    );
    expect(unnamedChecks(sql)).toContain(
      `alter table "public"."email_suppressions" add column if not exists`,
    );
    expect(unnamedChecks(sql)).toContain(
      `left join "public"."email_suppressions" s on`,
    );
    expect(unnamedChecks(sql)).toContain("suppress_notification_address");
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
