import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Sandbox } from "../../../src/create/lite/index.ts";

import { designDataApi, openSandbox } from "../../../src/create/lite/index.ts";

const files = [
  {
    path: "app.sql",
    module: "app",
    contents: `
      create table public.notes (
        id uuid primary key default gen_random_uuid(),
        owner_id uuid not null default auth.uid(),
        title text not null,
        tags text[] default '{}',
        body jsonb
      );
      alter table public.notes enable row level security;
      create policy read_own on public.notes for select to authenticated
        using (owner_id = auth.uid());
      create policy write_own on public.notes for insert to authenticated
        with check (owner_id = auth.uid());
      create policy update_own on public.notes for update to authenticated
        using (owner_id = auth.uid());
      create function public.shout(word text) returns text language sql as $$ select upper(word) $$;
    `,
  },
];

const ada = "00000000-0000-4000-8000-00000000000a";
const bob = "00000000-0000-4000-8000-00000000000b";

let sandbox: Sandbox;

beforeAll(async () => {
  sandbox = await openSandbox({ files });
}, 60_000);

afterAll(async () => {
  await sandbox.close();
});

const request = (path: string, init: RequestInit = {}): Request =>
  new Request(`http://localhost/rest/v1/${path}`, init);

describe("openSandbox", () => {
  it("applies the files without errors", () => {
    expect(sandbox.issues).toEqual([]);
  });

  it("applies row level security per persona", async () => {
    const asAda = sandbox.as({ sub: ada });
    const asBob = sandbox.as({ sub: bob });

    const inserted = await asAda.query(
      "insert into public.notes (title) values ('hello') returning owner_id",
    );

    expect(inserted).toEqual({ ok: true, rows: [{ owner_id: ada }] });

    expect(await asAda.query("select title from public.notes")).toEqual({
      ok: true,
      rows: [{ title: "hello" }],
    });

    expect(await asBob.query("select title from public.notes")).toEqual({
      ok: true,
      rows: [],
    });

    const anon = await sandbox.as({}).query("select title from public.notes");

    expect(anon).toEqual({ ok: true, rows: [] });
  });

  it("reports a rejected write as an error and rolls back", async () => {
    const result = await sandbox
      .as({ sub: bob })
      .query("insert into public.notes (owner_id, title) values ($1, 'x')", [
        ada,
      ]);

    expect(result).toMatchObject({ ok: false, error: { code: "42501" } });
  });

  it("lets the service role see every row", async () => {
    const result = await sandbox
      .as({ role: "service_role" })
      .query("select count(*)::int as n from public.notes");

    expect(result).toEqual({ ok: true, rows: [{ n: 1 }] });
  });
});

describe("rest", () => {
  const token = (claims: object): string =>
    `h.${btoa(JSON.stringify(claims)).replaceAll("=", "")}.s`;

  it("reads with filters, select and order", async () => {
    const response = await sandbox
      .as({ sub: ada })
      .rest(
        request("notes?select=title&title=eq.hello&order=title.desc&limit=5"),
      );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual([{ title: "hello" }]);
  });

  it("takes the persona from the bearer token", async () => {
    const response = await sandbox.rest(
      request("notes", {
        headers: {
          authorization: `Bearer ${token({ sub: bob, role: "authenticated" })}`,
        },
      }),
    );

    expect(await response.json()).toEqual([]);

    const owner = await sandbox.rest(
      request("notes?select=title", {
        headers: {
          authorization: `Bearer ${token({ sub: ada, role: "authenticated" })}`,
        },
      }),
    );

    expect(await owner.json()).toEqual([{ title: "hello" }]);
  });

  it("inserts, updates and returns the representation", async () => {
    const asAda = sandbox.as({ sub: ada });

    const created = await asAda.rest(
      request("notes", {
        method: "POST",
        headers: { prefer: "return=representation" },
        body: JSON.stringify({
          title: "second",
          tags: ["a", "b"],
          body: { k: 1 },
        }),
      }),
    );

    expect(created.status).toBe(201);
    expect(await created.json()).toMatchObject([
      { title: "second", tags: ["a", "b"], body: { k: 1 }, owner_id: ada },
    ]);

    const updated = await asAda.rest(
      request("notes?title=eq.second", {
        method: "PATCH",
        headers: { prefer: "return=representation" },
        body: JSON.stringify({ title: "renamed" }),
      }),
    );

    expect(await updated.json()).toMatchObject([{ title: "renamed" }]);
  });

  it("answers 403 for a write the policy rejects and 401 for anon", async () => {
    const body = JSON.stringify({ title: "nope", owner_id: ada });

    const forbidden = await sandbox
      .as({ sub: bob })
      .rest(request("notes", { method: "POST", body }));

    expect(forbidden.status).toBe(403);

    const anon = await sandbox
      .as({})
      .rest(request("notes", { method: "POST", body }));

    expect(anon.status).toBe(401);
  });

  it("calls a function and rejects what it does not support", async () => {
    const shout = await sandbox
      .as({ sub: ada })
      .rest(
        request("rpc/shout", {
          method: "POST",
          body: JSON.stringify({ word: "hi" }),
        }),
      );

    expect(await shout.json()).toBe("HI");

    const embed = await sandbox
      .as({ sub: ada })
      .rest(request("notes?select=*,owner(*)"));

    expect(embed.status).toBe(400);

    const missing = await sandbox.as({ sub: ada }).rest(request("nothing"));

    expect(missing.status).toBe(404);
  });
});

describe("designDataApi", () => {
  it("describes the tables a design creates", async () => {
    const result = await designDataApi(
      "saas",
      {
        appTables: {
          tasks: { columns: { title: { type: "text", nullable: false } } },
        },
      },
      { supabaseUrl: "https://example.supabase.co" },
    );

    expect(result.ok).toBe(true);

    if (!result.ok) {
      return;
    }

    expect(result.tables).toContain("tasks");

    expect(result.document).toMatchObject({
      openapi: expect.stringMatching(/^3\.1/u),
      paths: {
        "/rest/v1/tasks": { get: expect.anything(), post: expect.anything() },
      },
    });
  }, 60_000);

  it("returns the issues of a bad design", async () => {
    const result = await designDataApi("saas", {
      appTables: { "Bad Name": {} },
    });

    expect(result).toMatchObject({ ok: false });
  }, 60_000);
});
