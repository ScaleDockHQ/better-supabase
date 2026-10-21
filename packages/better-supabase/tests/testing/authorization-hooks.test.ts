import { describe, expect, it } from "vitest";

import type {
  AuthorizationHooks,
  SubscriberPolicy,
} from "../../src/core/contracts/authorization-hooks.ts";

import { defineAuthorizationHooks } from "../../src/core/contracts/authorization-hooks.ts";
import { testAuthorizationHooks } from "../../src/testing/authorization-hooks.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";

const closed = defineAuthorizationHooks({
  apiVersion: 1,
  name: "closed",
  delivery: {
    subscribers: (_event, subscribers) =>
      subscribers.filter((entry) => entry.kind === "service"),
    audience: () => [],
  },
  identities: { principalByIdentity: () => null },
  approverOf: (approver, request) => approver.userId !== request.requester,
  tickets: { subject: () => null },
  automation: { runAs: () => null, mayPublish: () => false },
  chat: { onAction: (_action, author) => ({ allowed: author !== null }) },
  support: { authorize: () => false },
  delegation: {
    permissions: ({ scopes }) =>
      scopes.includes("posts") ? ["posts.read"] : [],
  },
});

async function failures(hooks: AuthorizationHooks): Promise<string[]> {
  const error = await testAuthorizationHooks(hooks).then(
    () => undefined,
    (cause: unknown) => cause,
  );

  expect(error).toBeInstanceOf(ConformanceError);

  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe("testAuthorizationHooks", () => {
  it("passes hooks that fail closed for strangers", async () => {
    const report = await testAuthorizationHooks(closed);
    expect(report.subject).toBe('AuthorizationHooks "closed"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(report.checks).toHaveLength(12);
    expect(Object.isFrozen(closed)).toBe(true);
  });

  it("checks only the hooks that are set", async () => {
    const report = await testAuthorizationHooks({
      apiVersion: 1,
      name: "bare",
    });

    expect(report.checks.map((check) => check.name)).toEqual([
      "targets API v1 and has a name",
    ]);
  });

  it("names every hook that lets a stranger through", async () => {
    const leaky: AuthorizationHooks = {
      apiVersion: 1,
      name: "leaky",
      delivery: {
        subscribers: (() => [
          { principal: "invented" },
        ]) as unknown as SubscriberPolicy,
        audience: (_event, subscribers) => subscribers,
      },
      identities: {
        principalByIdentity: () => ({ kind: "user", userId: "someone" }),
      },
      approverOf: () => true,
      tickets: { subject: () => ({}) },
      automation: {
        runAs: () => ({ role: "authenticated" }),
        mayPublish: () => true,
      },
      chat: { onAction: () => ({ allowed: true }) },
      support: { authorize: ({ admin }) => ({ approvedBy: admin.user.id }) },
      delegation: { permissions: () => ["*"] },
    };

    expect(await failures(leaky)).toEqual([
      "subscribers returns a subset",
      "an unlinked identity is null",
      "a requester never approves their own request",
      "a forged ticket is null",
      "an unknown publisher may not publish",
      "an unknown publisher runs as no one",
      "an unlinked chat author is refused",
      "an admin with no claims cannot start a support session",
      "an admin never approves their own support session",
      "a delegation with no scopes grants no permissions",
    ]);
    expect(
      await failures({
        ...closed,
        // @ts-expect-error -- the kit checks hooks written in JavaScript too.
        apiVersion: 2,
      }),
    ).toEqual(["targets API v1 and has a name"]);
  });
});
