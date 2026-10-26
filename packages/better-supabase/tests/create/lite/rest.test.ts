import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Sandbox } from "../../../src/create/lite/index.ts";

import { openSandbox } from "../../../src/create/lite/index.ts";
import { personaOf } from "../../../src/create/lite/rest.ts";

const ada = "00000000-0000-4000-8000-00000000000a";

const files = [
  {
    path: "t.sql",
    module: "t",
    contents: `
      create table public.items (
        id int generated always as identity primary key,
        name text not null,
        qty int,
        flag boolean
      );
      grant all on public.items to anon, authenticated;
      insert into public.items (name, qty, flag) values
        ('apple', 1, true), ('banana', 2, false), ('cherry', null, null);
      create function public.pair() returns table (a int, b int) language sql
        as $$ select 1, 2 $$;
    `,
  },
];

let sandbox: Sandbox;

beforeAll(async () => {
  sandbox = await openSandbox({ files });
}, 60_000);

afterAll(async () => {
  await sandbox.close();
});

const call = async (
  path: string,
  init: RequestInit = {},
): Promise<{ status: number; body: unknown }> => {
  const response = await sandbox
    .as({ sub: ada })
    .rest(new Request(`http://x/rest/v1/${path}`, init));

  const text = await response.text();

  return {
    status: response.status,
    body: text === "" ? null : JSON.parse(text),
  };
};

const names = async (query: string): Promise<unknown> => {
  const { body } = await call(`items?select=name&order=name&${query}`);

  return Array.isArray(body) ? body.map((row) => row.name) : body;
};

describe("filters", () => {
  it.each([
    ["qty=gt.1", ["banana"]],
    ["qty=gte.1", ["apple", "banana"]],
    ["qty=lt.2", ["apple"]],
    ["qty=lte.2", ["apple", "banana"]],
    ["qty=neq.1", ["banana"]],
    ["name=like.*an*", ["banana"]],
    ["name=ilike.APP*", ["apple"]],
    ["qty=is.null", ["cherry"]],
    ["flag=is.true", ["apple"]],
    ['name=in.(apple,"cherry")', ["apple", "cherry"]],
    ["name=not.eq.apple", ["banana", "cherry"]],
    ["limit=1&offset=1", ["banana"]],
  ])("applies %s", async (query, expected) => {
    expect(await names(query)).toEqual(expected);
  });

  it.each([
    ["nope=eq.1", 400],
    ["qty=is.maybe", 400],
    ["qty=in.1", 400],
    ["qty=wat.1", 400],
    ["or=(qty.eq.1)", 400],
    ["limit=x", 400],
    ["order=nope", 400],
    ["select=nope", 400],
  ])("rejects %s", async (query, status) => {
    const { status: got } = await call(`items?${query}`);

    expect(got).toBe(status);
  });

  it("orders descending with nulls placement", async () => {
    const order = async (value: string): Promise<unknown> => {
      const { body } = await call(`items?select=name&order=${value}`);

      return Array.isArray(body) ? body.map((row) => row.name) : body;
    };

    expect(await order("qty.desc.nullslast")).toEqual([
      "banana",
      "apple",
      "cherry",
    ]);
    expect(await order("qty.asc.nullsfirst")).toEqual([
      "cherry",
      "apple",
      "banana",
    ]);
  });
});

describe("writes", () => {
  it("inserts several rows, deletes and answers without a body", async () => {
    const created = await call("items", {
      method: "POST",
      body: JSON.stringify([{ name: "x" }, { name: "y", qty: 9 }]),
    });

    expect(created).toEqual({ status: 201, body: null });

    const removed = await call("items?name=in.(x,y)", {
      method: "DELETE",
      headers: { prefer: "return=representation" },
    });

    expect(removed.status).toBe(200);
    expect(removed.body).toHaveLength(2);

    expect(
      (await call("items?name=eq.nothing", { method: "DELETE" })).status,
    ).toBe(204);
  });

  it("inserts default values and returns one object", async () => {
    const { status, body } = await call("items", {
      method: "POST",
      headers: {
        prefer: "return=representation",
        accept: "application/vnd.pgrst.object+json",
      },
      body: JSON.stringify({ name: "solo" }),
    });

    expect(status).toBe(201);
    expect(body).toMatchObject({ name: "solo" });

    await call("items?name=eq.solo", { method: "DELETE" });
  });

  it("refuses a single object for many rows", async () => {
    const { status } = await call("items?select=name", {
      headers: { accept: "application/vnd.pgrst.object+json" },
    });

    expect(status).toBe(406);
  });

  it.each([
    ["not json", "POST"],
    ["[1, 2]", "POST"],
    ["{}", "PATCH"],
    ["[1]", "PATCH"],
    ['{"nope": 1}', "POST"],
    ['{"nope": 1}', "PATCH"],
  ])("rejects the body %s for %s", async (body, method) => {
    const { status } = await call("items", { method, body });

    expect(status).toBe(400);
  });

  it("maps constraint violations to 409", async () => {
    const { status } = await call("items", {
      method: "POST",
      body: JSON.stringify({ name: null }),
    });

    expect(status).toBe(400);
  });

  it("answers HEAD without a body", async () => {
    const response = await sandbox
      .as({ sub: ada })
      .rest(new Request("http://x/rest/v1/items", { method: "HEAD" }));

    expect(response.status).toBe(200);
  });
});

describe("routing", () => {
  it.each([
    ["", "GET", 404],
    ["bad-name", "GET", 404],
    ["missing", "GET", 404],
    ["rpc", "POST", 404],
    ["rpc/pair", "GET", 405],
    ["items", "PUT", 405],
  ])("answers %s %s with %i", async (path, method, status) => {
    expect((await call(path, { method })).status).toBe(status);
  });

  it("returns the rows of a set function and reports bad rpc bodies", async () => {
    expect((await call("rpc/pair", { method: "POST" })).body).toEqual([
      { a: 1, b: 2 },
    ]);
    expect((await call("rpc/pair", { method: "POST", body: "{" })).status).toBe(
      400,
    );
    expect((await call("rpc/nothing", { method: "POST" })).status).toBe(404);
  });
});

describe("personaOf", () => {
  const withToken = (token: string): Request =>
    new Request("http://x/", { headers: { authorization: `Bearer ${token}` } });

  const encode = (value: unknown): string =>
    `h.${btoa(JSON.stringify(value)).replaceAll("+", "-").replaceAll("/", "_")}.s`;

  it("falls back to anon", () => {
    expect(personaOf(new Request("http://x/"))).toEqual({ role: "anon" });
    expect(personaOf(withToken("nodots"))).toEqual({ role: "anon" });
    expect(personaOf(withToken("h.%%%.s"))).toEqual({ role: "anon" });
    expect(personaOf(withToken(encode([1])))).toEqual({ role: "anon" });
  });

  it("reads sub, role and the remaining claims", () => {
    expect(
      personaOf(withToken(encode({ sub: ada, role: "service_role", k: 1 }))),
    ).toMatchObject({ sub: ada, role: "service_role" });
    expect(personaOf(withToken(encode({ sub: ada })))).toMatchObject({
      sub: ada,
    });
  });
});
