import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

interface LoggedRead {
  readonly actorId: string;
  readonly purpose: string | null;
  readonly emergency: boolean;
  readonly block: string;
  readonly function: string;
}

describe.skipIf(!live)("subject read log", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("logs every read without a window and shows the log to the record's lead", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.rows(
        `create table public.bsb_read_clients (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           name text not null
         )`,
      );
      await s.rows("grant select on public.bsb_read_clients to authenticated");
      await s.install(
        ["permissions", "organizations", "teams", "audit", "subjects"],
        {
          subjects: {
            client: {
              table: "public.bsb_read_clients",
              idType: "uuid",
              title: "name",
              team: { actions: ["read"] },
              auditReads: true,
            },
          },
          modules: { subjects: { options: { reads: { collapseSeconds: 0 } } } },
        },
      );
      const owner = await s.user("owner");
      const lead = await s.user("lead");
      const nurse = await s.user("nurse");

      const organization = await s.organization(owner, {
        member: lead,
        member2: nurse,
      });

      await s.service();

      const [row] = await s.rows<{ id: string }>(
        "insert into public.bsb_read_clients (organization_id, name) values ($1, 'Ada') returning id",
        [organization],
      );

      const client = row!.id;

      await s.asRole(owner);
      await s.value(
        "better_supabase.add_subject_member('client', $1, $2, role => 'lead')",
        [client, lead.id],
      );
      await s.value("better_supabase.add_subject_member('client', $1, $2)", [
        client,
        nurse.id,
      ]);

      await s.asRole(nurse);
      await s.value(
        "better_supabase.record_summary('client', $1, '{}')::text",
        [client],
      );
      await s.value(
        "better_supabase.record_summary('client', $1, '{}')::text",
        [client],
      );
      await s.value(
        "better_supabase.record_subject_read('client', $1, 'Intake')::text",
        [client],
      );

      expect(
        await s.hint("better_supabase.subject_access_log('client', $1)", [
          client,
        ]),
      ).toBe("SUBJECT_READ_FORBIDDEN");

      await s.asRole(lead);

      const reads = await s.value<LoggedRead[]>(
        "better_supabase.subject_access_log('client', $1)",
        [client],
      );

      expect(reads).toHaveLength(3);
      expect(reads.every((read) => read.actorId === nurse.id)).toBe(true);
      expect(reads.filter((read) => read.purpose === "Intake")).toHaveLength(1);
      expect(
        reads.filter((read) => read.function === "record_summary"),
      ).toHaveLength(2);

      const since = await s.value<LoggedRead[]>(
        "better_supabase.subject_access_log('client', $1, now() + interval '1 minute')",
        [client],
      );

      expect(since).toEqual([]);
      expect(
        await s.value<number>(
          "jsonb_array_length(better_supabase.subject_access_log('client', $1, max_rows => 1))",
          [client],
        ),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });
});
