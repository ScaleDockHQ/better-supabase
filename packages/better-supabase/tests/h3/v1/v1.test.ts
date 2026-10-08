import { describe, expect, it } from "vitest";

import type { NodeHeaderTarget } from "../../../src/bridges/node-headers.ts";

import { DbException, dbError } from "../../../src/core/errors.ts";
import { guard, problemOnError, toH3V1 } from "../../../src/h3/v1/index.ts";
import { withBetterSupabase } from "../../../src/server/composite.ts";
import { withServerTiming } from "../../../src/server/entries/timing.ts";
import { server, signer, USER } from "../../fixtures/test-server.ts";

function headerStore(): NodeHeaderTarget & {
  readonly values: Map<string, number | string | readonly string[]>;
} {
  const values = new Map<string, number | string | readonly string[]>();
  return {
    values,
    getHeader: (name) => values.get(name),
    setHeader: (name, value) => values.set(name, value),
  };
}

async function eventAs(role?: string, context: Record<string, unknown> = {}) {
  const headers: Record<string, string> = { host: "app.test" };
  if (role) {
    headers["authorization"] =
      `Bearer ${await signer.sign({ sub: USER, app_metadata: { role } })}`;
  }
  const res = headerStore();
  return {
    node: { req: { method: "GET", url: "/admin", headers }, res },
    context,
    res,
  };
}

describe("toH3V1", () => {
  const middleware = toH3V1([
    withBetterSupabase(server, { allow: ["user", "anon"] }),
    withServerTiming(),
  ]);

  it("puts the contributions on event.context and continues", async () => {
    const event = await eventAs("member");
    expect(await middleware(event)).toBeUndefined();
    expect(event.context).toHaveProperty("db");
    expect(event.context).toMatchObject({ bs: { auth: { kind: "user" } } });
  });

  it("returns the entries' short circuit", async () => {
    const strict = toH3V1([withBetterSupabase(server, { allow: ["user"] })]);
    expect((await strict(await eventAs()))?.status).toBe(401);
  });

  it("reads the env from the Cloudflare bindings or the env option", async () => {
    let seen: unknown;
    const withEnv = toH3V1([withBetterSupabase(server, { allow: ["anon"] })], {
      env: (event) => {
        seen = event.context.cloudflare?.env;
        return seen;
      },
    });
    await withEnv(
      await eventAs(undefined, { cloudflare: { env: { A: "1" } } }),
    );
    expect(seen).toEqual({ A: "1" });
  });
});

describe("h3 v1 guard and problemOnError", () => {
  it("refuses callers without the role and lets the others through", async () => {
    const middleware = toH3V1([
      withBetterSupabase(server, { allow: ["user"] }),
    ]);
    const admins = guard({ roles: ["admin"] });
    const member = await eventAs("member");
    await middleware(member);
    expect((await admins(member))?.status).toBe(403);
    const admin = await eventAs("admin");
    await middleware(admin);
    expect(await admins(admin)).toBeUndefined();
  });

  it("maps thrown DbExceptions only", async () => {
    const onError = problemOnError();
    const event = await eventAs();
    expect(
      onError(new DbException(dbError("conflict", "Taken")), event)?.status,
    ).toBe(409);
    expect(onError(new Error("boom"), event)).toBeUndefined();
  });
});
