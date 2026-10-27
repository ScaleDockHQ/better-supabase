import { describe, expect, it } from "vitest";

import type {
  AuthorizationRequest,
  Authorizer,
  AuthorizerRuntime,
} from "../../src/core/authorizer.ts";

import {
  bindAuthorizer,
  isRequestMemo,
  requestMemo,
  requestOf,
} from "../../src/core/authorizer.ts";

const USER = "11111111-1111-4111-8111-111111111111";

const claims = {
  aal: "aal2",
  memberships: [{ tenant: "o1", role: "owner" }],
  roles: ["admin"],
};

describe("requestOf context", () => {
  it("adds the purpose, request id and approval, never to the subject", () => {
    const actor = { id: USER, kind: "user", role: "authenticated" } as const;
    const plain = requestOf({ actor, claims });

    const request = requestOf(
      { actor, claims, requestId: "req_1", approval: "apr_1" },
      { intent: "write", operation: "update" },
    );

    expect(request.context).toEqual({
      aal: "aal2",
      scopes: [],
      intent: "write",
      operation: "update",
      requestId: "req_1",
      approval: "apr_1",
    });
    expect(request.subject).toEqual(plain.subject);
  });
});

describe("requestOf claims", () => {
  it("passes the verified claims of a user actor", () => {
    const { subject } = requestOf({
      actor: { id: USER, kind: "user", role: "authenticated" },
      claims,
    });

    expect(subject.type).toBe("user");
    expect(subject.properties).toEqual({ role: "authenticated", claims });
  });

  it("passes the claims, including act, to an agent", () => {
    const delegated = { ...claims, act: { sub: "agent-1" } };

    const { subject } = requestOf({
      actor: { id: USER, kind: "user" },
      claims: delegated,
    });

    expect(subject.type).toBe("agent");
    expect(subject.properties?.["claims"]).toEqual(delegated);
  });

  it("gives an anonymous caller no claims", () => {
    expect(requestOf(undefined).subject).toEqual({
      type: "anon",
      id: "anonymous",
    });
    expect(requestOf({ claims }).subject).toEqual({
      type: "anon",
      id: "anonymous",
    });
  });

  it("leaves out claims that are not an object", () => {
    const { subject } = requestOf({ actor: { id: USER, kind: "user" } });

    expect(subject.properties).toEqual({});
  });

  it("returns a read-only copy", () => {
    const context = { actor: { id: USER, kind: "user" as const }, claims };

    const copy = requestOf(context).subject.properties?.["claims"] as Record<
      string,
      unknown
    >;

    expect(copy).not.toBe(claims);
    expect(() => {
      copy["roles"] = ["owner"];
    }).toThrow(TypeError);
    const memberships = copy["memberships"] as Record<string, unknown>[];
    expect(() => {
      memberships[0]!["role"] = "guest";
    }).toThrow(TypeError);
    expect(context.claims).toEqual({
      aal: "aal2",
      memberships: [{ tenant: "o1", role: "owner" }],
      roles: ["admin"],
    });
  });
});

const versions = { evict: (): void => undefined };

const request: AuthorizationRequest = {
  subject: { type: "user", id: "u1" },
  action: "notes.read",
  resource: { type: "notes", id: "n1" },
  context: {},
};

function recording(): {
  readonly authorizer: Authorizer;
  readonly seen: (AuthorizerRuntime | undefined)[];
} {
  const seen: (AuthorizerRuntime | undefined)[] = [];

  return {
    seen,
    authorizer: {
      apiVersion: 1,
      name: "recording",
      key: (ref) => `key:${ref}`,
      forOperation: (table, operation) => `${table}.${operation}`,
      evaluate: (_request, runtime) => {
        seen.push(runtime);

        return { outcome: "granted" };
      },
      evaluations: (requests, runtime) => {
        seen.push(runtime);

        return Promise.resolve(
          requests.map(() => ({ outcome: "granted" as const })),
        );
      },
    },
  };
}

describe("requestMemo", () => {
  it("runs each key's load once and shares the promise", async () => {
    const memo = requestMemo();
    let loads = 0;

    const load = (): Promise<number> => {
      loads += 1;

      return Promise.resolve(loads);
    };

    const [first, second] = await Promise.all([
      memo.once("a", load),
      memo.once("a", load),
    ]);

    expect([first, second, loads]).toEqual([1, 1, 1]);
    await expect(memo.once("b", load)).resolves.toBe(2);
  });

  it("forgets a load that failed, so the next call retries", async () => {
    const memo = requestMemo();

    await expect(
      memo.once("a", () => Promise.reject(new Error("down"))),
    ).rejects.toThrow("down");
    await expect(memo.once("a", () => Promise.resolve("up"))).resolves.toBe(
      "up",
    );
  });

  it("is recognized by isRequestMemo", () => {
    expect(isRequestMemo(requestMemo())).toBe(true);
    expect(isRequestMemo({ once: "no" })).toBe(false);
    expect(isRequestMemo(null)).toBe(false);
  });
});

describe("bindAuthorizer", () => {
  it("returns the authorizer unchanged without versions", () => {
    const { authorizer } = recording();

    expect(bindAuthorizer(authorizer, {})).toBe(authorizer);
    const none: Authorizer | undefined = undefined;

    expect(
      bindAuthorizer<Authorizer | undefined>(none, { versions }),
    ).toBeUndefined();
  });

  it("merges the server's versions under each call's runtime", async () => {
    const { authorizer, seen } = recording();
    const bound = bindAuthorizer(authorizer, { versions });
    const memo = requestMemo();

    expect(bound.name).toBe("recording");
    expect(bound.key("notes.read")).toBe("key:notes.read");
    expect(bound.forOperation?.("notes", "select")).toBe("notes.select");

    await bound.evaluate(request);
    await bound.evaluate(request, { memo });
    await bound.evaluations?.([request], { memo });

    expect(seen).toEqual([
      { versions },
      { versions, memo },
      { versions, memo },
    ]);
  });

  it("leaves out the batch form when the authorizer has none", () => {
    const { authorizer } = recording();

    const single: Authorizer = {
      apiVersion: 1,
      name: authorizer.name,
      key: (ref) => authorizer.key(ref),
      evaluate: (call, runtime) => authorizer.evaluate(call, runtime),
    };

    const bound: Authorizer = bindAuthorizer<Authorizer>(single, { versions });

    expect("evaluations" in bound).toBe(false);
    expect("forOperation" in bound).toBe(false);
  });
});
