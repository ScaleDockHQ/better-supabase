import { describe, expect, it } from "vitest";

import {
  type AuthorizationRequest,
  type Authorizer,
  checkPermission,
  defineAuthorizer,
} from "../../src/core/authorizer.ts";
import {
  staticAuthorizer,
  testAuthorizer,
} from "../../src/testing/authorizer.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";

type Ref = "export" | "invite" | "purge";

const USER = "11111111-1111-4111-8111-111111111111";
const member = {
  actor: { id: USER, kind: "user", role: "authenticated" },
} as const;

const authorizer = staticAuthorizer<Ref>({
  roles: { authenticated: ["export"] },
  grants: { [USER]: ["purge"] },
  approvals: ["invite"],
});

async function failures<R>(
  subject: Authorizer<R>,
  permissions: readonly R[],
  unknown?: R,
): Promise<string[]> {
  const error = await testAuthorizer(subject, {
    permissions,
    ...(unknown === undefined ? {} : { unknown }),
  }).then(
    () => undefined,
    (cause: unknown) => cause,
  );
  expect(error).toBeInstanceOf(ConformanceError);
  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe("testAuthorizer", () => {
  it("passes the static authorizer", async () => {
    const report = await testAuthorizer(authorizer, {
      permissions: ["export", "invite", "purge"],
      granted: { permission: "export", context: member },
      unknown: "drop",
    });
    expect(report.subject).toBe('Authorizer "static"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("refuses a batch that loses the request order", async () => {
    const shuffled = defineAuthorizer({
      name: "shuffled",
      key: (ref) => ref,
      evaluate: (request) =>
        request.resource.id === "a"
          ? { outcome: "granted" }
          : { outcome: "denied" },
      evaluations: (requests) =>
        Promise.resolve(
          requests.map((_, index) =>
            index === 0 ? { outcome: "granted" } : { outcome: "denied" },
          ),
        ),
    });
    expect(await failures(shuffled, ["read"])).toEqual([
      "keeps the request order in evaluations",
    ]);
  });

  it("refuses an authorizer that trusts the input", async () => {
    const trusting = defineAuthorizer({
      name: "trusting",
      key: (ref) => ref,
      evaluate: (request) =>
        request.resource.properties?.["role"] === "service_role"
          ? { outcome: "granted" }
          : { outcome: "denied" },
    });
    expect(await failures(trusting, ["read"])).toEqual([
      "decides from the subject, never from the input",
    ]);
  });

  it("refuses an authorizer that trusts forged claims", async () => {
    const readers: Record<string, (request: AuthorizationRequest) => unknown> =
      {
        resource: (request) => request.resource.properties?.["claims"],
        "context claims": (request) => request.context["claims"],
        "context memberships": (request) => request.context["memberships"],
      };
    for (const read of Object.values(readers)) {
      const trusting = defineAuthorizer({
        name: "claims",
        key: (ref) => ref,
        evaluate: (request) =>
          read(request) ? { outcome: "granted" } : { outcome: "denied" },
      });
      expect(await failures(trusting, ["read"])).toEqual([
        "decides from the subject, never from the input",
      ]);
    }
  });

  it("passes an authorizer that reads the subject's claims", async () => {
    const reading = defineAuthorizer({
      name: "reading",
      key: (ref) => ref,
      evaluate: (request) =>
        request.subject.properties?.["claims"]
          ? { outcome: "granted" }
          : { outcome: "denied" },
    });
    const report = await testAuthorizer(reading, { permissions: ["read"] });
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("refuses unstable keys, references that aren't JSON and unknown grants", async () => {
    let calls = 0;
    const unstable = defineAuthorizer({
      name: "unstable",
      key: (ref) => `${ref}:${calls++}`,
      evaluate: () => ({ outcome: "granted" }),
    });
    expect(await failures(unstable, ["read"], "nope")).toEqual([
      "keys every permission stably, as plain JSON",
      "never grants an unknown permission",
    ]);
    const objects = defineAuthorizer<{ name: string } | Date>({
      name: "objects",
      key: (ref) => ("name" in ref ? ref.name : "date"),
      evaluate: () => ({ outcome: "denied" }),
    });
    expect(await failures(objects, [new Date(0)])).toEqual([
      "keys every permission stably, as plain JSON",
    ]);
  });

  it("refuses an unknown outcome, another API version and no permissions", async () => {
    const vague = {
      ...defineAuthorizer({
        name: "vague",
        key: (ref) => ref,
        // SAFETY: a malformed outcome, as an untyped adapter could return.
        evaluate: () => ({ outcome: "maybe" }) as never,
      }),
      apiVersion: 2,
    };
    // SAFETY: the kit checks adapters written in JavaScript too.
    const subject = vague as unknown as Authorizer;
    expect(await failures(subject, ["read"])).toEqual([
      "targets API v1",
      "answers every request with a known outcome, without mutating it",
    ]);
    expect(await failures(authorizer, [])).toEqual(["targets API v1"]);
  });
});

describe("staticAuthorizer", () => {
  const decide = (request: Partial<AuthorizationRequest<Ref>>) =>
    authorizer.evaluate({
      subject: {
        type: "user",
        id: "other",
        properties: { role: "authenticated" },
      },
      action: "export",
      resource: { type: "test" },
      context: {},
      ...request,
    });

  it("grants by role and by subject id", async () => {
    expect(await decide({})).toEqual({ outcome: "granted" });
    expect(await decide({ action: "purge" })).toMatchObject({
      outcome: "denied",
    });
    expect(
      await decide({
        action: "purge",
        subject: { type: "user", id: USER },
      }),
    ).toEqual({ outcome: "granted" });
    expect(
      await decide({ subject: { type: "anon", id: "anonymous" } }),
    ).toMatchObject({ outcome: "denied" });
  });

  it("asks for an approval and works through checkPermission", async () => {
    expect(await decide({ action: "invite" })).toEqual({
      outcome: "approval-required",
      approval: { id: "approval:invite" },
    });
    const checked = await checkPermission({
      authorizer,
      permission: "invite",
      resource: { type: "test" },
      context: member,
    });
    expect(checked.ok ? undefined : checked.error).toMatchObject({
      code: "APPROVAL_REQUIRED",
    });
  });
});
