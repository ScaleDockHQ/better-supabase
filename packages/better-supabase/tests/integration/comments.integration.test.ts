import { Client, Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createAttachments } from "../../src/blocks/attachments/index.ts";
import {
  createComments,
  sqlTransport,
} from "../../src/blocks/comments/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "messaging",
  "comments",
];

/**
 * A record table its own policies guard: members of the tenant read a row, and
 * a private one only its owner.
 */
async function recordTable(s: BlockSession, name: string): Promise<string> {
  const table = `public.bs_test_${name}_${crypto.randomUUID().slice(0, 8)}`;
  await s.rows(
    `create table ${table} (
       id uuid primary key default gen_random_uuid(),
       organization_id uuid not null,
       title text not null default 'Untitled',
       owner_id uuid,
       private boolean not null default false
     );
     alter table ${table} enable row level security;
     grant select, delete on ${table} to authenticated;
     create policy "read" on ${table} for select to authenticated
       using (better_supabase.has_organization_role(organization_id)
         and (not private or owner_id = (select auth.uid())));`,
  );

  return table;
}

describe.skipIf(!live)("comments", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("copies a thread in a PostgREST session, where pg-safeupdate refuses a delete without where", async () => {
    const url = new URL(dbUrl);
    url.username = "authenticator";
    const client = new Client({ connectionString: url.toString() });
    await client.connect();

    try {
      await client.query("begin");
      await client.query(
        "create temporary table bs_probe (x int) on commit drop",
      );
      await client.query("savepoint probe");
      await expect(client.query("delete from bs_probe")).rejects.toThrow(
        /DELETE requires a WHERE clause/,
      );
      await client.query("rollback to savepoint probe");
      await client.query("set local role service_role");
      await client.query(
        `select set_config('request.jwt.claims', '{"role":"service_role"}', true)`,
      );
      const tenant = crypto.randomUUID();

      const copy = () =>
        client.query<{ copied: number }>(
          "select better_supabase.copy_comments($1, 'quote', 'q1', 'invoice', 'i1') as copied",
          [tenant],
        );

      expect((await copy()).rows).toEqual([{ copied: 0 }]);
      expect((await copy()).rows).toEqual([{ copied: 0 }]);
      await client.query("rollback");
    } finally {
      await client.end();
    }
  });

  it("threads comments on readable records, notifies mentioned readers and emits message events", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await recordTable(s, "projects");
      await s.install(MODULES, { subjects: { project: { table } } });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const viewer = await s.user("viewer");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { member, viewer });

      const [project] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id, title) values ($1, 'Apollo') returning id`,
        [organization],
      );

      const subject = { type: "project", id: project!.id };

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(member);

      const first = await comments
        .create(subject, {
          body: `Ready for review @[Owner](${owner.id}) @[Me](${member.id}) @[Out](${outsider.id})`,
        })
        .orThrow();

      expect(first).toMatchObject({
        organizationId: organization,
        subject,
        authorId: member.id,
        parentId: undefined,
        threadId: undefined,
        editedAt: undefined,
        taskId: undefined,
      });
      expect(first.sentAt).toBeDefined();
      // The outsider stays in the column but isn't notified.
      expect(first.mentionIds).toEqual(
        expect.arrayContaining([owner.id, outsider.id]),
      );
      // The mention notification sends as the service role and restores the caller.
      expect(await s.value("auth.uid()")).toBe(member.id);
      expect(await s.value("auth.role()")).toBe("authenticated");

      expect(
        await comments.create(
          { type: "project", id: crypto.randomUUID() },
          { body: "No such project" },
        ),
      ).toMatchObject({ ok: false });
      expect(
        await comments.create(
          { type: "invoice", id: project!.id },
          { body: "Not a subject type" },
        ),
      ).toMatchObject({ ok: false });

      await s.asRole(owner);

      const reply = await comments
        .create(subject, { body: "Looks good", parentId: first.id })
        .orThrow();

      expect(reply).toMatchObject({ parentId: first.id, threadId: first.id });
      expect(await comments.get(first.id).orThrow()).toMatchObject({
        replyCount: 1,
        replyUserIds: [owner.id],
      });
      expect(
        await comments.edit(first.id, { body: "Owner editing" }),
      ).toMatchObject({ ok: false, error: { hint: "MESSAGING_NOT_FOUND" } });

      await s.service();

      const notified = await s.rows<{ user_id: string; type: string }>(
        `select r.user_id, e.type from better_supabase.notification_recipients r
         join better_supabase.notification_events e on e.id = r.event_id
         where e.organization_id = $1 and e.type = 'message.mentioned'`,
        [organization],
      );

      expect(notified).toEqual([
        { user_id: owner.id, type: "message.mentioned" },
      ]);

      await s.asRole(member);

      const edited = await comments
        .edit(first.id, { body: `Now with @[Viewer](${viewer.id})` })
        .orThrow();

      expect(edited.editedAt).toBeDefined();
      expect(edited.mentionIds).toEqual([viewer.id]);
      expect(
        await comments.edit(crypto.randomUUID(), { body: "x" }),
      ).toMatchObject({ ok: false, error: { kind: "not_found" } });
      expect(await comments.get(crypto.randomUUID())).toMatchObject({
        ok: false,
        error: { kind: "not_found", hint: "COMMENT_NOT_FOUND" },
      });

      const thread = await comments.list(subject).orThrow();

      // One transaction fixes now(): rows sent together order by id.
      expect(thread.map((comment) => comment.id).toSorted()).toEqual(
        [first.id, reply.id].toSorted(),
      );
      expect(
        thread.find((comment) => comment.id === reply.id)?.subject,
      ).toEqual(subject);

      // A viewer holds no messages keys: no comments to read, none to post.
      await s.asRole(viewer);
      expect(await comments.list(subject).orThrow()).toEqual([]);
      expect(await comments.create(subject, { body: "Viewer" })).toMatchObject({
        ok: false,
      });

      // The owner moderates: the comment stays as a placeholder.
      await s.asRole(owner);
      expect(await comments.remove(first.id).orThrow()).toBe(true);
      expect(await comments.remove(first.id).orThrow()).toBe(false);

      const after = await comments.list(subject).orThrow();

      const removed = after.find((comment) => comment.id === first.id);

      expect(removed).toMatchObject({ body: "", mentionIds: [] });
      expect(removed?.deletedAt).toBeDefined();
      expect(after.find((comment) => comment.id === reply.id)).toMatchObject({
        body: "Looks good",
      });

      await s.asRole(outsider);
      expect(await comments.list(subject).orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{
        type: string;
        payload: Record<string, unknown>;
      }>(
        `select type, payload from better_supabase.outbox_events
         where organization_id = $1 and (type like 'message.%' or type like 'conversation.%' or type like 'comment.%')
         order by position`,
        [organization],
      );

      // The viewer's edit mention notifies nobody and records no event.
      expect(events.map((event) => event.type)).toEqual([
        "conversation.created",
        "message.sent",
        "message.sent",
        "message.edited",
        "message.deleted",
      ]);
      expect(events[1]!.payload).toMatchObject({
        messageId: first.id,
        authorId: member.id,
        conversationKind: "subject",
        recordType: "project",
        recordId: project!.id,
      });
      expect(events[2]!.payload).toMatchObject({
        messageId: reply.id,
        threadId: first.id,
      });
    } finally {
      await s.close();
    }
  });

  it("hides comments on records the record's own policies hide", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await recordTable(s, "tasks");
      await s.install(MODULES, { subjects: { task: { table } } });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });

      const [hidden, open] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id, owner_id, private) values ($1, $2, true), ($1, $2, false) returning id`,
        [organization, owner.id],
      );

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(owner);

      for (const task of [hidden!, open!]) {
        await comments
          .create({ type: "task", id: task.id }, { body: "Checked" })
          .orThrow();
      }

      const visible = (): Promise<number> =>
        s.value<number>(
          `(select count(*)::int from better_supabase.messages m
            join better_supabase.conversations c on c.id = m.conversation_id
            where c.kind = 'subject' and c.subject_type = 'task')`,
        );

      expect(await visible()).toBe(2);
      await s.asRole(member);
      expect(await visible()).toBe(1);
      expect(
        await comments.list({ type: "task", id: hidden!.id }).orThrow(),
      ).toEqual([]);
      expect(
        await comments.create(
          { type: "task", id: hidden!.id },
          { body: "Let me in" },
        ),
      ).toMatchObject({ ok: false });
      expect(
        await comments
          .counts([
            { type: "task", id: hidden!.id },
            { type: "task", id: open!.id },
          ])
          .orThrow(),
      ).toEqual({ [`task:${hidden!.id}`]: 0, [`task:${open!.id}`]: 1 });
    } finally {
      await s.close();
    }
  });

  it("expands group mentions and keeps them to members who read comments", async () => {
    const s = await BlockSession.open(pool);
    const teams = `public.bs_test_team_members_${crypto.randomUUID().slice(0, 8)}`;

    try {
      const table = await recordTable(s, "projects");
      await s.rows(
        `create table ${teams} (
           team_id uuid not null,
           user_id uuid not null,
           organization_id uuid not null
         );
         grant select on ${teams} to authenticated;`,
      );
      await s.install(MODULES, {
        subjects: { project: { table } },
        modules: {
          comments: {
            options: {
              mentionGroups: {
                table: teams,
                group: "team_id",
                member: "user_id",
                tenant: "organization_id",
              },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const viewer = await s.user("viewer");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { member, viewer });
      const team = crypto.randomUUID();
      const elsewhere = crypto.randomUUID();
      await s.rows(
        `insert into ${teams} (team_id, user_id, organization_id)
         values ($1, $3, $2), ($1, $4, $2), ($1, $5, $2), ($1, $6, $2), ($7, $3, $8)`,
        [
          team,
          organization,
          owner.id,
          member.id,
          viewer.id,
          outsider.id,
          elsewhere,
          crypto.randomUUID(),
        ],
      );

      const [project] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1) returning id`,
        [organization],
      );

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      const recipients = async (): Promise<string[]> => {
        await s.service();

        const rows = await s.rows<{ user_id: string }>(
          `select r.user_id::text from better_supabase.notification_recipients r
           join better_supabase.notification_events e on e.id = r.event_id
           where e.organization_id = $1 and e.type = 'message.mentioned'
           order by e.created_at, r.user_id`,
          [organization],
        );

        await s.asRole(owner);

        return rows.map((row) => row.user_id);
      };

      await s.asRole(owner);

      const comment = await comments
        .create(
          { type: "project", id: project!.id },
          { body: `Team @[Team](${team}) and @[Elsewhere](${elsewhere})` },
        )
        .orThrow();

      // The group ids stay next to the members the team expands to.
      expect(comment.mentionIds).toEqual(
        expect.arrayContaining([team, elsewhere, member.id, viewer.id]),
      );
      expect(await recipients()).toEqual([member.id]);

      await comments
        .edit(comment.id, {
          body: `Team @[Team](${team}) and @[Member](${member.id})`,
        })
        .orThrow();
      expect(await recipients()).toEqual([member.id]);
    } finally {
      await s.close();
    }
  });

  it("checks a record type's read permission and pages and counts comments", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await recordTable(s, "deals");
      await s.install(MODULES, {
        subjects: { deal: { table, permissions: { read: "test_deals.read" } } },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });

      const [deal] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1) returning id`,
        [organization],
      );

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      const subject = { type: "deal", id: deal!.id };

      await s.asRole(member);
      expect(
        await comments.create(subject, { body: "Pricing looks right" }),
      ).toMatchObject({ ok: false });

      await s.asRole(owner);

      const created = await comments
        .create(subject, { body: "First" })
        .orThrow();

      await comments.create(subject, { body: "Second" }).orThrow();
      await comments.create(subject, { body: "Third" }).orThrow();

      await s.asRole(member);
      expect((await comments.get(created.id)).ok).toBe(false);
      expect(await comments.list(subject).orThrow()).toEqual([]);
      expect(await comments.counts([subject]).orThrow()).toEqual({
        [`deal:${deal!.id}`]: 0,
      });

      await s.asRole(owner);
      const all = await comments.list(subject).orThrow();
      expect(all.map((comment) => comment.body).toSorted()).toEqual([
        "First",
        "Second",
        "Third",
      ]);
      expect(
        (await comments.list(subject, { offset: 1, limit: 1 }).orThrow()).map(
          (comment) => comment.id,
        ),
      ).toEqual([all[1]!.id]);

      // One transaction fixes now(): the cursor pages by (sentAt, id).
      const page = await comments
        .list(subject, { cursor: all[0]!.sentAt!, cursorId: all[0]!.id })
        .orThrow();

      expect(page.map((comment) => comment.id)).toEqual(
        all.slice(1).map((comment) => comment.id),
      );
      expect(
        await comments
          .counts([subject, { type: "deal", id: "missing" }])
          .orThrow(),
      ).toEqual({ [`deal:${deal!.id}`]: 3, "deal:missing": 0 });

      await comments.remove(created.id).orThrow();
      expect(await comments.counts([subject]).orThrow()).toEqual({
        [`deal:${deal!.id}`]: 2,
      });
    } finally {
      await s.close();
    }
  });

  it("keeps a document and copies a thread to another record", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await recordTable(s, "quotes");
      await s.install(MODULES, { subjects: { quote: { table } } });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });

      const [from, to] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1), ($1) returning id`,
        [organization],
      );

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: organization,
        mentionsOf: ({ document }) =>
          JSON.stringify(document ?? {}).includes(owner.id) ? [owner.id] : [],
      });

      const document = {
        type: "doc",
        content: [{ type: "mention", id: owner.id }],
      };

      await s.asRole(member);

      const root = await comments
        .create(
          { type: "quote", id: from!.id },
          { body: "Check this", document },
        )
        .orThrow();

      expect(root.document).toEqual(document);
      expect(root.mentionIds).toEqual([owner.id]);
      await comments
        .create(
          { type: "quote", id: from!.id },
          { body: "Done", parentId: root.id },
        )
        .orThrow();

      const edited = await comments.edit(root.id, { body: "Plain" }).orThrow();

      expect(edited.document).toEqual(document);

      const cleared = await comments
        .edit(root.id, { body: "Plain", document: null })
        .orThrow();

      expect(cleared.document).toBeUndefined();
      expect(
        (
          await comments.copy(
            { type: "quote", id: from!.id },
            { type: "quote", id: to!.id },
          )
        ).ok,
      ).toBe(false);

      await s.service();
      expect(
        await comments
          .copy({ type: "quote", id: from!.id }, { type: "quote", id: to!.id })
          .orThrow(),
      ).toBe(2);
      await s.asRole(member);

      const copied = await comments
        .list({ type: "quote", id: to!.id })
        .orThrow();

      const copiedRoot = copied.find(
        (comment) => comment.parentId === undefined,
      );

      const copiedReply = copied.find(
        (comment) => comment.parentId !== undefined,
      );

      expect(copiedRoot).toMatchObject({
        body: "Plain",
        authorId: member.id,
        replyCount: 1,
      });
      expect(copiedRoot!.id).not.toBe(root.id);
      expect(copiedReply).toMatchObject({
        body: "Done",
        parentId: copiedRoot!.id,
        threadId: copiedRoot!.id,
      });
      expect(
        await comments.conversation({ type: "quote", id: to!.id }).orThrow(),
      ).not.toBe(
        await comments.conversation({ type: "quote", id: from!.id }).orThrow(),
      );
    } finally {
      await s.close();
    }
  });

  it("makes participants follow the record and tells its followers of new comments", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await recordTable(s, "quotes");
      const layout: ModuleLayout = { subjects: { quote: { table } } };
      await s.install(MODULES, layout);
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const member = await s.user("member");
      const member2 = await s.user("member2");

      const organization = await s.organization(owner, {
        admin,
        member,
        member2,
      });

      const [quote, quiet] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1), ($1) returning id`,
        [organization],
      );

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.service();
      await s.rows(
        `insert into better_supabase.notification_subscriptions (organization_id, user_id, subject_type, subject_id, level)
         values ($1, $2, 'quote', $3, 'ignore')`,
        [organization, admin.id, quote!.id],
      );

      await s.asRole(member);
      await comments
        .create(
          { type: "quote", id: quote!.id },
          { body: `@[Owner](${owner.id}) @[Admin](${admin.id})` },
        )
        .orThrow();
      await s.service();

      const levels = await s.rows<{ user_id: string; level: string }>(
        `select user_id, level from better_supabase.notification_subscriptions
         where subject_type = 'quote' and subject_id = $1 order by level, user_id`,
        [quote!.id],
      );

      expect(levels).toEqual([
        { user_id: admin.id, level: "ignore" },
        ...[member.id, owner.id]
          .toSorted()
          .map((id) => ({ user_id: id, level: "participating" })),
      ]);

      await s.asRole(member2);
      await comments
        .create({ type: "quote", id: quote!.id }, { body: "Agreed" })
        .orThrow();
      await s.service();

      const posted = await s.rows<{ user_id: string }>(
        `select r.user_id::text from better_supabase.notification_recipients r
         join better_supabase.notification_events e on e.id = r.event_id
         where e.type = 'comment.posted' and e.subject_type = 'quote' and e.subject_id = $1
         order by r.user_id`,
        [quote!.id],
      );

      // member2's own comment and admin's ignore leave the other two.
      expect(posted.map((row) => row.user_id)).toEqual(
        [member.id, owner.id].toSorted(),
      );

      await s.install(MODULES, {
        ...layout,
        modules: { comments: { options: { follow: false } } },
      });
      await s.asRole(member);
      await comments
        .create({ type: "quote", id: quiet!.id }, { body: "Not following" })
        .orThrow();
      await s.service();
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.notification_subscriptions where subject_type = 'quote' and subject_id = $1)",
          [quiet!.id],
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });

  it("resolves and pins threads, keeps edit history and anchors comments", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await recordTable(s, "docs");
      await s.install(MODULES, { subjects: { doc: { table } } });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const viewer = await s.user("viewer");
      const organization = await s.organization(owner, { member, viewer });

      const [doc] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1) returning id`,
        [organization],
      );

      const subject = { type: "doc", id: doc!.id };

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      const anchor = { kind: "range", from: 12, to: 40, quote: "the pump" };

      await s.asRole(member);

      const root = await comments
        .create(subject, { body: "Is this right?", anchor })
        .orThrow();

      expect(root.anchor).toEqual(anchor);

      const reply = await comments
        .create(subject, { body: "Checking", parentId: root.id })
        .orThrow();

      await comments.edit(root.id, { body: "Is this right? v2" }).orThrow();
      await comments.edit(root.id, { body: "Is this right? v3" }).orThrow();

      const edits = await comments.edits(root.id).orThrow();

      expect(edits.map((edit) => edit.body).toSorted()).toEqual(
        ["Is this right?", "Is this right? v2"].toSorted(),
      );
      expect(edits.every((edit) => edit.editedBy === member.id)).toBe(true);
      expect(edits.every((edit) => edit.messageId === root.id)).toBe(true);

      await s.asRole(owner);

      const resolved = await comments.resolve(root.id).orThrow();

      expect(resolved.resolvedBy).toBe(owner.id);
      expect(resolved.resolvedAt).toBeDefined();
      // A reply is not a thread.
      expect((await comments.resolve(reply.id)).ok).toBe(false);

      const reopened = await comments.resolve(root.id, false).orThrow();

      expect(reopened.resolvedAt).toBeUndefined();
      expect(reopened.resolvedBy).toBeUndefined();

      const pinned = await comments.pin(reply.id).orThrow();

      expect(pinned).toMatchObject({ pinnedBy: owner.id });
      expect(
        (await comments.list(subject).orThrow()).find(
          (comment) => comment.id === reply.id,
        )?.pinnedAt,
      ).toBeDefined();
      expect(
        (await comments.pin(reply.id, false).orThrow()).pinnedAt,
      ).toBeUndefined();

      // A viewer reads nothing, so resolves and pins nothing.
      await s.asRole(viewer);
      expect((await comments.resolve(root.id)).ok).toBe(false);
      expect((await comments.pin(root.id)).ok).toBe(false);
      expect(await comments.edits(root.id).orThrow()).toHaveLength(0);

      // Deleting a comment drops its history.
      await s.asRole(member);
      await comments.remove(root.id).orThrow();
      expect(await comments.edits(root.id).orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{
        type: string;
        payload: Record<string, unknown>;
      }>(
        `select type, payload from better_supabase.outbox_events
         where organization_id = $1 and type in ('message.resolved', 'message.pinned')
         order by position`,
        [organization],
      );

      expect(
        events.map((event) => [
          event.type,
          event.payload["resolved"] ?? event.payload["pinned"],
        ]),
      ).toEqual([
        ["message.resolved", true],
        ["message.resolved", false],
        ["message.pinned", true],
        ["message.pinned", false],
      ]);
    } finally {
      await s.close();
    }
  });

  it("attaches files uploaded to the record's conversation to a comment", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await recordTable(s, "projects");
      await s.install(
        [...MODULES.slice(0, -2), "attachments", ...MODULES.slice(-2)],
        {
          subjects: withBlockSubjects(
            { project: { table } },
            ["messaging"],
            {},
          ),
          modules: {
            attachments: { options: { bucket: "bs-it-comment-files" } },
          },
        },
      );
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });

      const [project] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1) returning id`,
        [organization],
      );

      const subject = { type: "project", id: project!.id };
      const transport = sqlTransport(s.sql);

      const comments = createComments({
        transport,
        tenant: () => organization,
      });

      const attachments = createAttachments({
        transport,
        tenant: organization,
        storage: {
          from: () => ({
            createSignedUploadUrl: (path) =>
              Promise.resolve({
                data: { signedUrl: `https://storage.test/${path}`, token: "t" },
                error: null,
              }),
            createSignedUrl: (path) =>
              Promise.resolve({
                data: { signedUrl: `https://storage.test/${path}` },
                error: null,
              }),
            download: () =>
              Promise.resolve({ data: new Blob([]), error: null }),
            remove: () => Promise.resolve({ data: [], error: null }),
          }),
        },
      });

      await s.asRole(member);
      expect(await comments.conversation(subject).orThrow()).toBeUndefined();

      const conversation = await comments
        .conversation(subject, { open: true })
        .orThrow();

      expect(conversation).toBeDefined();
      expect(await comments.conversation(subject).orThrow()).toBe(conversation);

      const { attachment } = await attachments
        .upload(
          { type: "conversation", id: conversation! },
          { name: "plan.pdf", mimeType: "application/pdf", size: 10 },
        )
        .orThrow();

      const comment = await comments
        .create(subject, { body: "The plan", attachmentIds: [attachment.id] })
        .orThrow();

      expect(comment.attachments.map((file) => file.id)).toEqual([
        attachment.id,
      ]);
      expect(comment.attachments[0]).toMatchObject({ name: "plan.pdf" });

      // A file can't be attached twice, nor one someone else uploaded.
      expect(
        await comments.create(subject, {
          body: "Again",
          attachmentIds: [attachment.id],
        }),
      ).toMatchObject({ ok: false });

      await s.service();
      expect(
        await s.rows(
          "select subject_type, subject_id from better_supabase.attachments where id = $1",
          [attachment.id],
        ),
      ).toEqual([{ subject_type: "message", subject_id: comment.id }]);
    } finally {
      await s.close();
    }
  });

  it("deletes a record's comments with the record when its type cascades", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await recordTable(s, "cascading");
      await s.install(MODULES, {
        subjects: { project: { table, cascade: true } },
      });
      const owner = await s.user("owner");
      const organization = await s.organization(owner);

      const [project] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1) returning id`,
        [organization],
      );

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: organization,
      });

      await s.asRole(owner);

      const comment = await comments
        .create({ type: "project", id: project!.id }, { body: "Gone soon" })
        .orThrow();

      await s.service();
      await s.rows(`delete from ${table} where id = $1`, [project!.id]);

      expect(
        await s.rows("select 1 from better_supabase.messages where id = $1", [
          comment.id,
        ]),
      ).toEqual([]);
      expect(
        await s.rows(
          "select 1 from better_supabase.conversations where subject_id = $1",
          [project!.id],
        ),
      ).toEqual([]);
    } finally {
      await s.close();
    }
  });

  it("turns a comment into a work item once", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await recordTable(s, "projects");
      await s.install(
        [
          "organizations",
          "outbox",
          "notifications",
          "subjects",
          "rank",
          "relations",
          "pipelines",
          "work-items",
          "messaging",
          "comments",
        ],
        {
          subjects: withBlockSubjects(
            { project: { table } },
            ["work-items"],
            {},
          ),
          modules: {
            "work-items": {
              tables: { projects: "work_projects" },
              options: { maxAssignees: 0 },
            },
          },
        },
      );
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });

      const [project] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1) returning id`,
        [organization],
      );

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(member);

      const comment = await comments
        .create(
          { type: "project", id: project!.id },
          { body: "Replace the pump before Friday" },
        )
        .orThrow();

      const task = await comments
        .assign(comment.id, { assigneeId: member.id })
        .orThrow();

      expect(await comments.assign(comment.id).orThrow()).toBe(task);
      expect((await comments.get(comment.id).orThrow()).taskId).toBe(task);

      await s.service();
      expect(
        await s.rows(
          "select title, body from better_supabase.work_items where id = $1",
          [task],
        ),
      ).toEqual([
        {
          title: "Replace the pump before Friday",
          body: "Replace the pump before Friday",
        },
      ]);

      await s.asRole(member);
      expect(await comments.assign(crypto.randomUUID())).toMatchObject({
        ok: false,
        error: { hint: "COMMENT_NOT_FOUND" },
      });
    } finally {
      await s.close();
    }
  });

  it("moves version 7 comments and their reactions onto the messaging core", async () => {
    const s = await BlockSession.open(pool);

    try {
      const installed = [
        "organizations",
        "subjects",
        "reactions",
        "messaging",
        "comments",
      ];

      const table = await recordTable(s, "projects");
      const layout: ModuleLayout = { subjects: { project: { table } } };
      await s.install(installed, layout);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });

      const [project] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1) returning id`,
        [organization],
      );

      const [root, reply, edited, removed] = [
        crypto.randomUUID(),
        crypto.randomUUID(),
        crypto.randomUUID(),
        crypto.randomUUID(),
      ];

      await s.service();
      await s.rows(
        `create table better_supabase.comments (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           subject_type text not null,
           subject_id text not null,
           author_id uuid,
           body text not null,
           document jsonb,
           mentions uuid[] not null default '{}',
           parent_id uuid references better_supabase.comments (id),
           created_at timestamptz not null default now(),
           edited_at timestamptz,
           deleted_at timestamptz
         )`,
      );
      await s.rows(
        `insert into better_supabase.comments (id, organization_id, subject_type, subject_id, author_id, body, mentions, parent_id, created_at, edited_at, deleted_at)
         values
           ($1::uuid, $5::uuid, 'project', $6::uuid, $7::uuid, 'Root @[Member](' || $8::text || ')', array[$8::uuid], null, '2026-10-01T10:00:00Z', null, null),
           ($2::uuid, $5, 'project', $6, $8::uuid, 'Reply', '{}', $1::uuid, '2026-10-01T11:00:00Z', null, null),
           ($3::uuid, $5, 'project', $6, $8::uuid, 'Edited', '{}', $2::uuid, '2026-10-01T12:00:00Z', '2026-10-01T12:30:00Z', null),
           ($4::uuid, $5, 'project', $6, $7, '', '{}', $1, '2026-10-01T13:00:00Z', null, '2026-10-01T13:30:00Z')`,
        [
          root,
          reply,
          edited,
          removed,
          organization,
          project!.id,
          owner.id,
          member.id,
        ],
      );
      await s.rows(
        `insert into better_supabase.reactions (tenant_id, subject_type, subject_id, actor, user_id, emoji)
         values ($1, 'comment', $2, $3, $4, 'thumbsup')`,
        [organization, root, member.id, member.id],
      );

      const plans = upgradePlan(
        [
          ...installed
            .filter((module) => module !== "comments")
            .map((module) => ({ module, version: 1000 })),
          { module: "comments", version: 7 },
        ],
        layout,
      );

      expect(plans.map((plan) => plan.module)).toEqual(["comments"]);

      for (const plan of plans) {
        for (const step of plan.steps) {
          await s.rows(step.sql);
        }
      }

      expect(
        await s.value<string | null>(
          "to_regclass('better_supabase.comments')::text",
        ),
      ).toBeNull();

      const conversations = await s.rows<{ id: string; created_by: string }>(
        `select id, created_by from better_supabase.conversations
         where tenant_id = $1 and kind = 'subject' and access = 'subject'
           and subject_type = 'project' and subject_id = $2`,
        [organization, project!.id],
      );

      expect(conversations).toEqual([
        { id: expect.any(String), created_by: owner.id },
      ]);

      const messages = await s.rows<{
        id: string;
        conversation_id: string;
        parent_id: string | null;
        thread_id: string | null;
        author_id: string;
        mentions: string[];
        reply_count: number;
        sent_at: Date;
        edited_at: Date | null;
        deleted_at: Date | null;
      }>(
        `select id, conversation_id, parent_id, thread_id, author_id, mentions, reply_count, sent_at, edited_at, deleted_at
         from better_supabase.messages where id = any ($1::uuid[]) order by sent_at`,
        [[root, reply, edited, removed]],
      );

      expect(messages.map((message) => message.id)).toEqual([
        root,
        reply,
        edited,
        removed,
      ]);
      expect(
        messages.every(
          (message) => message.conversation_id === conversations[0]!.id,
        ),
      ).toBe(true);
      expect(
        messages.map((message) => [message.parent_id, message.thread_id]),
      ).toEqual([
        [null, null],
        [root, root],
        [reply, root],
        [root, root],
      ]);
      // The deleted reply doesn't count.
      expect(messages[0]).toMatchObject({
        author_id: owner.id,
        mentions: [member.id],
        reply_count: 2,
      });
      expect(messages[0]!.sent_at.toISOString()).toBe(
        "2026-10-01T10:00:00.000Z",
      );
      expect(messages[2]!.edited_at?.toISOString()).toBe(
        "2026-10-01T12:30:00.000Z",
      );
      expect(messages[3]!.deleted_at?.toISOString()).toBe(
        "2026-10-01T13:30:00.000Z",
      );
      expect(
        await s.rows(
          "select subject_type, subject_id from better_supabase.reactions where tenant_id = $1",
          [organization],
        ),
      ).toEqual([{ subject_type: "message", subject_id: root }]);

      // The moved thread reads through the comments client.
      await s.asRole(member);

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      const thread = await comments
        .list({ type: "project", id: project!.id })
        .orThrow();

      expect(thread.map((comment) => comment.body)).toEqual([
        `Root @[Member](${member.id})`,
        "Reply",
        "Edited",
        "",
      ]);
      expect(thread[0]).toMatchObject({
        mentionIds: [member.id],
        replyCount: 2,
      });
    } finally {
      await s.close();
    }
  });
});
