import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

// Comments and attachments on projects name the provider's project scope
// (better-supabase.config.ts): centrakit.authz_project_ids_with answers for
// the members of centrakit.project_members, without an organization role.
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
