import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody, moduleTopics } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("streams", { modules })!;

describe("streams module", () => {
  it("owns the stream and chunk tables with owner reads", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."streams" (',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."stream_chunks" (',
    );
    expect(sql).toContain('primary key ("stream_id", "idx")');
    expect(sql).toContain('using ("owner_id" = (select auth.uid()))');
    expect(sql).toContain("on delete cascade");
  });

  it("keeps the writes for the service role", () => {
    const sql = body();
    for (const signature of [
      '"stream_open"(text, uuid, uuid, text, interval, boolean)',
      '"stream_append"(text, integer, text[])',
      '"stream_close"(text)',
      '"purge_streams"(interval, integer)',
    ]) {
      expect(sql).toContain(
        `grant execute on function "better_supabase".${signature} to service_role;`,
      );
    }
    expect(sql).toContain(
      'grant execute on function "better_supabase"."stream_read"(text, integer, integer) to authenticated, service_role;',
    );
  });

  it("makes appends idempotent and refuses gaps and closed streams", () => {
    const sql = body();
    expect(sql).toContain("on conflict do nothing");
    expect(sql).toContain("hint = 'STREAM_GAP'");
    expect(sql).toContain("hint = 'STREAM_CLOSED'");
    expect(sql).toContain("'cancelled', v_stream.\"cancel_requested_at\"");
  });

  it("pings a private topic without a payload", () => {
    const sql = body();
    expect(sql).toContain(
      "perform realtime.send('{}'::jsonb, 'append', 'stream:' || stream_append.stream_id, true);",
    );
    expect(sql).toContain("like 'stream:%'");
    expect(moduleTopics(["streams"])).toEqual([
      { module: "streams", topic: "stream:{streamId}" },
    ]);
  });

  it("takes the topic prefix and the id type from the config", () => {
    const sql = body({
      streams: { idType: "bigint", options: { topic: "ai" } },
    });
    expect(sql).toContain("'ai:' || stream_append.stream_id");
    expect(sql).toContain("substr((select realtime.topic()), 4)");
    expect(sql).toContain('"tenant_id" bigint');
    expect(() =>
      body({ streams: { options: { topic: "Bad Topic" } } }),
    ).toThrow(/options.topic/);
  });

  it("writes nothing in custom mode", () => {
    expect(
      moduleBody("streams", { modules: { streams: { mode: "custom" } } }),
    ).toBeUndefined();
  });
});
