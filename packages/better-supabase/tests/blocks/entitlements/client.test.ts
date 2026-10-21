import { describe, expect, it } from "vitest";

import type { AuthSnapshot } from "../../../src/client/bind.ts";

import { createFeatureGateController } from "../../../src/blocks/entitlements/client.ts";
import { fakeAuth, mount, SIGNED_OUT, USER } from "../../fixtures/ports.ts";

const LOADING: AuthSnapshot = { status: "loading", user: null, claims: null };

const session = (
  tenant: string | undefined,
  features: Record<string, readonly string[]>,
): AuthSnapshot => ({
  status: "signed-in",
  user: { id: USER },
  claims: {
    sub: USER,
    ...(tenant === undefined ? {} : { tenant_id: tenant }),
    features,
  },
});

describe("createFeatureGateController", () => {
  it("follows the session's features claim for the active organization", () => {
    const auth = fakeAuth(LOADING);

    const controller = createFeatureGateController({
      auth,
      feature: "exports",
    });

    expect(controller.getSnapshot().allowed).toBeUndefined();
    const { view, unmount, renders } = mount(controller);
    auth.set(session("org-1", { "org-1": ["audit"] }));
    expect(view()).toMatchObject({ allowed: false, organizationId: "org-1" });
    auth.set(session("org-1", { "org-1": ["audit", "exports"] }));
    expect(view().allowed).toBe(true);
    const before = renders();
    view().recheck();
    expect(renders()).toBe(before);
    auth.set(SIGNED_OUT);
    expect(view()).toMatchObject({ allowed: false, organizationId: undefined });
    unmount();
    expect(auth.listeners()).toBe(0);
  });

  it("checks a given organization, a custom claim and short codes", () => {
    const auth = fakeAuth({
      status: "signed-in",
      user: { id: USER },
      claims: { sub: USER, plan: { "org-2": ["x"] }, org: "org-1" },
    });

    const given = createFeatureGateController({
      auth,
      feature: "exports",
      organizationId: "org-2",
      claim: { claim: "plan", keys: { exports: "x" } },
    });

    expect(given.getSnapshot()).toEqual({
      allowed: true,
      organizationId: "org-2",
    });

    const active = createFeatureGateController({
      auth,
      feature: "exports",
      claim: "plan",
      tenantClaim: "org",
    });

    expect(active.getSnapshot()).toEqual({
      allowed: false,
      organizationId: "org-1",
    });

    const outside = createFeatureGateController({
      auth: fakeAuth(session(undefined, {})),
      feature: "exports",
    });

    expect(outside.getSnapshot().allowed).toBe(false);
  });
});
