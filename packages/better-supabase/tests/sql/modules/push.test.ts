import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  moduleBody,
  renderModules,
  resolveModules,
} from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) => moduleBody("push", { modules })!;

const withOutbox = (): string =>
  renderModules(["outbox", "push"], { modules: {} })
    .filter((file) => file.contents.includes("push_devices"))
    .map((file) => file.contents)
    .join("\n");

describe("push module", () => {
  it("creates the devices table with RLS for the owner", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."push_devices"',
    );
    expect(sql).toContain(
      '"user_id" uuid not null references auth.users (id) on delete cascade',
    );
    expect(sql).toContain('"token" text not null unique');
    expect(sql).toContain(
      'alter table "better_supabase"."push_devices" enable row level security;',
    );
    expect(sql).toContain(
      'grant select, delete on "better_supabase"."push_devices" to authenticated;',
    );
    expect(sql).toContain('using ("user_id" = (select auth.uid()))');
  });

  it("keeps token reads and pruning for the service role", () => {
    const sql = body();
    for (const signature of [
      '"push_tokens_for"(uuid[])',
      '"prune_push_tokens"(text[])',
    ]) {
      expect(sql).toContain(
        `revoke execute on function "better_supabase".${signature} from public, anon, authenticated;`,
      );
      expect(sql).toContain(
        `grant execute on function "better_supabase".${signature} to service_role;`,
      );
    }
    expect(sql).toContain("hint = 'PUSH_FORBIDDEN'");
    expect(sql).toContain("hint = 'PUSH_TOO_MANY'");
    expect(sql.match(/security definer/g)).toHaveLength(4);
  });

  it("emits device events only with the outbox", () => {
    expect(body()).not.toContain("emit_event");
    const sql = withOutbox();
    expect(sql).toContain("emit_event('push.device_registered'");
    expect(sql).toContain("emit_event('push.device_unregistered'");
  });

  it("needs no other module and is empty in custom mode", () => {
    expect(resolveModules(["push"]).map((module) => module.name)).toEqual([
      "push",
    ]);
    expect(
      moduleBody("push", { modules: { push: { mode: "custom" } } }),
    ).toBeUndefined();
  });
});
