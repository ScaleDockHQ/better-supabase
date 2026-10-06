import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { CloudEvent } from "../../src/events/index.ts";

import {
  activitySink,
  createComments,
  sqlTransport,
} from "../../src/blocks/comments/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("comments", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("threads comments on readable subjects, notifies mentions and emits events", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.rows(
        `create table if not exists public.bs_test_projects (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           name text not null
         );
         alter table public.bs_test_projects enable row level security;
         grant select on public.bs_test_projects to authenticated;
         drop policy if exists "read" on public.bs_test_projects;
         create policy "read" on public.bs_test_projects for select to authenticated
           using (better_supabase.has_organization_role(organization_id));`,
      );
      await s.install(
        ["organizations", "outbox", "notifications", "comments"],
        {
          modules: {
            comments: {
              options: { subjects: { project: { table: "bs_test_projects" } } },
            },
          },
        },
      );
      const owner = await s.user("owner");
      const member = await s.user("member");
      const viewer = await s.user("viewer");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { member, viewer });
      const [project] = await s.rows<{ id: string }>(
        "insert into public.bs_test_projects (organization_id, name) values ($1, 'Apollo') returning id",
        [organization],
      );
      const subject = project!.id;
      const comments = createComments({ transport: sqlTransport(s.sql) });

      await s.asRole(member);
      const first = await comments
        .create({
          organizationId: organization,
          subjectType: "project",
          subjectId: subject,
          body: `Ready for review @[Owner](${owner.id}) @[Me](${member.id}) @[Out](${outsider.id})`,
        })
        .orThrow();
      expect(first).toMatchObject({
        organizationId: organization,
        subjectType: "project",
        authorId: member.id,
        parentId: undefined,
        editedAt: undefined,
      });
      // The author is dropped; the outsider stays in the column but isn't notified.
      expect(first.mentions).toEqual([owner.id, outsider.id].toSorted());
      // The mention trigger sends as the service role and restores the caller.
      expect(await s.value("auth.uid()")).toBe(member.id);
      expect(await s.value("auth.role()")).toBe("authenticated");

      const missing = await comments.create({
        organizationId: organization,
        subjectType: "project",
        subjectId: crypto.randomUUID(),
        body: "No such project",
      });
      expect(missing).toMatchObject({
        ok: false,
        error: { kind: "forbidden" },
      });
      const unknown = await comments.create({
        organizationId: organization,
        subjectType: "invoice",
        subjectId: subject,
        body: "Not a subject type",
      });
      expect(unknown).toMatchObject({ ok: false });

      await s.asRole(owner);
      const reply = await comments
        .create({
          organizationId: organization,
          subjectType: "project",
          subjectId: subject,
          body: "Looks good",
          parentId: first.id,
        })
        .orThrow();
      expect(reply.parentId).toBe(first.id);
      expect(
        await comments.edit(first.id, { body: "Owner editing" }),
      ).toMatchObject({ ok: false, error: { hint: "COMMENT_NOT_AUTHOR" } });

      await s.service();
      const notified = await s.rows<{ user_id: string; type: string }>(
        `select r.user_id, e.type from better_supabase.notification_recipients r
         join better_supabase.notification_events e on e.id = r.event_id
         where e.subject_id = $1`,
        [subject],
      );
      expect(notified).toEqual([
        { user_id: owner.id, type: "comment.mentioned" },
      ]);

      await s.asRole(member);
      const edited = await comments
        .edit(first.id, { body: `Now with @[Viewer](${viewer.id})` })
        .orThrow();
      expect(edited.editedAt).toBeDefined();
      expect(edited.mentions).toEqual([viewer.id]);
      expect(
        await comments.edit(crypto.randomUUID(), { body: "x" }),
      ).toMatchObject({ ok: false, error: { kind: "not_found" } });

      const thread = await comments
        .list(organization, "project", subject)
        .orThrow();
      expect(thread.map((comment) => comment.id)).toEqual([first.id, reply.id]);

      await s.asRole(viewer);
      // Viewers can read neither comments (no comments.read) nor create.
      expect(
        await comments.list(organization, "project", subject).orThrow(),
      ).toEqual([]);

      await s.asRole(owner);
      expect(await comments.remove(first.id).orThrow()).toBe(true);
      expect(await comments.remove(first.id).orThrow()).toBe(false);
      const after = await comments
        .list(organization, "project", subject)
        .orThrow();
      expect(after[0]).toMatchObject({ body: "", mentions: [] });
      expect(after[0]?.deletedAt).toBeDefined();

      await s.asRole(outsider);
      expect(
        await comments.list(organization, "project", subject).orThrow(),
      ).toEqual([]);

      await s.service();
      const events = await s.rows<{
        type: string;
        payload: Record<string, unknown>;
        tenant: string;
      }>(
        `select type, payload, organization_id::text as tenant from better_supabase.outbox_events
         where type like 'comment.%' and organization_id = $1 order by position`,
        [organization],
      );
      // The edit's mention of the viewer, who lacks comments.read, sends nothing.
      expect(events.map((event) => event.type)).toEqual([
        "comment.created",
        "comment.mentioned",
        "comment.created",
        "comment.deleted",
      ]);

      const cloud: CloudEvent[] = events.map((event, index) => ({
        specversion: "1.0",
        id: `evt-${String(index)}`,
        source: "https://app.test",
        type: `dev.better-supabase.${event.type}`,
        subject: `comments/${String(event.payload["commentId"])}`,
        time: "2026-10-06T12:00:00Z",
        data: event.payload,
        partitionkey: event.tenant,
      }));
      const sink = activitySink({
        transport: sqlTransport(s.sql),
        types: ["comment.created", "comment.deleted"],
      });
      await sink.send(cloud);
      await sink.send(cloud);
      const feed = await s.rows<{
        type: string;
        actor_id: string;
        subject_type: string;
      }>(
        `select type, actor_id, subject_type from better_supabase.activity_entries
         where organization_id = $1 order by event_id`,
        [organization],
      );
      expect(feed).toEqual([
        {
          type: "comment.created",
          actor_id: member.id,
          subject_type: "project",
        },
        {
          type: "comment.created",
          actor_id: owner.id,
          subject_type: "project",
        },
        {
          type: "comment.deleted",
          actor_id: member.id,
          subject_type: "project",
        },
      ]);

      await s.asRole(viewer);
      expect(
        await s.rows("select 1 from better_supabase.activity_entries"),
      ).toEqual([]);
      await s.asRole(member);
      expect(
        await s.rows("select 1 from better_supabase.activity_entries"),
      ).toHaveLength(3);
      expect(
        await s.hint("select better_supabase.record_activity('{}')"),
      ).toMatch(/permission denied/);
    } finally {
      await s.close();
    }
  });

  it("keeps a document, copies a thread, cascades deletes and lists a timeline", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.rows(
        `create table public.bs_test_quotes (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null
         );
         alter table public.bs_test_quotes enable row level security;
         grant select, delete on public.bs_test_quotes to authenticated;
         create policy "read" on public.bs_test_quotes for select to authenticated
           using (better_supabase.has_organization_role(organization_id));`,
      );
      await s.install(["organizations", "comments"], {
        modules: {
          comments: {
            options: {
              subjects: {
                quote: { table: "bs_test_quotes", cascade: true },
              },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });
      const [from, to] = await s.rows<{ id: string }>(
        "insert into public.bs_test_quotes (organization_id) values ($1), ($1) returning id",
        [organization],
      );
      const comments = createComments({
        transport: sqlTransport(s.sql),
        mentionsOf: ({ document }) =>
          JSON.stringify(document ?? {}).includes(owner.id) ? [owner.id] : [],
      });
      const document = {
        type: "doc",
        content: [{ type: "mention", id: owner.id }],
      };

      await s.asRole(member);
      const root = await comments
        .create({
          organizationId: organization,
          subjectType: "quote",
          subjectId: from!.id,
          body: "Check this",
          document,
        })
        .orThrow();
      expect(root.document).toEqual(document);
      expect(root.mentions).toEqual([owner.id]);
      await comments
        .create({
          organizationId: organization,
          subjectType: "quote",
          subjectId: from!.id,
          body: "Done",
          parentId: root.id,
        })
        .orThrow();
      const edited = await comments.edit(root.id, { body: "Plain" }).orThrow();
      expect(edited.document).toEqual(document);
      const cleared = await comments
        .edit(root.id, { body: "Plain", document: null })
        .orThrow();
      expect(cleared.document).toBeNull();
      expect(
        (
          await comments.copy(
            organization,
            { type: "quote", id: from!.id },
            { type: "quote", id: to!.id },
          )
        ).ok,
      ).toBe(false);

      await s.service();
      expect(
        await comments
          .copy(
            organization,
            { type: "quote", id: from!.id },
            { type: "quote", id: to!.id },
          )
          .orThrow(),
      ).toBe(2);
      await s.asRole(member);
      const copied = await comments
        .list(organization, "quote", to!.id)
        .orThrow();
      expect(copied.map((comment) => comment.body)).toEqual(["Plain", "Done"]);
      expect(copied[0]!.authorId).toBe(member.id);
      expect(copied[1]!.parentId).toBe(copied[0]!.id);

      await s.service();
      await s.rows("delete from public.bs_test_quotes where id = $1", [
        from!.id,
      ]);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.comments where subject_id = $1)",
          [from!.id],
        ),
      ).toBe(0);

      await s.rows(
        `select better_supabase.record_activity(jsonb_build_object('entries', jsonb_build_array(
           jsonb_build_object('event_id', 'e1', 'organization_id', $1::text, 'type', 'quote.sent',
             'subject_type', 'quote', 'subject_id', $2::text, 'occurred_at', '2026-10-06T10:00:00Z'),
           jsonb_build_object('event_id', 'e2', 'organization_id', $1::text, 'type', 'quote.created',
             'subject_type', 'quote', 'subject_id', $2::text, 'occurred_at', '2026-10-06T09:00:00Z'),
           jsonb_build_object('event_id', 'e3', 'organization_id', $1::text, 'type', 'task.created',
             'subject_type', 'task', 'subject_id', 't1', 'occurred_at', '2026-10-06T11:00:00Z'))))`,
        [organization, to!.id],
      );
      await s.asRole(owner);
      const timeline = await comments
        .history(organization, { type: "quote", id: to!.id })
        .orThrow();
      expect(timeline.map((entry) => entry.type)).toEqual([
        "quote.sent",
        "quote.created",
      ]);
      const page = await comments
        .history(organization, undefined, {
          before: Temporal.Instant.from("2026-10-06T10:30:00Z"),
          limit: 1,
        })
        .orThrow();
      expect(page.map((entry) => entry.type)).toEqual(["quote.sent"]);
    } finally {
      await s.close();
    }
  });
});
