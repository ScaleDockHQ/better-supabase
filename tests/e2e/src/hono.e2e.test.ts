import { afterAll, beforeAll, describe, expect, it } from "vitest";

import app from "@better-supabase/example-hono-api/app";

import {
  ACME,
  cleanup,
  createUser,
  OTHER,
  reachable,
  type TestUser,
} from "./stack.ts";

describe.skipIf(!(await reachable()))("hono-api example", () => {
  let acme: TestUser;
  let other: TestUser;
  const rows = cleanup("customers");

  beforeAll(async () => {
    [acme, other] = await Promise.all([createUser(ACME), createUser(OTHER)]);
  });
  afterAll(async () => {
    await rows.run();
    await Promise.all([acme.remove(), other.remove()]);
  });

  const call = (
    user: TestUser | undefined,
    path: string,
    init: { method?: string; body?: unknown } = {},
  ) => {
    const headers = new Headers();
    if (user) headers.set("authorization", `Bearer ${user.accessToken}`);
    if (init.body !== undefined)
      headers.set("content-type", "application/json");
    return app.request(path, {
      method: init.method ?? "GET",
      headers,
      body: init.body === undefined ? null : JSON.stringify(init.body),
    });
  };

  it("runs CRUD as the signed-in user, scoped by RLS", async () => {
    const name = `Hono e2e ${crypto.randomUUID()}`;
    const created = await call(acme, "/api/customers", {
      method: "POST",
      body: { name, organizationId: ACME },
    });
    const row = (await created.json()) as { id: string; code?: string };
    expect({ status: created.status, code: row.code }).toEqual({
      status: 201,
      code: undefined,
    });
    rows.track(row.id);

    expect(
      await (
        await call(acme, `/api/customers?q=${encodeURIComponent(name)}`)
      ).json(),
    ).toMatchObject({
      items: [{ id: row.id, name, status: "lead" }],
    });
    expect((await call(other, `/api/customers/${row.id}`)).status).toBe(404);
    expect(
      (
        await call(other, "/api/customers", {
          method: "POST",
          body: { name, organizationId: ACME },
        })
      ).status,
    ).toBe(403);
    expect(
      await (await call(acme, `/api/customers/${row.id}/notes`)).json(),
    ).toEqual({ items: [] });
    expect(
      (await call(acme, `/api/customers/${row.id}`, { method: "DELETE" }))
        .status,
    ).toBe(204);
  });

  it("answers anonymous callers with a 401 problem", async () => {
    const response = await call(undefined, "/api/customers");
    expect(response.status).toBe(401);
    expect(response.headers.get("content-type")).toContain(
      "application/problem+json",
    );
  });

  it("rejects unknown sort values with a 422 problem", async () => {
    const response = await call(acme, "/api/customers?sort=nope");
    expect(response.status).toBe(422);
    expect(await response.json()).toMatchObject({ kind: "validation" });
  });
});
