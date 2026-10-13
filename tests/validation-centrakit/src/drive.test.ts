import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, ROLES, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

interface Node {
  readonly id: string;
  readonly name: string;
  readonly parentId: string | null;
  readonly role?: string;
}

describe.skipIf(!live)("drive on CentraKit's file tree", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("shares a folder with a team and inherits the grant", async () => {
    await withCentraKit(pool, async (s) => {
      await s.as("service");
      const [{ id: org }] = (await s.rows<{ id: string }>(
        "insert into centrakit.organizations (name, slug) values ('Acme', $1) returning id",
        [`acme-${crypto.randomUUID().slice(0, 8)}`],
      )) as [{ id: string }];
      await s.rows(
        `insert into centrakit.organization_users (organization_id, user_id, role_id)
         values ($1, $2, $3), ($1, $4, $5)`,
        [org, USERS.owner, ROLES.owner, USERS.member, ROLES.member],
      );
      const [{ id: team }] = (await s.rows<{ id: string }>(
        "insert into centrakit.teams (tenant_id, name, slug) values ($1, 'Design', 'design') returning id",
        [org],
      )) as [{ id: string }];
      await s.rows(
        "insert into centrakit.team_members (team_id, user_id, tenant_id) values ($1, $2, $3)",
        [team, USERS.member, org],
      );

      await s.as("owner");
      const projects = await s.value<Node>(
        "better_supabase.drive_create_folder($1, null, 'Projects')",
        [org],
      );
      const launch = await s.value<Node>(
        "better_supabase.drive_create_folder($1, $2, 'Launch')",
        [org, projects.id],
      );
      expect(launch.parentId).toBe(projects.id);
      expect(
        await s.rows<{ name: string; kind: string }>(
          "select name, kind from centrakit.file_node where organization_id = $1 order by name",
          [org],
        ),
      ).toEqual([
        { name: "Launch", kind: "folder" },
        { name: "Projects", kind: "folder" },
      ]);

      await s.as("member");
      expect(await s.hint("better_supabase.drive_get($1)", [launch.id])).toBe(
        "DRIVE_NOT_FOUND",
      );

      await s.as("owner");
      await s.value("better_supabase.drive_share($1, 'team', $2, 'viewer')", [
        projects.id,
        team,
      ]);
      expect(
        await s.rows<{ team_id: string; user_id: string | null; role: string }>(
          "select team_id::text, user_id::text, role from centrakit.file_node_grant where file_node_id = $1 order by role",
          [projects.id],
        ),
      ).toEqual([
        { team_id: null, user_id: USERS.owner, role: "editor" },
        { team_id: team, user_id: null, role: "viewer" },
      ]);

      await s.as("member");
      expect(
        await s.value<Node>("better_supabase.drive_get($1)", [launch.id]),
      ).toMatchObject({ role: "viewer" });
      expect(
        await s.hint("better_supabase.drive_create_folder($1, $2, 'Notes')", [
          org,
          launch.id,
        ]),
      ).toBe("DRIVE_FORBIDDEN");

      await s.as("owner");
      await s.value("better_supabase.drive_share($1, 'user', $2, 'editor')", [
        launch.id,
        USERS.member,
      ]);
      await s.as("member");
      const notes = await s.value<Node>(
        "better_supabase.drive_create_folder($1, $2, 'Notes')",
        [org, launch.id],
      );
      expect(notes.role).toBe("editor");
    });
  });
});
