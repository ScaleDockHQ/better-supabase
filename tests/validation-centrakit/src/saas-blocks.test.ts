import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Session } from "./stack.ts";

import { dbUrl, reachable, withCentraKit } from "./stack.ts";

const live = await reachable();

const TABLES = [
  "organization_number_sequences",
  "teams",
  "team_members",
  "organization_tags",
  "task_tags",
  "status_history",
  "field_definitions",
  "field_values",
  "share_links",
  "subject_views",
  "subject_user_state",
  "recurrence_rules",
  "reminders",
  "reminder_deliveries",
  "import_runs",
] as const;

describe.skipIf(!live)("SaaS blocks on CentraKit tables", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it.each(TABLES)("adopts centrakit.%s", async (table) => {
    await withCentraKit(pool, async (s) => {
      expect(
        await s.value<string | null>("to_regclass($1)", [`centrakit.${table}`]),
      ).toBe(`centrakit.${table}`);
    });
  });

  async function organization(s: Session): Promise<string> {
    await s.as("service");

    const { rows } = await s.client.query<{ id: string }>(
      "insert into centrakit.organizations (name, slug) values ('Acme', $1) returning id",
      [`acme-${crypto.randomUUID().slice(0, 8)}`],
    );

    return rows[0]!.id;
  }

  it("allocates the next number", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await organization(s);
      expect(
        await s.value(
          "better_supabase.next_number($1::uuid, 'invoice', now())::text",
          [org],
        ),
      ).toBe("1");
      expect(
        await s.value(
          "better_supabase.next_number($1::uuid, 'invoice', now())::text",
          [org],
        ),
      ).toBe("2");
    });
  });

  it("creates a team", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await organization(s);

      const created = await s.value<{ id: string }>(
        "better_supabase.create_team($1::uuid, 'Ops', '')",
        [org],
      );

      expect(created.id).toEqual(expect.any(String));
    });
  });

  it("creates a tag", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await organization(s);

      const created = await s.value<{ id: string }>(
        "better_supabase.create_tag($1::uuid, 'task', 'Urgent', null, null)",
        [org],
      );

      expect(created.id).toEqual(expect.any(String));
    });
  });

  it("rejects an unknown status transition", async () => {
    await withCentraKit(pool, async (s) => {
      await s.as("service");
      expect(
        await s.hint("better_supabase.transition('quote', $1, 'sent', null)", [
          crypto.randomUUID(),
        ]),
      ).toBe("STATE_MACHINE_UNKNOWN");
    });
  });

  it("saves a field definition", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await organization(s);

      const saved = await s.value<{ id: string }>(
        "better_supabase.save_field_definition($1::uuid, 'customer', 'serial', 'Serial', 'text', false)",
        [org],
      );

      expect(saved.id).toEqual(expect.any(String));
    });
  });

  it("creates a share link and returns the token once", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await organization(s);

      const link = await s.value<{ id: string; token: string }>(
        "better_supabase.create_share_link($1::uuid, 'file', $2, 'view')",
        [org, crypto.randomUUID()],
      );

      expect(link.token).toEqual(expect.any(String));
      expect(link.id).toEqual(expect.any(String));
    });
  });

  it("saves a reminder", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await organization(s);

      const saved = await s.value<{ id: string }>(
        "better_supabase.save_reminder($1::uuid, 'task', $2, 15)",
        [org, crypto.randomUUID()],
      );

      expect(saved.id).toEqual(expect.any(String));
    });
  });

  it("starts an import run", async () => {
    await withCentraKit(pool, async (s) => {
      const org = await organization(s);

      const started = await s.value<{ id: string }>(
        "better_supabase.start_import($1::uuid, 'people', '{}'::jsonb)",
        [org],
      );

      expect(started.id).toEqual(expect.any(String));
    });
  });
});
