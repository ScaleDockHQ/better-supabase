import { describe, expect, it } from "vitest";

import { contextClaims } from "../../../src/auth/delegation.ts";
import {
  unwrap,
  withContext,
  wrapPayload,
} from "../../../src/blocks/jobs/envelope.ts";

const actor = { id: "user-1", kind: "user" as const };

describe("job envelope", () => {
  it("keeps a delegated client's scope, details and act chain", () => {
    const act = { sub: "agent-1", act: { sub: "client-1" } };
    const details = [{ type: "posts", actions: ["read"] }];
    const stored = withContext(
      { id: 1 },
      {
        actor,
        tenant: "t1",
        claims: {
          client_id: "client-1",
          scope: "posts:read",
          authorization_details: details,
          act,
          email: "dropped@example.test",
        },
      },
    );
    expect(stored).toEqual({
      $bs: 1,
      context: {
        actor,
        tenant: "t1",
        client_id: "client-1",
        scope: "posts:read",
        authorization_details: details,
        act,
      },
      payload: { id: 1 },
    });
    const { payload, context } = unwrap(JSON.parse(JSON.stringify(stored)));
    expect(payload).toEqual({ id: 1 });
    expect(context).toEqual({
      actor,
      tenant: "t1",
      claims: {
        client_id: "client-1",
        scope: "posts:read",
        authorization_details: details,
        act,
      },
    });
    expect(contextClaims(context)).toMatchObject({
      ok: true,
      claims: { client_id: "client-1", scope: "posts:read", act },
    });
  });

  it("keeps a bare client_id token delegated", () => {
    const stored = withContext(null, {
      actor,
      claims: { client_id: "mcp", scope: ["posts:read"] },
    });
    expect(unwrap(stored).context).toEqual({
      actor,
      claims: { client_id: "mcp", scope: "posts:read" },
    });
  });

  it("leaves support and impersonation as they were", () => {
    const support = {
      kind: "support",
      sub: "admin-1",
      session_id: "s-1",
      read_only: true,
    };
    const stored = withContext(null, {
      actor: { ...actor, impersonator: "admin-1" },
      claims: { act: support },
    });
    expect(stored).toMatchObject({ context: { act: support } });
    expect(unwrap(stored).context).toEqual({
      actor: { ...actor, impersonator: "admin-1" },
      claims: { act: support },
    });
    const impersonated = withContext(null, {
      actor,
      claims: { act: { kind: "impersonation", sub: "admin-1", reason: "r" } },
    });
    expect(unwrap(impersonated).context.claims).toEqual({
      act: { kind: "impersonation", sub: "admin-1", reason: "r" },
    });
  });

  it("refuses to record an invalid act chain or malformed delegation", () => {
    for (const claims of [
      { act: { kind: "root", sub: "a" } },
      { client_id: "c", scope: 7 },
    ]) {
      const wrapped = wrapPayload(null, { actor, claims });
      expect(wrapped.ok).toBe(false);
      expect(wrapped.error).toMatchObject({ kind: "forbidden" });
      expect(() => withContext(null, { actor, claims })).toThrow(TypeError);
    }
  });

  it("makes forContext refuse a stored envelope with a bad act chain", () => {
    const { context } = unwrap({
      $bs: 1,
      context: { actor, act: { kind: "root", sub: "a" }, client_id: 3 },
      payload: null,
    });
    expect(context.claims).toEqual({
      act: { kind: "root", sub: "a" },
      client_id: 3,
    });
    expect(contextClaims(context)).toMatchObject({ ok: false });
  });

  it("records a ticket, from the options or the context", () => {
    expect(wrapPayload("p", {}, { ticket: "tk-1" }).data).toEqual({
      $bs: 1,
      context: { ticket: "tk-1" },
      payload: "p",
    });
    expect(wrapPayload("p", undefined, { ticket: "tk-1" }).data).toEqual({
      $bs: 1,
      context: { ticket: "tk-1" },
      payload: "p",
    });
    const stored = withContext("p", { actor, ticket: "tk-2" });
    expect(stored).toEqual({
      $bs: 1,
      context: { actor, ticket: "tk-2" },
      payload: "p",
    });
    expect(unwrap(stored).context).toEqual({ actor, ticket: "tk-2" });
    expect(
      wrapPayload("p", { actor, ticket: "old" }, { ticket: "new" }),
    ).toMatchObject({ data: { context: { ticket: "new" } } });
    for (const ticket of ["", 5]) {
      expect(wrapPayload("p", { actor, ticket }).error).toMatchObject({
        kind: "validation",
      });
    }
    expect(unwrap({ $bs: 1, context: { ticket: 9 }, payload: 1 })).toEqual({
      payload: 1,
      context: { ticket: 9 },
    });
  });

  it("stores a bare payload without an actor, tenant or ticket", () => {
    expect(withContext("p", undefined)).toBe("p");
    expect(withContext("p", { claims: { client_id: "c" } })).toBe("p");
    expect(unwrap("p")).toEqual({ payload: "p", context: {} });
  });
});
