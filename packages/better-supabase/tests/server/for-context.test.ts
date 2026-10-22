import { describe, expect, it, vi } from "vitest";

import type { TicketSubject } from "../../src/core/contracts/authorization-hooks.ts";
import type {
  BetterPostgres,
  SessionOptions,
  SqlClaims,
} from "../../src/postgres/pool.ts";

import { unwrap, withContext } from "../../src/blocks/queue/envelope.ts";
import { defineAuthorizationHooks } from "../../src/core/contracts/authorization-hooks.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { createServer } from "../../src/server/server.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const USER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const user = { id: USER, kind: "user" as const };

function fakePostgres() {
  const fake = fakeSql();
  const claims: SqlClaims[] = [];
  const sessions: (SessionOptions | undefined)[] = [];

  // SAFETY: the server only calls executorFor; the executor only calls queryRaw.
  const postgres = {
    admin: fake.sql,
    anon: fake.sql,
    executorFor: (value: SqlClaims, session?: SessionOptions) => {
      claims.push(value);
      sessions.push(session);

      return postgresExecutor(fake.sql);
    },
  } as unknown as BetterPostgres;

  return { postgres, claims, sessions };
}

describe("forContext delegation", () => {
  it("runs a delegated job with the client's scope and act chain", async () => {
    const { postgres, claims } = fakePostgres();
    const server = createServer(defineSupabase(schema), { env, postgres });
    const act = { sub: "agent-1", act: { sub: "client-1" } };

    const stored = withContext(null, {
      actor: user,
      claims: {
        client_id: "client-1",
        scope: "posts:read",
        authorization_details: [{ type: "posts" }],
        act,
      },
    });

    const db = await server
      .forContext(unwrap(JSON.parse(JSON.stringify(stored))).context)
      .orThrow();

    expect(claims).toEqual([
      {
        role: "authenticated",
        sub: USER,
        client_id: "client-1",
        scope: "posts:read",
        authorization_details: [{ type: "posts" }],
        act,
      },
    ]);
    expect(db.$context.claims).toMatchObject({ scope: "posts:read", act });
  });

  it("never lets claimsFor widen a delegated token", async () => {
    const { postgres, claims } = fakePostgres();

    const server = createServer(defineSupabase(schema), {
      env,
      postgres,
      claimsFor: () => ({ scope: "admin", client_id: "x", user_role: "r" }),
    });

    await server
      .forContext({ actor: user, claims: { client_id: "c" } })
      .orThrow();
    expect(claims).toEqual([
      { role: "authenticated", sub: USER, client_id: "c", user_role: "r" },
    ]);
  });

  it("refuses malformed delegation claims before claimsFor runs", async () => {
    const { postgres, claims } = fakePostgres();
    const claimsFor = vi.fn(() => ({}));

    const server = createServer(defineSupabase(schema), {
      env,
      postgres,
      claimsFor,
    });

    const result = await server.forContext({
      actor: user,
      claims: { client_id: "c", authorization_details: "all" },
    });

    expect(result.error).toMatchObject({
      kind: "forbidden",
      message: "forContext got invalid delegation claims",
    });
    expect(claimsFor).not.toHaveBeenCalled();
    expect(claims).toEqual([]);
  });

  it("caps a delegated context to the keys the delegation hook maps its scopes to", async () => {
    const { postgres, claims } = fakePostgres();

    const permissions = vi.fn(({ scopes }: { scopes: readonly string[] }) =>
      scopes.includes("posts:read") ? ["posts.read", "posts.list"] : [],
    );

    const server = createServer(defineSupabase(schema), {
      env,
      postgres,
      authorization: defineAuthorizationHooks({
        apiVersion: 1,
        name: "scopes",
        delegation: { permissions },
      }),
    });

    const context = {
      actor: user,
      tenant: OTHER,
      claims: { client_id: "c", scope: "posts:read" },
    };

    await server.forContext(context).orThrow();
    await server
      .forContext(context, { permissions: ["posts.read", "posts.delete"] })
      .orThrow();
    await server.forContext({ actor: user }).orThrow();
    expect(permissions).toHaveBeenCalledTimes(2);
    expect(permissions).toHaveBeenCalledWith({
      userId: USER,
      tenant: OTHER,
      clientId: "c",
      scopes: ["posts:read"],
    });
    expect(claims.map((entry) => entry["bsb_permission_cap"])).toEqual([
      ["posts.read", "posts.list"],
      ["posts.read"],
      undefined,
    ]);
  });

  it("grants a delegated context nothing when the delegation hook throws", async () => {
    const { postgres, claims } = fakePostgres();

    const server = createServer(defineSupabase(schema), {
      env,
      postgres,
      authorization: defineAuthorizationHooks({
        apiVersion: 1,
        name: "broken",
        delegation: {
          permissions: () => {
            throw new Error("down");
          },
        },
      }),
    });

    await server
      .forContext({ actor: user, claims: { client_id: "c" } })
      .orThrow();
    expect(claims[0]?.["bsb_permission_cap"]).toEqual([]);
  });
});

describe("forContext tickets", () => {
  it("runs as the context the ticket resolves to, never the recorded one", async () => {
    const { postgres, claims } = fakePostgres();

    const subject = vi.fn<TicketSubject>(async () => ({
      actor: { id: OTHER, kind: "user" },
      tenant: "t2",
    }));

    const server = createServer(defineSupabase(schema), {
      env,
      postgres,
      authorization: defineAuthorizationHooks({
        apiVersion: 1,
        name: "test",
        tickets: { subject },
      }),
    });

    const db = await server
      .forContext({ actor: user, tenant: "t1", ticket: "tk-1" })
      .orThrow();

    expect(subject).toHaveBeenCalledWith("tk-1");
    expect(db.$context.actor?.id).toBe(OTHER);
    expect(claims).toEqual([
      { role: "authenticated", sub: OTHER, tenant_id: "t2" },
    ]);
  });

  it("prefers the ticket option over the provider hook", async () => {
    const { postgres, claims } = fakePostgres();
    const hook = vi.fn<TicketSubject>(() => null);

    const server = createServer(defineSupabase(schema), {
      env,
      postgres,
      authorization: {
        apiVersion: 1,
        name: "test",
        tickets: { subject: hook },
      },
    });

    await server
      .forContext(
        { ticket: "tk-1" },
        { ticket: () => ({ actor: { id: OTHER, kind: "user" } }) },
      )
      .orThrow();
    expect(hook).not.toHaveBeenCalled();
    expect(claims).toEqual([{ role: "authenticated", sub: OTHER }]);
  });

  it("fails with forbidden for a refused, thrown, missing or malformed ticket", async () => {
    const { postgres, claims } = fakePostgres();
    const server = createServer(defineSupabase(schema), { env, postgres });

    const cases: [
      Record<string, unknown>,
      TicketSubject | undefined,
      string,
    ][] = [
      [{ actor: user, ticket: "tk" }, () => null, "refused"],
      [
        { actor: user, ticket: "tk" },
        () => Promise.reject(new Error("revoked")),
        "refused",
      ],
      [{ actor: user, ticket: "tk" }, undefined, "no ticket resolver"],
      [{ actor: user, ticket: 7 }, () => ({ actor: user }), "invalid ticket"],
      [
        { actor: user, ticket: "tk" },
        () => ({ actor: { id: "svc", kind: "service" } }),
        "got service",
      ],
    ];

    for (const [context, ticket, message] of cases) {
      const result = await server.forContext(
        context,
        ticket === undefined ? {} : { ticket },
      );

      expect(result.error).toMatchObject({ kind: "forbidden" });
      expect(result.error?.message).toContain(message);
    }

    expect(claims).toEqual([]);
  });
});
