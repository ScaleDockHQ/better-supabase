import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/registry.ts";

const body = () => moduleBody("chat-sdk-state", { modules: {} })!;

describe("chat-sdk-state module", () => {
  it("keeps every table and function for the service role", () => {
    const sql = body();
    for (const table of [
      "chat_state_subscriptions",
      "chat_state_locks",
      "chat_state_cache",
      "chat_state_lists",
      "chat_state_queues",
      "chat_installations",
    ]) {
      expect(sql).toContain(
        `alter table "better_supabase"."${table}" enable row level security;`,
      );
    }
    const grants = [
      ...sql.matchAll(/grant execute on function [^;]+ to ([^;]+);/g),
    ];
    expect(grants.length).toBeGreaterThan(20);
    for (const grant of grants) expect(grant[1]).toBe("service_role");
  });

  it("reads the wall clock so TTLs pass inside one transaction", () => {
    const sql = body();
    expect(sql).toContain("clock_timestamp()");
    expect(sql).toContain("for update skip locked");
  });

  it("writes nothing in custom mode", () => {
    expect(
      moduleBody("chat-sdk-state", {
        modules: { "chat-sdk-state": { mode: "custom" } },
      }),
    ).toBeUndefined();
  });
});
