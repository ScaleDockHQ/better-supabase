import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("can_subject_for", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("answers for another user through the subject's read key", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.rows(
        `create table public.bs_memos (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           title text not null
         )`,
      );
      await s.install(["access", "organizations", "subjects"], {
        subjects: {
          memo: {
            table: "public.bs_memos",
            title: "title",
            permissions: { read: "memos.read" },
          },
          note: { table: "public.bs_memos", tenant: false },
        },
      });
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { admin });

      await s.service();

      const [row] = await s.rows<{ id: string }>(
        "insert into public.bs_memos (organization_id, title) values ($1, 'Plan') returning id",
        [organization],
      );

      const memo = row!.id;

      const canRead = (user: string, type = "memo") =>
        s.value<boolean>(
          "better_supabase.can_subject_for($1, $2, $3, 'read')",
          [user, type, memo],
        );

      expect(await canRead(owner.id)).toBe(true);
      expect(await canRead(admin.id)).toBe(false);
      expect(await canRead(outsider.id)).toBe(false);
      expect(await canRead(owner.id, "note")).toBe(false);
      expect(await canRead(owner.id, "unknown")).toBe(false);

      await s.asRole(owner);
      expect(
        await s.hint(
          "select better_supabase.can_subject_for($1, 'memo', $2, 'read')",
          [owner.id, memo],
        ),
      ).toMatch(/permission denied/);
    } finally {
      await s.close();
    }
  });
});
