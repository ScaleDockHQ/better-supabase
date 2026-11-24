import { introspect, run, serializeSnapshot } from "better-supabase/cli";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, ROLES, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();
const fixture = fileURLToPath(new URL("..", import.meta.url));

const payloads = await readFile(
  new URL("../supabase/page-payloads.sql", import.meta.url),
  "utf-8",
);

// The two provider fields the split needs, which the frozen provider snapshot
// doesn't have yet: the customers table shared per tenant, and the app's
// permission helper with the argument that holds the key.
const configFile = `import base from ${JSON.stringify(
  pathToFileURL(join(fixture, "better-supabase.config.ts")).href,
)};

export default {
  ...base,
  auth: {
    ...base.auth,
    authorization: {
      ...base.auth.authorization,
      tables: {
        "centrakit.customers": { share: "tenant", permissions: ["crm.read"] },
      },
      permissionFilters: { "app_auth.allowed_org_ids": { keyArgument: 0 } },
    },
  },
};
`;

describe.skipIf(!live)("a page payload split for a shared entry", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  afterAll(() => pool.end());

  it(
    "config functions --shareable passes the tenant half and names what fails in the mixed one",
    { timeout: 120_000 },
    async () => {
      const dir = await mkdtemp(join(tmpdir(), "centrakit-payloads-"));

      try {
        await withCentraKit(pool, async (s) => {
          await s.as("service");
          await s.client.query(payloads);

          const org = (
            await s.rows<{ id: string }>(
              "insert into centrakit.organizations (name, slug) values ('Acme', $1) returning id",
              [`acme-${crypto.randomUUID().slice(0, 8)}`],
            )
          )[0]!.id;

          await s.client.query(
            "insert into centrakit.organization_users (organization_id, user_id, role_id) values ($1, $2, $3)",
            [org, USERS.member, ROLES.member],
          );

          const customer = (
            await s.rows<{ id: string }>(
              "insert into centrakit.customers (organization_id, company_name) values ($1, 'Bakery Jansen'), ($1, 'Garage De Vries') returning id::text",
              [org],
            )
          )[0]!.id;

          await s.client.query(
            "insert into centrakit.subject_user_state (subject_type, subject_id, user_id, starred_at) values ('customer', $1, $2, now())",
            [customer, USERS.member],
          );

          const snapshot = await introspect(
            s.client,
            ["centrakit", "better_supabase", "public", "app_auth"],
            { shareable: true },
          );

          await writeFile(
            join(dir, "snapshot.json"),
            serializeSnapshot(snapshot),
          );

          // The two halves answer what the mixed payload answered, under RLS.
          await s.as("member");
          await s.client.query("set local role authenticated");

          const mixed = await s.value<{ customers: unknown; starred: unknown }>(
            "public.customer_page_payload($1)",
            [org],
          );

          expect(
            await s.value("public.customer_list_payload($1)", [org]),
          ).toEqual(mixed.customers);
          expect(await s.value("public.customer_starred($1)", [org])).toEqual(
            mixed.starred,
          );

          await s.client.query("reset role");
        });

        await writeFile(join(dir, "better-supabase.config.mjs"), configFile);

        const result = await run([
          "config",
          "functions",
          "--shareable",
          "public.customer_*_payload",
          "--snapshot",
          join(dir, "snapshot.json"),
          "--cwd",
          dir,
        ]);

        expect(result).toMatchObject({ code: 0, stderr: "" });
        expect(result.stdout).toContain(
          "public.customer_list_payload: shareable once sharedFunctions lists it (reads centrakit.customers; filters by crm.read)",
        );
        expect(result.stdout).toContain(
          [
            "public.customer_page_payload: can't be shared (reads centrakit.customers)",
            "  - it calls auth.uid, which reads the caller",
            "  - it reads centrakit.subject_user_state, which the provider's tables don't share per tenant",
          ].join("\n"),
        );
        expect(result.stdout).toContain("1 of 2 can be shared.");
      } finally {
        await rm(dir, { recursive: true, force: true });
      }
    },
  );
});
