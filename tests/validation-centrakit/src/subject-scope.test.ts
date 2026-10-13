import { renderModules } from "better-supabase/sql";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

// CentraKit's own config uses the catalog access model, so the provider
// subject scope runs in this layout: the provider reads CentraKit's roles for
// organizations and a project membership table for projects.
const LAYOUT = {
  modules: {
    access: { model: "provider" as const },
    comments: {
      options: {
        subjects: {
          project: {
            table: "centrakit.projects",
            idType: "uuid",
            scope: "project",
          },
        },
      },
    },
    attachments: {
      options: {
        subjects: {
          project: {
            table: "centrakit.projects",
            idType: "uuid",
            scope: "project",
          },
        },
      },
    },
  },
  accessProvider: {
    name: "centrakit",
    scope: "organization",
    scopes: ["organization", "project"],
    idType: "uuid" as const,
    functions: {
      idsWith: "centrakit.{scope}_ids_with({permission})",
      isPlatform: "centrakit.is_platform({permission})",
    },
  },
};

const PROVIDER = `
create table centrakit.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references centrakit.organizations (id),
  name text not null
);
create table centrakit.project_members (
  project_id uuid not null references centrakit.projects (id),
  user_id uuid not null,
  primary key (project_id, user_id)
);
grant select on centrakit.projects, centrakit.project_members to authenticated;
create function centrakit.organization_ids_with(permission text) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select ou.organization_id from centrakit.organization_users ou
  join centrakit.role_permissions rp on rp.role_id = ou.role_id
  join centrakit.permissions p on p.id = rp.permission_id
  where ou.user_id = auth.uid() and p.key = permission
$$;
create function centrakit.project_ids_with(permission text) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select pm.project_id from centrakit.project_members pm
  where pm.user_id = auth.uid() and permission in ('comments.read', 'attachments.read')
$$;
create function centrakit.is_platform(permission text) returns boolean
language sql stable as $$ select false $$;
grant execute on function centrakit.organization_ids_with(text), centrakit.project_ids_with(text),
  centrakit.is_platform(text) to authenticated;`;

describe.skipIf(!live)("provider subject scopes on CentraKit's tables", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("reads comments and attachments through a grant on the project", async () => {
    await withCentraKit(pool, async (s) => {
      await s.as("owner");
      const organization = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Acme", slug: `acme-${USERS.owner.slice(0, 8)}` }],
      );
      await s.client.query(PROVIDER);
      for (const file of renderModules(
        ["access", "comments", "attachments"],
        LAYOUT,
      ))
        await s.client.query(file.contents);

      const [granted, hidden] = await s.rows<{ id: string }>(
        `insert into centrakit.projects (organization_id, name)
         values ($1, 'Granted'), ($1, 'Hidden') returning id::text`,
        [organization],
      );
      await s.client.query(
        "insert into centrakit.project_members values ($1, $2)",
        [granted?.id, USERS.member],
      );
      const subjects = [granted?.id, hidden?.id];
      await s.client.query(
        `insert into better_supabase.comments (organization_id, subject_type, subject_id, body, author_id)
         values ($1, 'project', $2, 'seen', $4), ($1, 'project', $3, 'unseen', $4)`,
        [organization, ...subjects, USERS.owner],
      );
      await s.client.query(
        `insert into better_supabase.attachments (organization_id, subject_type, subject_id, name, mime_type, size)
         values ($1, 'project', $2, 'seen.pdf', 'application/pdf', 1),
                ($1, 'project', $3, 'unseen.pdf', 'application/pdf', 1)`,
        [organization, ...subjects],
      );

      await s.as("member");
      await s.client.query("set local role authenticated");
      expect(
        await s.rows(
          "select body from better_supabase.comments where subject_id = any($1)",
          [subjects],
        ),
      ).toEqual([{ body: "seen" }]);
      expect(
        await s.rows(
          "select name from better_supabase.attachments where subject_id = any($1)",
          [subjects],
        ),
      ).toEqual([{ name: "seen.pdf" }]);
      await s.client.query("reset role");
    });
  });
});
