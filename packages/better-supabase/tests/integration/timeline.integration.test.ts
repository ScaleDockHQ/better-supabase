import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { CloudEvent } from "../../src/events/index.ts";

import { createComments } from "../../src/blocks/comments/index.ts";
import {
  activitySink,
  createTimeline,
  sqlTransport,
} from "../../src/blocks/timeline/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

/**
 * A record table its own policies guard: members of the tenant read a row, and
 * one with an owner only that owner.
 */
async function ownedTable(s: BlockSession, name: string): Promise<string> {
  const table = `public.bsb_test_${name}_${crypto.randomUUID().slice(0, 8)}`;
  await s.rows(
    `create table ${table} (
       id uuid primary key default gen_random_uuid(),
       organization_id uuid not null,
       owner_id uuid,
       total integer not null default 0
     );
     alter table ${table} enable row level security;
     grant select, update on ${table} to authenticated;
     create policy "read" on ${table} for select to authenticated
       using (better_supabase.has_organization_role(organization_id)
         and (owner_id is null or owner_id = (select auth.uid())));`,
  );

  return table;
}

describe.skipIf(!live)("activity", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("records comment events through activitySink once, for members with activity.read", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await ownedTable(s, "projects");
      await s.install(
        [
          "organizations",
          "outbox",
          "notifications",
          "subjects",
          "messaging",
          "comments",
          "timeline",
        ],
        { subjects: { project: { table } } },
      );
      const owner = await s.user("owner");
      const member = await s.user("member");
      const viewer = await s.user("viewer");
      const organization = await s.organization(owner, { member, viewer });

      const [project] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1) returning id`,
        [organization],
      );

      const subject = { type: "project", id: project!.id };

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(member);

      const first = await comments
        .create(subject, { body: "Ready for review" })
        .orThrow();

      await s.asRole(owner);
      await comments
        .create(subject, { body: "Looks good", parentId: first.id })
        .orThrow();
      await comments.remove(first.id).orThrow();

      await s.service();

      const events = await s.rows<{
        type: string;
        payload: Record<string, unknown>;
        tenant: string;
      }>(
        `select type, payload, organization_id::text as tenant from better_supabase.outbox_events
         where organization_id = $1 and type like 'message.%' order by position`,
        [organization],
      );

      expect(events.map((event) => event.type)).toEqual([
        "message.sent",
        "message.sent",
        "message.deleted",
      ]);

      const cloud: CloudEvent[] = events.map((event, index) => ({
        specversion: "1.0",
        id: `evt-${String(index)}`,
        source: "https://app.test",
        type: `dev.better-supabase.${event.type}`,
        subject: `messages/${String(event.payload["messageId"])}`,
        time: `2026-10-06T12:0${String(index)}:00Z`,
        data: event.payload,
        partitionkey: event.tenant,
      }));

      const sink = activitySink({
        transport: sqlTransport(s.sql),
        types: ["message.sent"],
      });

      await sink.send(cloud);
      await sink.send(cloud);

      const feed = await s.rows<{
        type: string;
        actor_id: string;
        subject_type: string;
        subject_id: string;
      }>(
        `select type, actor_id, subject_type, subject_id from better_supabase.activity_entries
         where organization_id = $1 order by event_id`,
        [organization],
      );

      // The payload's record, not the message, is the entry's subject.
      expect(feed).toEqual([
        {
          type: "message.sent",
          actor_id: member.id,
          subject_type: "project",
          subject_id: project!.id,
        },
        {
          type: "message.sent",
          actor_id: owner.id,
          subject_type: "project",
          subject_id: project!.id,
        },
      ]);

      const activity = createTimeline({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(viewer);
      expect(
        await s.rows("select 1 from better_supabase.activity_entries"),
      ).toEqual([]);
      await s.asRole(member);
      expect(
        (await activity.list(subject, { sources: ["event"] }).orThrow()).map(
          (entry) => entry.actorId,
        ),
      ).toEqual([owner.id, member.id]);
      expect(
        (await activity.list(subject, { sources: ["message"] }).orThrow()).map(
          (entry) => [entry.type, entry.actorId, entry.summary],
        ),
      ).toEqual([["comment.posted", owner.id, "Looks good"]]);
      expect(
        await s.hint("select better_supabase.record_activity('{}')"),
      ).toMatch(/permission denied/);
    } finally {
      await s.close();
    }
  });

  it("lists a subject's timeline and pages the tenant feed by instant", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "timeline"], {});
      const owner = await s.user("owner");
      const organization = await s.organization(owner, {});
      const quote = crypto.randomUUID();

      await s.rows(
        `select better_supabase.record_activity(jsonb_build_object('entries', jsonb_build_array(
           jsonb_build_object('event_id', 'e1', 'organization_id', $1::text, 'type', 'quote.sent',
             'subject_type', 'quote', 'subject_id', $2::text, 'occurred_at', '2026-10-06T10:00:00Z'),
           jsonb_build_object('event_id', 'e2', 'organization_id', $1::text, 'type', 'quote.created',
             'subject_type', 'quote', 'subject_id', $2::text, 'occurred_at', '2026-10-06T09:00:00Z'),
           jsonb_build_object('event_id', 'e3', 'organization_id', $1::text, 'type', 'task.created',
             'subject_type', 'task', 'subject_id', 't1', 'occurred_at', '2026-10-06T11:00:00Z'))))`,
        [organization, quote],
      );
      await s.asRole(owner);

      const activity = createTimeline({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      const timeline = await activity
        .list({ type: "quote", id: quote })
        .orThrow();

      expect(timeline.map((entry) => entry.type)).toEqual([
        "quote.sent",
        "quote.created",
      ]);
      expect(timeline[0]).toMatchObject({
        source: "event",
        organizationId: organization,
        subject: { type: "quote", id: quote },
      });
      expect(timeline[0]!.occurredAt.toString()).toBe("2026-10-06T10:00:00Z");

      const page = await activity
        .list(undefined, {
          cursor: Temporal.Instant.from("2026-10-06T10:30:00Z"),
          limit: 1,
        })
        .orThrow();

      expect(page.map((entry) => entry.type)).toEqual(["quote.sent"]);
      expect(
        (await activity.list().orThrow()).map((entry) => entry.type),
      ).toEqual(["task.created", "quote.sent", "quote.created"]);
    } finally {
      await s.close();
    }
  });

  it("filters entries through can_subject and adds the subject's audit entries", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await ownedTable(s, "quotes");
      await s.install(
        ["organizations", "notifications", "audit", "subjects", "timeline"],
        {
          subjects: { quote: { table: table.replace("public.", "") } },
          modules: { audit: { options: { readPolicy: true } } },
        },
      );
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const member = await s.user("member");
      const organization = await s.organization(owner, { admin, member });
      await s.rows("select better_supabase.audit($1)", [table]);

      const [open, mine] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id, owner_id) values ($1, null), ($1, $2) returning id`,
        [organization, owner.id],
      );

      const entry = (event: string, type: string, subject: string) => ({
        event_id: event,
        organization_id: organization,
        type,
        subject_type: type.split(".")[0],
        subject_id: subject,
        occurred_at: "2026-10-06T10:00:00Z",
      });

      await s.rows("select better_supabase.record_activity($1)", [
        {
          entries: [
            entry("a1", "quote.sent", open!.id),
            entry("a2", "quote.sent", mine!.id),
            entry("a3", "task.created", "t1"),
          ],
        },
      ]);

      const activity = createTimeline({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(admin);

      const timeline = await activity
        .list({ type: "quote", id: open!.id })
        .orThrow();

      expect(
        timeline
          .map((item) => `${item.source} ${item.type}`)
          .toSorted((a, b) => a.localeCompare(b)),
      ).toEqual([
        `audit ${table.replace("public.", "")}.created`,
        "event quote.sent",
      ]);
      expect(timeline.find((item) => item.source === "audit")).toMatchObject({
        organizationId: organization,
        subject: { type: "quote", id: open!.id },
        data: { op: "insert", table },
      });
      // The owner's own quote is hidden from the admin by its policy.
      expect(
        await activity.list({ type: "quote", id: mine!.id }).orThrow(),
      ).toEqual([]);

      const feed = await activity.list().orThrow();

      const byText = (
        a: string | null | undefined,
        b: string | null | undefined,
      ): number => (a ?? "").localeCompare(b ?? "");

      expect(feed.map((item) => item.subject?.id).toSorted(byText)).toEqual(
        [open!.id, "t1"].toSorted(byText),
      );
      expect(feed.every((item) => item.source === "event")).toBe(true);

      await s.asRole(member);
      expect(
        (await activity.list({ type: "quote", id: open!.id }).orThrow()).map(
          (item) => item.source,
        ),
      ).toEqual(["event"]);
    } finally {
      await s.close();
    }
  });

  it("adds a subject's notification deliveries and workflow runs, filtered by sources", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = await ownedTable(s, "deals");
      await s.install(
        ["organizations", "notifications", "workflows", "subjects", "timeline"],
        { subjects: { deal: { table: table.replace("public.", "") } } },
      );
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const stranger = await s.user("stranger");
      const organization = await s.organization(owner, { admin });

      const [open, mine] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id, owner_id) values ($1, null), ($1, $2) returning id`,
        [organization, admin.id],
      );

      await s.rows("select better_supabase.record_activity($1)", [
        {
          entries: [
            {
              event_id: "d1",
              organization_id: organization,
              type: "deal.won",
              subject_type: "deal",
              subject_id: open!.id,
              occurred_at: "2026-10-06T10:00:00Z",
            },
          ],
        },
      ]);

      for (const deal of [open!.id, mine!.id]) {
        await s.rows(
          `with ev as (
             insert into better_supabase.notification_events (organization_id, type, subject_type, subject_id, summary)
             values ($1, 'deal.won', 'deal', $2, 'Deal won') returning id
           ), rc as (
             insert into better_supabase.notification_recipients (event_id, organization_id, user_id)
             select ev.id, $1, $3 from ev returning id
           )
           insert into better_supabase.notification_deliveries (recipient_id, organization_id, channel, status, created_at)
           select rc.id, $1, 'email', 'sent', '2026-10-06T11:00:00Z' from rc`,
          [organization, deal, owner.id],
        );
        await s.rows(
          `insert into better_supabase.workflow_runs (engine, external_id, definition, tenant_id, status, subject_type, subject_id, created_at)
           values ('test', $3, 'close-deal', $1, 'completed', 'deal', $2, '2026-10-06T12:00:00Z')`,
          [organization, deal, `run-${deal}`],
        );
      }

      const activity = createTimeline({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(owner);

      const timeline = await activity
        .list({ type: "deal", id: open!.id })
        .orThrow();

      expect(timeline.map((item) => `${item.source} ${item.type}`)).toEqual([
        "run run.completed",
        "delivery delivery.sent",
        "event deal.won",
      ]);
      expect(timeline[0]).toMatchObject({
        organizationId: organization,
        subject: { type: "deal", id: open!.id },
        data: { definition: "close-deal", status: "completed" },
      });
      expect(timeline[1]).toMatchObject({
        summary: "Deal won",
        data: {
          channel: "email",
          status: "sent",
          notificationType: "deal.won",
          userId: owner.id,
        },
      });
      expect(
        (
          await activity
            .list(
              { type: "deal", id: open!.id },
              { sources: ["delivery", "event"] },
            )
            .orThrow()
        ).map((item) => item.source),
      ).toEqual(["delivery", "event"]);
      expect(
        await activity.list({ type: "deal", id: mine!.id }).orThrow(),
      ).toEqual([]);
      expect(
        (await activity.list().orThrow()).map((item) => item.source),
      ).toEqual(["event"]);

      await s.asRole(admin);
      expect(
        (await activity.list({ type: "deal", id: open!.id }).orThrow()).map(
          (item) => item.source,
        ),
      ).toEqual(["delivery", "event"]);

      await s.asRole(stranger);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.activity_subject_deliveries($1, 'deal', $2, null, 50))",
          [organization, open!.id],
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });
});
