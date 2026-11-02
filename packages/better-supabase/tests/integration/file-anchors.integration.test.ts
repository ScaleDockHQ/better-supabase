import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import {
  createComments,
  fileAnchor,
  sqlTransport,
} from "../../src/blocks/comments/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects(
    { doc: { table: "anchors_it.docs", idType: "uuid" } },
    ["comments", "attachments"],
    {},
  ),
};

const TABLES = `create schema anchors_it;
create table anchors_it.docs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
alter table anchors_it.docs enable row level security;
create policy docs_read on anchors_it.docs for select to authenticated using (true);
grant usage on schema anchors_it to authenticated;
grant select on anchors_it.docs to authenticated;`;

describe.skipIf(!live)("file anchors", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("comments on a page of a record's file and lists them by the file", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      await s.install(
        ["organizations", "outbox", "attachments", "messaging", "comments"],
        layout,
      );
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      await s.client.query("reset role");

      const [doc, other] = await s.rows<{ id: string }>(
        "insert into anchors_it.docs (organization_id) values ($1), ($1) returning id",
        [tenant],
      );

      const [file, elsewhere] = await s.rows<{ id: string }>(
        `insert into better_supabase.attachments (organization_id, subject_type, subject_id, name, mime_type, size, status, uploaded_by)
         values ($1, 'doc', $2, 'plan.pdf', 'application/pdf', 10, 'clean', $4),
                ($1, 'doc', $3, 'other.pdf', 'application/pdf', 10, 'clean', $4)
         returning id`,
        [tenant, doc!.id, other!.id, owner.id],
      );

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant,
      });

      const subject = { type: "doc", id: doc!.id };

      await s.asRole(owner);

      const anchor = fileAnchor(file!.id, {
        page: 2,
        region: { x: 0.25, y: 0.5, width: 0.5, height: 0.25 },
      });

      const comment = await comments
        .create({ subject, comment: { body: "Is this figure right?", anchor } })
        .orThrow();

      expect(comment.anchor).toEqual(anchor);

      const wrong = await comments.create({
        subject,
        comment: {
          body: "Wrong file",
          anchor: fileAnchor(elsewhere!.id, { page: 1 }),
        },
      });

      expect(wrong.ok ? undefined : wrong.error.hint).toBe(
        "MESSAGING_ANCHOR_INVALID",
      );

      const listed = await comments
        .anchoredTo({ attachmentId: file!.id })
        .orThrow();

      expect(listed.map((row) => [row.id, row.subject])).toEqual([
        [comment.id, subject],
      ]);
    } finally {
      await s.close();
    }
  });
});
