import { describe, expect, it, vi } from "vitest";

import type { AuthorizationRequest } from "../../src/core/authorizer.ts";

import {
  checkEach,
  checkPermission,
  defineAuthorizer,
  requestOf,
} from "../../src/core/authorizer.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const USER = "11111111-1111-4111-8111-111111111111";

describe("AuthZEN Authorization API", () => {
  it("pins version 1.0", () => {
    expect(SPEC_PINS.authzen).toBe("1.0");
  });

  it("builds subject, action, resource and context from the verified request", async () => {
    const evaluate = vi.fn(() => ({ outcome: "granted" }) as const);

    const authorizer = defineAuthorizer({
      name: "test",
      key: String,
      evaluate,
    });

    await checkPermission({
      authorizer,
      permission: "export",
      resource: { type: "customers", id: "c1" },
      context: {
        actor: { id: USER, kind: "user", role: "authenticated" },
        tenant: "org-1",
        claims: { aal: "aal2", scope: "read write" },
      },
    });
    expect(evaluate).toHaveBeenCalledWith({
      subject: {
        type: "user",
        id: USER,
        properties: {
          role: "authenticated",
          claims: { aal: "aal2", scope: "read write" },
        },
      },
      action: "export",
      resource: { type: "customers", id: "c1" },
      context: { tenant: "org-1", aal: "aal2", scopes: ["read", "write"] },
    });
    expect(requestOf(undefined).subject).toEqual({
      type: "anon",
      id: "anonymous",
    });
  });

  it("reads batch results in the request order (Access Evaluations)", async () => {
    const evaluations = vi.fn(
      async (requests: readonly AuthorizationRequest[]) =>
        requests.map((request) =>
          request.resource.id === "b"
            ? ({ outcome: "denied" } as const)
            : ({ outcome: "granted" } as const),
        ),
    );

    const authorizer = defineAuthorizer({
      name: "batch",
      key: String,
      evaluate: () => ({ outcome: "denied" }),
      evaluations,
    });

    const granted = await checkEach(
      authorizer,
      "read",
      ["a", "b", "c"].map((id) => ({ type: "customers", id })),
      undefined,
    );

    expect(granted).toEqual([true, false, true]);
    expect(evaluations).toHaveBeenCalledOnce();
    expect(
      evaluations.mock.calls[0]![0].map((request) => request.resource.id),
    ).toEqual(["a", "b", "c"]);
  });

  it("denies when the decision point fails or gives no decision", async () => {
    const throwing = defineAuthorizer({
      name: "throwing",
      key: String,
      evaluate: () => {
        throw new Error("down");
      },
      evaluations: () => Promise.reject(new Error("down")),
    });

    const resource = { type: "customers" };

    const checked = await checkPermission({
      authorizer: throwing,
      permission: "read",
      resource,
      context: undefined,
    });

    expect(checked.ok ? undefined : checked.error).toMatchObject({
      kind: "forbidden",
      code: "PERMISSION_DENIED",
    });
    expect(
      await checkEach(throwing, "read", [resource, resource], undefined),
    ).toEqual([false, false]);

    const vague = defineAuthorizer({
      name: "vague",
      key: String,
      // SAFETY: a malformed outcome, as an untyped decision point could return.
      evaluate: () => ({ outcome: "maybe" }) as never,
    });

    const undecided = await checkPermission({
      authorizer: vague,
      permission: "read",
      resource,
      context: undefined,
    });

    expect(undecided.ok).toBe(false);

    const missing = await checkPermission({
      authorizer: undefined,
      permission: "read",
      resource,
      context: undefined,
    });

    expect(missing.ok).toBe(false);
  });
});
