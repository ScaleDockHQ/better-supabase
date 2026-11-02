import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createBulk } from "../../src/blocks/bulk/index.ts";
import { createCollections } from "../../src/blocks/collections/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createSavedViews } from "../../src/blocks/saved-views/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const { company, ...parties } = withBlockSubjects({}, ["contacts"], {});

const layout: BlockSqlLayout = {
  subjects: {
    ...parties,
    ...(company === undefined
      ? {}
      : { company: { ...company, cascade: true } }),
    memo: {
      table: "public.collection_test_memos",
      idType: "uuid",
      title: "title",
      url: "/memos/{id}",
      cascade: true,
    },
  },
};

const MODULES = [
  "organizations",
  "outbox",
  "teams",
  "subjects",
  "contacts",
  "saved-views",
  "bulk",
  "collections",
];

// A subject whose rows only their author reads, so a shared list holds a
// record some members can't open.
const MEMOS = `create table if not exists public.collection_test_memos (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  author uuid not null,
  title text not null
);
alter table public.collection_test_memos enable row level security;
grant select on public.collection_test_memos to authenticated;
create policy memos_author on public.collection_test_memos for select to authenticated
  using (author = (select auth.uid()));`;

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("collections", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("stars records, ranks them and hides what the caller can't read", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.client.query(MEMOS);
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const other = await s.organization(stranger);
      const transport = sqlTransport(s.sql);
      const companies = createContacts({ transport });
      const collections = createCollections({ transport });

      await s.as(rep);

      const acme = await companies
        .saveCompany({ organizationId: org, input: { name: "Acme" } })
        .orThrow();

      const globex = await companies
        .saveCompany({ organizationId: org, input: { name: "Globex" } })
        .orThrow();

      const first = await collections
        .star({
          organizationId: org,
          subject: { type: "company", id: acme.id },
        })
        .orThrow();

      expect(first.rank).toBe("V");

      const second = await collections
        .star({
          organizationId: org,
          subject: { type: "company", id: globex.id },
        })
        .orThrow();

      expect(
        (
          await collections
            .star({
              organizationId: org,
              subject: { type: "company", id: acme.id },
            })
            .orThrow()
        ).rank,
      ).toBe("V");

      const moved = await collections
        .reorderStar({
          subject: { type: "company", id: globex.id },
          neighbors: { next: first.rank },
        })
        .orThrow();

      expect(moved < first.rank).toBe(true);

      const stars = await collections
        .starred({ organizationId: org })
        .orThrow();

      expect(stars.map((star) => star.title)).toEqual(["Globex", "Acme"]);
      expect(second.starredAt).toBeInstanceOf(Temporal.Instant);
      expect(
        await collections
          .starred({ organizationId: org, type: "memo" })
          .orThrow(),
      ).toHaveLength(0);

      await s.as(owner);
      expect(
        await collections.starred({ organizationId: org }).orThrow(),
      ).toHaveLength(0);

      await s.as(stranger);
      expect(
        hint(
          await collections.star({
            organizationId: other,
            subject: { type: "company", id: acme.id },
          }),
        ),
      ).toBe("FAVORITE_SUBJECT_FORBIDDEN");
      expect(
        hint(
          await collections.star({
            organizationId: org,
            subject: { type: "company", id: acme.id },
          }),
        ),
      ).toBe("FAVORITE_FORBIDDEN");

      await s.as(rep);
      expect(
        await collections.unstar({ type: "company", id: acme.id }).orThrow(),
      ).toBe(true);
      expect(
        await collections.unstar({ type: "company", id: acme.id }).orThrow(),
      ).toBe(false);
      expect(
        hint(
          await collections.reorderStar({
            subject: { type: "company", id: acme.id },
            neighbors: { previous: "not a key" },
          }),
        ),
      ).toBe("RANK_KEY_INVALID");

      await s.service();
      await s.client.query(
        "delete from better_supabase.companies where id = $1",
        [globex.id],
      );
      await s.as(rep);
      expect(
        await collections.starred({ organizationId: org }).orThrow(),
      ).toHaveLength(0);
    } finally {
      await s.close();
    }
  });

  it("keeps lists per user, team and organization and pages their entries", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const peer = await s.user("peer");
      await s.client.query(MEMOS);
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep, member2: peer });
      const transport = sqlTransport(s.sql);
      const companies = createContacts({ transport });
      const collections = createCollections({ transport });

      await s.as(owner);

      const team = await s.value<string>(
        "(better_supabase.create_team($1, 'Sales', null) ->> 'id')",
        [org],
      );

      for (const member of [owner, rep]) {
        await s.client.query("select better_supabase.add_team_member($1, $2)", [
          team,
          member.id,
        ]);
      }

      await s.as(rep);
      const ids: string[] = [];

      for (const name of ["Acme", "Globex", "Initech"]) {
        ids.push(
          (
            await companies
              .saveCompany({ organizationId: org, input: { name } })
              .orThrow()
          ).id,
        );
      }

      const mine = await collections
        .create({
          organizationId: org,
          input: { name: "My accounts", subjectType: "company" },
        })
        .orThrow();

      expect(mine.scope).toBe("user");
      expect(mine.ownerId).toBe(rep.id);
      expect(
        hint(
          await collections.create({
            organizationId: org,
            input: {
              name: "Everyone",
              subjectType: "company",
              scope: "tenant",
            },
          }),
        ),
      ).toBe("COLLECTION_FORBIDDEN");
      expect(
        hint(
          await collections.create({
            organizationId: org,
            input: { name: "x", subjectType: "deal" },
          }),
        ),
      ).toBe("COLLECTION_SUBJECT_TYPE_UNKNOWN");
      expect(
        hint(
          await collections.create({
            organizationId: org,
            input: { name: " ", subjectType: "company" },
          }),
        ),
      ).toBe("COLLECTION_NAME_REQUIRED");

      const added = await collections
        .add({ id: mine.id, subjectIds: [ids[2]!, ids[0]!, ids[2]!] })
        .orThrow();

      expect(added.added).toEqual([ids[2], ids[0]]);
      expect(
        (
          await collections
            .add({ id: mine.id, subjectIds: [ids[0]!, ids[1]!] })
            .orThrow()
        ).added,
      ).toEqual([ids[1]]);

      const firstPage = await collections
        .entries({ id: mine.id, limit: 2 })
        .orThrow();

      expect(firstPage.items.map((entry) => entry.title)).toEqual([
        "Initech",
        "Acme",
      ]);
      expect(firstPage.items[0]?.addedBy).toBe(rep.id);

      const rest = await collections
        .entries({
          id: mine.id,
          limit: 2,
          ...(firstPage.next && { cursor: firstPage.next }),
        })
        .orThrow();

      expect(rest.items.map((entry) => entry.title)).toEqual(["Globex"]);
      expect(rest.next).toBeUndefined();
      await collections
        .reorder({
          id: mine.id,
          subjectId: ids[1]!,
          neighbors: { next: firstPage.items[0]!.rank },
        })
        .orThrow();
      expect(await collections.subjectIds({ id: mine.id }).orThrow()).toEqual([
        ids[1],
        ids[2],
        ids[0],
      ]);
      expect(
        await collections
          .where({ id: mine.id, column: "company_id" })
          .orThrow(),
      ).toEqual({ company_id: { in: [ids[1], ids[2], ids[0]] } });

      const foreign = await s.value<string>("(select gen_random_uuid()::text)");
      expect(
        hint(await collections.add({ id: mine.id, subjectIds: [foreign] })),
      ).toBe("COLLECTION_SUBJECT_FORBIDDEN");
      expect(
        hint(
          await collections.add({
            id: mine.id,
            subjectIds: Array.from({ length: 1001 }, () => foreign),
          }),
        ),
      ).toBe("COLLECTION_TOO_MANY");

      await s.asRole(peer);
      expect(
        await collections.list({ organizationId: org }).orThrow(),
      ).toHaveLength(0);
      expect(hint(await collections.entries({ id: mine.id }))).toBe("ok");
      expect(
        (await collections.entries({ id: mine.id }).orThrow()).items,
      ).toEqual([]);
      expect(
        hint(await collections.add({ id: mine.id, subjectIds: [ids[0]!] })),
      ).toBe("COLLECTION_NOT_FOUND");

      await s.as(owner);

      const shared = await collections
        .create({
          organizationId: org,
          input: {
            name: "Key accounts",
            subjectType: "company",
            scope: "team",
            teamId: team,
          },
        })
        .orThrow();

      const everyone = await collections
        .create({
          organizationId: org,
          input: { name: "Watchlist", subjectType: "company", scope: "tenant" },
        })
        .orThrow();

      await s.as(rep);
      await collections.add({ id: shared.id, subjectIds: [ids[0]!] }).orThrow();
      expect(
        (await collections.listsOf({ type: "company", id: ids[0]! }).orThrow())
          .map((list) => list.name)
          .toSorted(),
      ).toEqual(["Key accounts", "My accounts"]);
      expect(
        hint(
          await collections.rename({ id: shared.id, input: { name: "Mine" } }),
        ),
      ).toBe("COLLECTION_FORBIDDEN");
      await s.asRole(peer);
      expect(
        (await collections.list({ organizationId: org }).orThrow()).map(
          (list) => list.name,
        ),
      ).toEqual(["Watchlist"]);
      await collections
        .add({ id: everyone.id, subjectIds: [ids[1]!] })
        .orThrow();
      expect(
        await collections
          .remove({ id: everyone.id, subjectIds: [ids[1]!, ids[2]!] })
          .orThrow(),
      ).toBe(1);

      await s.as(rep);

      const renamed = await collections
        .rename({
          id: mine.id,
          input: { name: "Top accounts", description: "Q4" },
        })
        .orThrow();

      expect(renamed.description).toBe("Q4");
      expect(
        (
          await collections
            .rename({ id: mine.id, input: { description: null } })
            .orThrow()
        ).description,
      ).toBeUndefined();
      expect(await collections.archive({ id: mine.id }).orThrow()).toBe(true);
      expect(
        hint(await collections.add({ id: mine.id, subjectIds: [ids[0]!] })),
      ).toBe("COLLECTION_ARCHIVED");
      expect(
        (await collections.list({ organizationId: org }).orThrow()).map(
          (list) => list.name,
        ),
      ).not.toContain("Top accounts");

      const archived = await collections
        .list({
          organizationId: org,
          includeArchived: true,
          subjectType: "company",
        })
        .orThrow();

      expect(archived.find((list) => list.id === mine.id)?.archived).toBe(true);
      await collections.archive({ id: mine.id, archived: false }).orThrow();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where payload ->> 'collectionId' = $1 order by type",
        [mine.id],
      );

      expect(events.map((event) => event.type)).toEqual([
        "collection.archived",
        "collection.created",
        "collection.entry_added",
        "collection.entry_added",
        "collection.entry_added",
      ]);
    } finally {
      await s.close();
    }
  });

  it("hides entries whose record the caller can't read and cascades deletes", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      await s.client.query(MEMOS);
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const transport = sqlTransport(s.sql);
      const collections = createCollections({ transport });
      const views = createSavedViews({ transport });
      const bulk = createBulk({ transport });

      await s.service();

      const [own, secret] = await s.rows<{ id: string }>(
        `insert into public.collection_test_memos (organization_id, author, title)
         values ($1, $2, 'Rep notes'), ($1, $3, 'Owner notes') returning id`,
        [org, rep.id, owner.id],
      );

      await s.as(owner);

      const list = await collections
        .create({
          organizationId: org,
          input: { name: "Memos", subjectType: "memo", scope: "tenant" },
        })
        .orThrow();

      await collections
        .add({ id: list.id, subjectIds: [own!.id, secret!.id] })
        .orThrow();

      await s.asRole(rep);
      expect(
        await s.rows(
          "select subject_id from better_supabase.subject_collection_entries where collection_id = $1",
          [list.id],
        ),
      ).toEqual([{ subject_id: own!.id }]);
      const page = await collections.entries({ id: list.id }).orThrow();
      expect(page.items.map((entry) => entry.title)).toEqual(["Rep notes"]);
      expect(page.items[0]?.url).toBe(`/memos/${own!.id}`);

      const view = await views
        .upsert({
          organizationId: org,
          list: "memos",
          name: "In Memos",
          state: { collectionId: list.id },
        })
        .orThrow();

      expect(view.id).toBeTypeOf("string");
      expect(
        hint(
          await views.upsert({
            organizationId: org,
            list: "memos",
            name: "Broken",
            state: { collectionId: crypto.randomUUID() },
          }),
        ),
      ).toBe("SAVED_VIEW_COLLECTION_NOT_FOUND");

      await s.as(owner);

      const picks = await collections
        .create({
          organizationId: org,
          input: { name: "Picks", subjectType: "memo" },
        })
        .orThrow();

      const run = await bulk
        .run({
          organizationId: org,
          subjectType: "memo",
          rows: [secret!.id, crypto.randomUUID()],
          action: "collections.add",
          args: { collectionId: picks.id },
        })
        .orThrow();

      expect(run.failed).toBe(1);
      expect(await collections.subjectIds({ id: picks.id }).orThrow()).toEqual([
        secret!.id,
      ]);

      await s.service();
      await s.client.query(
        "delete from public.collection_test_memos where id = $1",
        [secret!.id],
      );
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.subject_collection_entries where subject_id = $1)",
          [secret!.id],
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });

  it("saves records for later and reminds the member when due", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.client.query(MEMOS);
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      await s.organization(stranger);
      const transport = sqlTransport(s.sql);
      const companies = createContacts({ transport });
      const sent: { key: unknown; recipients: unknown }[] = [];

      const collections = createCollections({
        transport,
        notification: "saved_item.reminder",
        notifier: {
          send: ({ input }) => {
            sent.push({ key: input.key, recipients: input.recipients });

            return { ok: true };
          },
        },
      });

      await s.as(rep);

      const acme = await companies
        .saveCompany({ organizationId: org, input: { name: "Acme" } })
        .orThrow();

      const company = { type: "company", id: acme.id };

      expect(
        hint(
          await collections.saveForLater({
            organizationId: org,
            subject: company,
            input: {
              remindAt: Temporal.Now.instant().subtract({ minutes: 1 }),
            },
          }),
        ),
      ).toBe("SAVED_ITEM_INVALID");
      expect(
        hint(
          await collections.saveForLater({
            organizationId: org,
            subject: company,
            input: { note: "x".repeat(1001) },
          }),
        ),
      ).toBe("SAVED_ITEM_INVALID");

      const item = await collections
        .saveForLater({
          organizationId: org,
          subject: company,
          input: {
            note: "Call back",
            remindAt: Temporal.Now.instant().add({ hours: 1 }),
          },
        })
        .orThrow();

      expect(item.note).toBe("Call back");
      const page = await collections.saved({ organizationId: org }).orThrow();
      expect(page.items.map((saved) => saved.title)).toEqual(["Acme"]);

      await s.as(owner);
      expect(
        (await collections.saved({ organizationId: org }).orThrow()).items,
      ).toHaveLength(0);
      expect(await collections.removeSaved(item.id).orThrow()).toBe(false);

      await s.as(stranger);
      expect(
        hint(
          await collections.saveForLater({
            organizationId: org,
            subject: company,
          }),
        ),
      ).toBe("SAVED_ITEM_FORBIDDEN");

      await s.as(rep);
      expect(hint(await collections.remindDue())).toBe("SAVED_ITEM_FORBIDDEN");

      await s.service();
      await s.client.query(
        "update better_supabase.saved_items set remind_at = now() - interval '1 minute' where id = $1",
        [item.id],
      );

      const due = await collections.remindDue().orThrow();
      expect(due.map((saved) => saved.id)).toEqual([item.id]);
      expect(sent).toEqual([
        { key: expect.stringContaining(item.id), recipients: [rep.id] },
      ]);
      expect(await collections.remindDue().orThrow()).toHaveLength(0);

      await s.as(rep);
      expect(await collections.completeSaved({ id: item.id }).orThrow()).toBe(
        true,
      );
      expect(
        (await collections.saved({ organizationId: org }).orThrow()).items,
      ).toHaveLength(0);
      expect(
        (
          await collections
            .saved({ organizationId: org, options: { completed: true } })
            .orThrow()
        ).items,
      ).toHaveLength(1);

      await collections
        .saveForLater({ organizationId: org, subject: company })
        .orThrow();
      expect(
        (await collections.saved({ organizationId: org }).orThrow()).items,
      ).toHaveLength(1);
      expect(await collections.removeSaved(item.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });
});
