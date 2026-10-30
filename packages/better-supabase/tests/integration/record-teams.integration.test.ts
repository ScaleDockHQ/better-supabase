import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("record teams", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("grants the team's actions only to current members", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.rows(
        `create table public.bsb_clients (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           name text not null
         )`,
      );
      await s.rows("grant select on public.bsb_clients to authenticated");
      await s.install(["permissions", "organizations", "teams", "subjects"], {
        subjects: {
          client: {
            table: "public.bsb_clients",
            idType: "uuid",
            title: "name",
            permissions: { read: "clients.read" },
            team: { actions: ["read", "write"] },
          },
        },
      });
      const owner = await s.user("owner");
      const nurse = await s.user("nurse");
      const outsider = await s.user("outsider");
      const former = await s.user("former");
      const ward = await s.user("ward");

      const organization = await s.organization(owner, {
        member: nurse,
        member2: outsider,
        member3: former,
        member4: ward,
      });

      await s.service();

      const [row] = await s.rows<{ id: string }>(
        "insert into public.bsb_clients (organization_id, name) values ($1, 'Ada') returning id",
        [organization],
      );

      const client = row!.id;

      const can = async (user: TestUser, action = "read") => {
        await s.asRole(user);

        const allowed = await s.value<boolean>(
          "better_supabase.can_subject('client', $1, $2)",
          [client, action],
        );

        await s.service();

        return allowed;
      };

      expect(await can(nurse)).toBe(false);
      expect(await can(nurse, "write")).toBe(false);

      await s.asRole(nurse);
      expect(
        await s.hint("better_supabase.add_subject_member('client', $1, $2)", [
          client,
          nurse.id,
        ]),
      ).toBe("SUBJECT_MEMBER_FORBIDDEN");

      await s.asRole(owner);

      const added = await s.value<{
        id: string;
        role: string;
        active: boolean;
      }>(
        "better_supabase.add_subject_member('client', $1, $2, role => 'lead')",
        [client, nurse.id],
      );

      expect(added).toMatchObject({ role: "lead", active: true });
      expect(
        await s.hint(
          "better_supabase.add_subject_member('client', $1, $2, role => 'boss')",
          [client, outsider.id],
        ),
      ).toBe("SUBJECT_MEMBER_INVALID");
      expect(
        await s.hint("better_supabase.add_subject_member('client', $1)", [
          client,
        ]),
      ).toBe("SUBJECT_MEMBER_INVALID");
      await s.value(
        "better_supabase.add_subject_member('client', $1, $2, ends_on => current_date - 1)",
        [client, former.id],
      );
      await s.value(
        "better_supabase.add_subject_member('client', $1, $2, starts_on => current_date + 1)",
        [client, outsider.id],
      );
      await s.service();

      expect(await can(nurse)).toBe(true);
      expect(await can(nurse, "write")).toBe(true);
      expect(await can(former)).toBe(false);
      expect(await can(outsider)).toBe(false);
      expect(
        await s.value<boolean>(
          "better_supabase.can_subject_for($1, 'client', $2, 'read')",
          [nurse.id, client],
        ),
      ).toBe(true);
      expect(
        await s.value<boolean>(
          "better_supabase.can_subject_for($1, 'client', $2, 'read')",
          [former.id, client],
        ),
      ).toBe(false);

      const [team] = await s.rows<{ id: string }>(
        `insert into better_supabase.teams (tenant_id, name, slug)
         values ($1, 'Night shift', 'night-shift') returning id`,
        [organization],
      );

      await s.rows(
        "insert into better_supabase.team_members (team_id, user_id, tenant_id) values ($1, $2, $3)",
        [team!.id, ward.id, organization],
      );
      expect(await can(ward)).toBe(false);
      await s.value(
        "better_supabase.add_subject_member('client', $1, team_id => $2)",
        [client, team!.id],
      );
      expect(await can(ward)).toBe(true);

      await s.asRole(nurse);

      const mine = await s.value<{
        items: { subjectId: string; roles: string[]; title: string }[];
        nextCursor: string | null;
      }>("better_supabase.my_subjects($1)", [organization]);

      expect(mine).toEqual({
        items: [
          expect.objectContaining({
            subjectId: client,
            roles: ["lead"],
            title: "Ada",
          }),
        ],
        nextCursor: null,
      });

      const teamRows = await s.value<unknown[]>(
        "better_supabase.list_subject_members('client', $1)",
        [client],
      );

      expect(teamRows).toHaveLength(4);

      await s.asRole(owner);

      const ended = await s.value<{ active: boolean }>(
        "better_supabase.end_subject_member($1, current_date - 1)",
        [added.id],
      );

      expect(ended.active).toBe(false);
      await s.service();
      expect(await can(nurse)).toBe(false);
    } finally {
      await s.close();
    }
  });
});
