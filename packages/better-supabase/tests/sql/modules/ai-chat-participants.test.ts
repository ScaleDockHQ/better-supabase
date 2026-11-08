import { describe, expect, it } from "vitest";

import { moduleBody } from "../app-columns.ts";

const body = (options: Record<string, unknown> = {}) =>
  moduleBody("ai-chat", { modules: { "ai-chat": { options } } })!;

describe("ai-chat participants", () => {
  it("owns ai_chat_participants, with one unique key per kind", () => {
    const sql = body();

    expect(sql).toContain(
      'create table "better_supabase"."ai_chat_participants" (',
    );
    expect(sql).toContain('"id" uuid primary key default gen_random_uuid()');
    expect(sql).toContain(
      'ai_chat_participants_user_key on "better_supabase"."ai_chat_participants" ("chat_id", "user_id") where "kind" = \'user\'',
    );
    expect(sql).toContain("ai_chat_participants_team_key");
    expect(sql).toContain("ai_chat_participants_customer_key");
    expect(sql).toContain('lower("email")) where "kind" = \'external\'');
    expect(sql).toContain("check (\"role\" in ('viewer', 'editor'))");
    expect(sql).toContain("ai_chat_participants_own_read");
  });

  it("lets participants read the chat and editors write to it", () => {
    const sql = body();

    expect(sql).toContain(
      '"better_supabase"."ai_chats"."visibility" <> \'private\' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = "better_supabase"."ai_chats"."id"',
    );
    expect(sql).toContain("pa.\"role\"::text in ('editor')");
    expect(
      sql.indexOf('"better_supabase"."ai_chat_participants" ('),
    ).toBeLessThan(sql.indexOf("create policy bsb_ai_chats_read"));
  });

  it("adds, removes and lists participants", () => {
    const sql = body();

    for (const name of [
      "add_ai_chat_participant",
      "remove_ai_chat_participant",
      "list_ai_chat_participants",
    ]) {
      expect(sql).toContain(
        `create or replace function "better_supabase"."${name}"(`,
      );
    }

    expect(sql).toContain("'participant.added'");
    expect(sql).toContain("'participant.removed'");
    expect(sql).toContain(
      'on conflict ("chat_id", "user_id") where "kind" = \'user\' do update set "role" = excluded."role"',
    );
  });

  it("writes the participant table's extra columns from fields", () => {
    const sql = body({ participantExtraColumns: { note: "text" } });

    expect(sql).toContain(
      "coalesce(add_ai_chat_participant.fields, '{}'::jsonb) -> 'note'",
    );
  });

  it("keeps participants of a tenant chat inside the tenant", () => {
    const sql = body();

    expect(sql).toContain("can''t read chats in the chat''s organization");
    expect(sql).toContain(
      'and (x."tenant_id" is null or x."tenant_id" in (select',
    );
    expect(sql).toContain(
      'and (v_chat."tenant_id" is null or v_chat."tenant_id" in (select',
    );
  });

  it("checks the share permission only for a chat with a tenant", () => {
    expect(body()).toContain("You may not share chats here");
    expect(body({ tenant: false })).toContain("v_chat.tenant is not null and");
  });
});
