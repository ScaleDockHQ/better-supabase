import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { MutationNotice } from "../../src/core/events.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { createPostgres } from "../../src/postgres/pool.ts";
import { createServer } from "../../src/server/server.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

const RUN = String(Date.now());
const ORG = "00000000-0000-4000-8000-000000000001";

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/storage/v1/status`, {
      signal: AbortSignal.timeout(1000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

const documents = defineBucket({
  id: "bs-it-documents",
  path: "{userId}/{file}",
  policy: "owner",
});
// `{userId}` is not the first segment: the whole bucket is listed and filtered.
const shared = defineBucket({
  id: "bs-it-shared",
  path: "{organizationId}/{userId}/{file}",
});
const logos = defineBucket({
  id: "bs-it-logos",
  path: "{organizationId}/{file}",
});

describe.skipIf(!(await reachable()))("deleteAccount", () => {
  const service = createClient(url, secretKey, {
    auth: { persistSession: false },
  });
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  const table = `bs_del_${RUN}`;
  const betterSupabase = defineSupabase(schema);
  const server = createServer(betterSupabase, {
    env: {
      url,
      publishableKey,
      secretKey,
      jwksUrl: new URL("/auth/v1/.well-known/jwks.json", url),
    },
  });
  let userId: string;
  let otherId: string;

  const createUser = async (name: string) => {
    const { data, error } = await service.auth.admin.createUser({
      email: `${name}-${RUN}@example.test`,
      password: `pw-${crypto.randomUUID()}`,
      email_confirm: true,
    });
    if (error) throw error;
    return data.user.id;
  };
  const file = (text: string) => new Blob([text], { type: "text/plain" });

  beforeAll(async () => {
    await pool.query(documents.sql());
    await pool.query(shared.sql());
    [userId, otherId] = await Promise.all([
      createUser("delete-me"),
      createUser("keep-me"),
    ]);
    const docs = documents.connect(service);
    const organization = shared.connect(service);
    for (const owner of [userId, otherId]) {
      for (const name of ["a.txt", "b.txt"])
        await docs.upload({ userId: owner, file: name }, file(name)).orThrow();
      await organization
        .upload(
          { organizationId: ORG, userId: owner, file: "c.txt" },
          file("c"),
        )
        .orThrow();
    }
    await pool.query(
      `create table public.${table} (id bigint generated always as identity primary key,
        user_id uuid not null references auth.users (id))`,
    );
    await pool.query(`insert into public.${table} (user_id) values ($1)`, [
      userId,
    ]);
  });

  afterAll(async () => {
    await pool.query(`drop table if exists public.${table}`);
    for (const bucket of [documents, shared]) {
      const all = await bucket.connect(service).list();
      if (all.ok)
        await bucket.connect(service).remove(all.data.map((o) => o.path));
    }
    for (const id of [userId, otherId])
      if (id) await service.auth.admin.deleteUser(id);
    await pool.end();
  });

  it("returns a conflict naming BS406 while a foreign key blocks the delete", async () => {
    const result = await server.deleteAccount(userId);
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "conflict", table: "auth.users" },
    });
    expect(!result.ok && result.error.hint).toContain("BS406");
    const { data } = await service.auth.admin.getUserById(userId);
    expect(data.user?.id).toBe(userId);
  });

  it("keeps the objects and returns the database's hint when a check refuses the delete", async () => {
    const guard = `bs_del_guard_${RUN}`;
    const postgres = createPostgres({ connectionString: dbUrl, max: 1 });
    const withPostgres = createServer(betterSupabase, {
      env: {
        url,
        publishableKey,
        secretKey,
        jwksUrl: new URL("/auth/v1/.well-known/jwks.json", url),
      },
      postgres,
    });
    try {
      await pool.query(`
        create table public.${guard} (user_id uuid references auth.users (id) on delete cascade);
        insert into public.${guard} values ('${userId}');
        create function public.${guard}() returns trigger language plpgsql as $$
        begin
          raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
        end;
        $$;
        create constraint trigger ${guard} after delete on public.${guard}
          deferrable initially deferred for each row execute function public.${guard}();
        alter table public.${table} drop constraint ${table}_user_id_fkey,
          add foreign key (user_id) references auth.users (id) on delete cascade;
      `);
      const result = await withPostgres.deleteAccount(userId, {
        buckets: [documents],
      });
      expect(result).toMatchObject({
        ok: false,
        error: { hint: "ORGANIZATION_OWNER_REQUIRED", table: "auth.users" },
      });
      expect(
        await documents.connect(service).list({ userId }).orThrow(),
      ).toHaveLength(2);
      const { data } = await service.auth.admin.getUserById(userId);
      expect(data.user?.id).toBe(userId);
    } finally {
      await pool.query(`
        drop table if exists public.${guard};
        drop function if exists public.${guard}();
        alter table public.${table} drop constraint if exists ${table}_user_id_fkey,
          add foreign key (user_id) references auth.users (id);
      `);
      await postgres.end();
    }
  });

  it("removes the user’s objects, the user and their cascaded rows", async () => {
    await pool.query(`alter table public.${table}
      drop constraint ${table}_user_id_fkey,
      add foreign key (user_id) references auth.users (id) on delete cascade`);
    const notices: MutationNotice[] = [];
    const off = betterSupabase.on("mutation", (notice) => notices.push(notice));

    const result = await server.deleteAccount(userId, {
      buckets: [documents, shared, logos],
      cascades: ["customers"],
    });
    off();

    expect(result).toMatchObject({
      ok: true,
      data: {
        userId,
        removed: { "bs-it-documents": 2, "bs-it-shared": 1 },
      },
    });
    expect(await documents.connect(service).list({ userId }).orThrow()).toEqual(
      [],
    );
    const kept = await shared
      .connect(service)
      .list({ organizationId: ORG })
      .orThrow();
    expect(kept.map((object) => object.path)).toEqual([
      `${ORG}/${otherId}/c.txt`,
    ]);
    expect(
      await documents.connect(service).list({ userId: otherId }).orThrow(),
    ).toHaveLength(2);

    const { data } = await service.auth.admin.getUserById(userId);
    expect(data.user).toBeNull();
    const { rows } = await pool.query(`select 1 from public.${table}`);
    expect(rows).toEqual([]);
    expect(notices.map(({ table: t, kind, rows: r }) => [t, kind, r])).toEqual([
      ["auth.users", "delete", [{ id: userId }]],
      ["customers", "delete", []],
    ]);
  });

  it("returns not_found for a user that no longer exists", async () => {
    expect(await server.deleteAccount(userId)).toMatchObject({
      ok: false,
      error: { kind: "not_found" },
    });
  });
});
