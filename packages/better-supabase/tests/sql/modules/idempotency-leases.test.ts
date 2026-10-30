import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

describe("idempotency next to the leases block", () => {
  it("creates its idempotency_leases table apart from the leases", () => {
    const files = renderBlocks(["idempotency", "leases"]);

    const schema = files
      .filter((file) => file.kind === "schema")
      .map((file) => file.contents)
      .join("\n");

    expect(schema).toContain(
      `create table if not exists "better_supabase"."idempotency_leases"`,
    );
    expect(schema).toContain(
      `create table if not exists "better_supabase"."leases"`,
    );
  });

  it("names both config keys when two blocks would create one table", () => {
    expect(() =>
      renderBlocks(["idempotency", "leases"], {
        modules: {
          idempotency: { tables: { leases: "better_supabase.leases" } },
        },
      }),
    ).toThrow(
      "blocks.idempotency.tables.leases and blocks.leases.tables.leases both name better_supabase.leases",
    );
  });

  it("installs when both tables have other names", () => {
    expect(
      renderBlocks(["idempotency", "leases"], {
        modules: {
          idempotency: { tables: { leases: "idempotency_locks" } },
          leases: { tables: { leases: "lease_agreements" } },
        },
      }).length,
    ).toBeGreaterThan(0);
  });

  it(
    "migrates both blocks into one database",
    async () => {
      const files = renderBlocks(["idempotency", "leases"]);

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          ROLES,
          ...files
            .filter((file) => file.kind !== "data")
            .map((file) => file.contents),
        ],
        seed: [
          ...files
            .filter((file) => file.kind === "data")
            .map((file) => file.contents),
          `do $$
begin
  if better_supabase.acquire_lease('job', 60, 'conv') is null then
    raise exception 'no lease';
  end if;
  if to_regclass('better_supabase.leases') is null then
    raise exception 'no leases';
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
    BOOT.timeout,
  );
});
