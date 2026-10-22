import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import {
  createModeration,
  sqlTransport,
} from "../../src/blocks/moderation/index.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

interface Comment {
  readonly id: string;
}

interface Review {
  readonly id: string;
  readonly status: string;
  readonly rejectionReason: string | null;
}

const PROJECTS = `create table if not exists public.bs_mod_projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
alter table public.bs_mod_projects enable row level security;
grant select on public.bs_mod_projects to authenticated;
drop policy if exists "read" on public.bs_mod_projects;
create policy "read" on public.bs_mod_projects for select to authenticated
  using (better_supabase.has_organization_role(organization_id));
create table if not exists public.bs_mod_tickets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);`;

async function project(s: BlockSession, tenant: string): Promise<string> {
  await s.service();

  const [row] = await s.rows<{ id: string }>(
    "insert into public.bs_mod_projects (organization_id) values ($1) returning id",
    [tenant],
  );

  return row!.id;
}

async function comment(
  s: BlockSession,
  author: TestUser,
  tenant: string,
  projectId: string,
  body: string,
): Promise<string> {
  await s.as(author);

  const created = await s.value<Comment>(
    "better_supabase.create_comment($1, 'project', $2, $3)",
    [tenant, projectId, body],
  );

  return created.id;
}

/** Whether `user` reads the comment through the table's policies. */
async function reads(
  s: BlockSession,
  user: TestUser,
  commentId: string,
): Promise<boolean> {
  await s.asRole(user);

  const rows = await s.rows(
    "select id from better_supabase.comments where id = $1",
    [commentId],
  );

  await s.client.query("reset role");

  return rows.length === 1;
}

describe.skipIf(!live)("moderation", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("hides comments after enough reports, and moderators decide, remove and ban", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(PROJECTS);
      await s.install(
        ["organizations", "outbox", "audit", "comments", "moderation"],
        {
          modules: {
            comments: {
              options: { subjects: { project: { table: "bs_mod_projects" } } },
            },
            moderation: {
              options: { autoHideThreshold: 2, reasons: ["spam", "rude"] },
            },
          },
        },
      );
      const owner = await s.user("owner");
      const writer = await s.user("writer");
      const first = await s.user("first");
      const second = await s.user("second");

      const tenant = await s.organization(owner, {
        member: writer,
        member2: first,
        member3: second,
      });

      const projectId = await project(s, tenant);
      const spam = await comment(s, writer, tenant, projectId, "Cheap watches");

      await s.as(first);

      const asFirst = createModeration({
        transport: sqlTransport(s.sql),
        tenant,
      });

      expect(
        await s.hint(
          "better_supabase.report_content($1, 'comment', $2, 'abuse')",
          [tenant, spam],
        ),
      ).toBe("MODERATION_INVALID");
      expect(
        await s.hint(
          "better_supabase.report_content($1, 'comment', $2, 'spam')",
          [tenant, crypto.randomUUID()],
        ),
      ).toBe("MODERATION_SUBJECT_NOT_FOUND");
      expect(
        await asFirst
          .report({ type: "comment", id: spam }, { reason: "spam" })
          .orThrow(),
      ).toMatchObject({ status: "open", reason: "spam", autoHidden: false });
      expect((await asFirst.queue()).ok).toBe(false);
      expect(await asFirst.statuses("comment", [spam]).orThrow()).toEqual({});

      await s.as(second);
      expect(
        await s.value<{ autoHidden: boolean }>(
          "better_supabase.report_content($1, 'comment', $2, 'rude', 'Ads')",
          [tenant, spam],
        ),
      ).toMatchObject({ autoHidden: true });
      expect(await reads(s, second, spam)).toBe(false);
      expect(await reads(s, writer, spam)).toBe(true);

      await s.as(owner);

      const asOwner = createModeration({
        transport: sqlTransport(s.sql),
        tenant,
      });

      expect(await reads(s, owner, spam)).toBe(true);

      const [queued] = await asOwner.queue().orThrow();

      expect(queued).toMatchObject({
        subject: { type: "comment", id: spam },
        authorId: writer.id,
        status: "hidden",
        openReports: 2,
      });
      expect(queued?.decidedBy).toBeUndefined();

      const detail = await asOwner
        .item({ type: "comment", id: spam })
        .orThrow();

      expect(detail?.reports).toHaveLength(2);
      expect(detail?.actions.map((action) => action.action)).toEqual([
        "auto_hide",
      ]);

      const restored = await asOwner.decide(queued!.id, "restore").orThrow();

      expect(restored).toMatchObject({ status: "visible", openReports: 0 });
      expect(await reads(s, second, spam)).toBe(true);

      await s.as(owner);
      expect(await asOwner.queue().orThrow()).toEqual([]);
      expect(await asOwner.queue({ status: "visible" }).orThrow()).toHaveLength(
        1,
      );

      const removed = await asOwner
        .decide(queued!.id, "ban", { reason: "Spam ring" })
        .orThrow();

      expect(removed.status).toBe("removed");
      expect(
        await s.rows<{ deleted: boolean }>(
          "select deleted_at is not null as deleted from better_supabase.comments where id = $1",
          [spam],
        ),
      ).toEqual([{ deleted: true }]);
      expect(
        await s.hint("better_supabase.moderate($1, 'restore')", [queued!.id]),
      ).toBe("MODERATION_INVALID");

      const [ban] = await asOwner.bans().orThrow();

      expect(ban).toMatchObject({ userId: writer.id, reason: "Spam ring" });
      await s.as(writer);
      expect(
        await s.hint(
          "better_supabase.create_comment($1, 'project', $2, 'Again')",
          [tenant, projectId],
        ),
      ).toBe("MODERATION_BANNED");

      await s.as(owner);
      expect(await asOwner.unban(ban!.id).orThrow()).toBe(true);
      expect(await asOwner.unban(ban!.id).orThrow()).toBe(false);
      expect(await asOwner.bans().orThrow()).toEqual([]);
      expect(await asOwner.bans({ active: false }).orThrow()).toHaveLength(1);

      const later = await asOwner
        .ban(writer.id, {
          reason: "Cooling off",
          expiresAt: Temporal.Now.instant().add({ hours: 1 }),
        })
        .orThrow();

      expect(later.expiresAt).toBeInstanceOf(Temporal.Instant);
      expect(
        await s.hint("better_supabase.ban_user($1, $2)", [tenant, owner.id]),
      ).toBe("MODERATION_INVALID");

      await s.as(first);
      expect(
        await s.hint("better_supabase.moderate($1, 'hide')", [queued!.id]),
      ).toBe("MODERATION_FORBIDDEN");
      expect(
        await s.hint("better_supabase.ban_user($1, $2)", [tenant, second.id]),
      ).toBe("MODERATION_FORBIDDEN");

      await s.service();
      expect(
        await s.rows<{ type: string }>(
          "select type from better_supabase.outbox_events where type like 'moderation%' order by created_at, type",
        ),
      ).toEqual(
        expect.arrayContaining([
          { type: "moderation_report.created" },
          { type: "moderation_item.decided" },
          { type: "moderation_ban.created" },
          { type: "moderation_ban.lifted" },
        ]),
      );
    } finally {
      await s.close();
    }
  });

  it("runs review moderation through the queue", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(PROJECTS);
      await s.install(["organizations", "outbox", "moderation", "reviews"], {
        modules: {
          reviews: {
            options: {
              subjects: { ticket: { table: "public.bs_mod_tickets" } },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });

      await s.service();

      const [ticket] = await s.rows<{ id: string }>(
        "insert into public.bs_mod_tickets (organization_id) values ($1) returning id",
        [tenant],
      );

      await s.as(member);

      const review = await s.value<Review>(
        "better_supabase.submit_review($1, 'ticket', $2, 2, 'Slow')",
        [tenant, ticket!.id],
      );

      expect(review.status).toBe("pending");

      await s.as(owner);

      const moderation = createModeration({
        transport: sqlTransport(s.sql),
        tenant,
      });

      const [queued] = await moderation
        .queue({ subjectType: "review" })
        .orThrow();

      expect(queued).toMatchObject({
        subject: { type: "review", id: review.id },
        status: "pending",
        authorId: member.id,
      });

      await moderation
        .decide(queued!.id, "hide", { reason: "Off topic" })
        .orThrow();

      await s.as(member);
      expect(
        await s.value<Review>("better_supabase.my_review($1, 'ticket', $2)", [
          tenant,
          ticket!.id,
        ]),
      ).toMatchObject({ status: "rejected", rejectionReason: "Off topic" });

      await s.as(owner);
      expect(
        await s.value<Review>("better_supabase.publish_review($1)", [
          review.id,
        ]),
      ).toMatchObject({ status: "published", rejectionReason: null });
      expect(
        await moderation.statuses("review", [review.id]).orThrow(),
      ).toEqual({});

      await s.as(member);
      await s.value("better_supabase.submit_review($1, 'ticket', $2, 4)", [
        tenant,
        ticket!.id,
      ]);

      await s.as(owner);
      expect(
        await moderation.statuses("review", [review.id]).orThrow(),
      ).toEqual({ [review.id]: "pending" });

      await s.as(member);
      expect(
        await s.value<boolean>("better_supabase.delete_review($1)", [
          review.id,
        ]),
      ).toBe(true);

      await s.as(owner);
      expect(
        await moderation.item({ type: "review", id: review.id }).orThrow(),
      ).toBeNull();
    } finally {
      await s.close();
    }
  });

  it("upgrades version 1 reviews onto moderation items", async () => {
    const s = await BlockSession.open(pool);

    try {
      const tenant = crypto.randomUUID();
      const moderator = await s.user("moderator");

      await s.client.query(
        `create schema reviews_up;
create table reviews_up.reviews (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  author_id uuid,
  status text not null,
  rejection_reason text,
  moderated_by uuid,
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into reviews_up.reviews (tenant_id, subject_type, subject_id, status, rejection_reason, moderated_by, moderated_at)
values
  ($1, 'product', 'p1', 'published', null, $2, now()),
  ($1, 'product', 'p2', 'rejected', 'Spam', $2, now()),
  ($1, 'product', 'p3', 'pending', null, null, null);`
          .replaceAll("$1", `'${tenant}'`)
          .replaceAll("$2", `'${moderator.id}'`),
      );

      const [plan] = upgradePlan([{ module: "reviews", version: 1 }], {
        modules: {
          reviews: { schema: "reviews_up" },
          moderation: { schema: "reviews_up" },
        },
      });

      for (const step of plan!.steps) {
        await s.client.query(step.sql);
      }

      expect(
        await s.rows<{
          status: string;
          reason: string | null;
          decided: boolean;
        }>(
          `select status, reason, decided_by is not null as decided
           from reviews_up.moderation_items order by status`,
        ),
      ).toEqual([
        { status: "hidden", reason: "Spam", decided: true },
        { status: "pending", reason: null, decided: false },
        { status: "visible", reason: null, decided: true },
      ]);
      expect(
        await s.rows<{ action: string }>(
          "select action from reviews_up.moderation_actions order by action",
        ),
      ).toEqual([{ action: "approve" }, { action: "hide" }]);
      expect(
        await s.rows<{ column_name: string }>(
          `select column_name from information_schema.columns
           where table_schema = 'reviews_up' and table_name = 'reviews' and column_name like 'moderated%'`,
        ),
      ).toEqual([]);
    } finally {
      await s.close();
    }
  });
});
