import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
): string =>
  renderModules(names, { modules: options ? { comments: { options } } : {} })
    .filter((file) => file.module === "comments")
    .map((file) => file.contents)
    .join("\n");

describe("comments module", () => {
  it("puts comments on the record's conversation and leaves out what isn't installed", () => {
    const sql = sqlOf(["comments"]);
    expect(sql).toContain(
      `create table if not exists "better_supabase"."comment_tasks" (`,
    );
    expect(sql).not.toMatch(/create table if not exists \S+"comments"/);
    expect(sql).toContain(
      `"better_supabase"."open_conversation"(\n    create_comment.tenant,\n    'subject',`,
    );
    expect(sql).toContain(`v_msg := "better_supabase"."send_message"(`);
    expect(sql).toContain(
      `drop function if exists "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb);`,
    );
    expect(sql).not.toContain("comment_sent");
    expect(sql).not.toContain('"assign_comment"(');
    expect(sql).not.toContain('"notify"(');
  });

  it("reads a comment's work item only where the caller reads the message in its tenant", () => {
    const sql = sqlOf(["comments"]);
    expect(sql).toContain(
      `create policy "comment_tasks_read" on "better_supabase"."comment_tasks" for select to authenticated
  using ("better_supabase"."comment_message_readable"("message_id", "organization_id"));`,
    );
    expect(sql).toContain(
      `with check (("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "organization_id"))`,
    );
    expect(sql).toContain(
      `x."id" = comment_message_readable.message and x."tenant_id" = comment_message_readable.tenant`,
    );
    expect(sql).toContain(
      `grant insert ("message_id", "organization_id", "task_id") on "better_supabase"."comment_tasks" to authenticated;`,
    );
  });

  it("copies a record's comments as the service role only", () => {
    const sql = sqlOf(["comments"]);
    expect(sql).toContain(
      `raise exception 'Only the service role copies comments'`,
    );
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."copy_comments"(uuid, text, text, text, text) from public, anon, authenticated;`,
    );
    expect(sql).toContain('left join copies p on p.old_id = y."parent_id"');
  });

  it("expands group mentions before sending with options.mentionGroups", () => {
    expect(sqlOf(["comments"])).not.toContain("union select g.");

    const sql = sqlOf(["organizations", "comments"], {
      mentionGroups: {
        table: "app.team_members",
        group: "team_id",
        member: "user_id",
        tenant: "organization_id",
      },
    });

    expect(sql).toContain(
      `union select g."user_id" from "app"."team_members" g where g."team_id" = any (v_raw) and g."organization_id" = create_comment.tenant`,
    );
    expect(
      sqlOf(["comments"], {
        mentionGroups: { table: "teams", group: "id", member: "user_id" },
      }),
    ).toContain(
      `union select g."user_id" from "public"."teams" g where g."id" = any (v_raw)`,
    );
    expect(() =>
      sqlOf(["comments"], { mentionGroups: { table: "teams" } }),
    ).toThrow("needs table, group and member");
    expect(() => sqlOf(["comments"], { mentionGroups: "teams" })).toThrow(
      "must be { table, group, member, tenant? }",
    );
    expect(() =>
      sqlOf(["comments"], {
        mentionGroups: { table: "t", group: "g", member: "m", kind: "x" },
      }),
    ).toThrow("mentionGroups.kind is not an option");
    expect(() =>
      sqlOf(["comments"], {
        mentionGroups: { table: "t", group: "g", member: 1 },
      }),
    ).toThrow("member must be a non-empty string");
  });

  it("tells the record's followers and makes the author and the mentioned follow it", () => {
    const sql = sqlOf(["organizations", "notifications", "comments"]);
    expect(sql).toMatch(
      /"comment_sent"\(message uuid\)[\s\S]*?security definer/,
    );
    expect(sql).toContain(
      `where x."id" = comment_sent.message and x."author_id" = auth.uid()`,
    );
    expect(sql).toContain(`'type', 'comment.posted'`);
    expect(sql).toContain(`'exclude', to_jsonb(v_msg."mentions")`);
    expect(sql).toContain(
      `insert into "better_supabase"."notification_subscriptions"`,
    );

    const quiet = sqlOf(["organizations", "notifications", "comments"], {
      follow: false,
    });

    expect(quiet).toContain(`'type', 'comment.posted'`);
    expect(quiet).not.toContain("notification_subscriptions");
  });

  it("turns a comment into a work item with work-items", () => {
    const sql = sqlOf(["organizations", "work-items", "comments"]);
    expect(sql).toContain(
      `create or replace function "better_supabase"."assign_comment"(message uuid, assignee uuid default null, attrs jsonb default '{}')`,
    );
    expect(sql).toContain(`v_task := ("better_supabase"."create_work_item"(`);
    expect(sql).toContain(
      `case when assign_comment.assignee is null then '{}'::uuid[] else array[assign_comment.assignee] end`,
    );
  });

  it("rejects the options it dropped", () => {
    expect(() => sqlOf(["comments"], { notify: false })).toThrow(/notify/);
    expect(() => sqlOf(["comments"], { subjects: {} })).toThrow(/subjects/);
  });

  it("moves comments onto conversations from version 7", () => {
    const [plan] = upgradePlan([
      { module: "comments", version: 7 },
      { module: "reactions", version: 1 },
      { module: "attachments", version: 1 },
    ]);

    expect(plan).toMatchObject({ module: "comments", from: 7, to: 8 });
    const sql = plan!.steps.map((step) => step.sql).join("\n");
    expect(sql).toContain(
      `create table if not exists "better_supabase"."messages" (`,
    );
    expect(sql).toContain(
      `insert into "better_supabase"."conversations" ("tenant_id", "kind", "access", "subject_type", "subject_id"`,
    );
    expect(sql).toContain(
      `insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "parent_id", "thread_id"`,
    );
    expect(sql).toContain(
      `update "better_supabase"."reactions" x set "subject_type" = 'message' where x."subject_type" = 'comment';`,
    );
    expect(sql).toContain(
      `update "better_supabase"."attachments" x set "subject_type" = 'message' where x."subject_type" = 'comment';`,
    );
    expect(sql.indexOf('update "better_supabase"."attachments"')).toBeLessThan(
      sql.indexOf('drop table "better_supabase".comments cascade;'),
    );
    expect(sql).toContain(
      `drop function if exists "better_supabase"."delete_comment"(uuid);`,
    );
  });
});
