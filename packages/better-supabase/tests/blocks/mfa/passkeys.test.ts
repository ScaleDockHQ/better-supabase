import { describe, expect, it, vi } from "vitest";

import type { MfaApi, WebAuthnApi } from "../../../src/blocks/mfa/client.ts";

import {
  createMfaController,
  createStepUpController,
} from "../../../src/blocks/mfa/client.ts";
import { fakeAuth, flush, mount } from "../../fixtures/ports.ts";

const reply = <T>(data: T) => Promise.resolve({ data, error: null });

function passkeyMfa() {
  let level: "aal1" | "aal2" = "aal1";

  let factors = [{ id: "pk1", factor_type: "webauthn", status: "verified" }];

  const webauthn = {
    register: vi.fn(() => {
      factors = [
        ...factors,
        { id: "pk2", factor_type: "webauthn", status: "verified" },
      ];
      level = "aal2";

      return reply({});
    }),
    authenticate: vi.fn(() => {
      level = "aal2";

      return reply({});
    }),
  } satisfies WebAuthnApi;

  const api = {
    webauthn,
    listFactors: vi.fn(() => reply({ all: [...factors] })),
    getAuthenticatorAssuranceLevel: vi.fn(() =>
      reply({ currentLevel: level, nextLevel: "aal2" }),
    ),
    enroll: vi.fn(),
    challengeAndVerify: vi.fn(),
    unenroll: vi.fn(),
  } satisfies MfaApi;

  return api;
}

describe("passkeys in the MFA controller", () => {
  it("registers a passkey and reads aal2", async () => {
    const mfa = passkeyMfa();

    const { view, unmount } = mount(
      createMfaController({ mfa, auth: fakeAuth() }),
    );

    await flush();

    const result = await view().registerPasskey({
      name: "Laptop",
      rpId: "example.com",
      rpOrigins: ["https://example.com"],
    });

    expect(result.ok && result.data.level).toBe("aal2");
    expect(mfa.webauthn.register).toHaveBeenCalledWith({
      friendlyName: "Laptop",
      webauthn: { rpId: "example.com", rpOrigins: ["https://example.com"] },
    });
    expect(view().factors?.map((each) => each.type)).toEqual([
      "webauthn",
      "webauthn",
    ]);
    unmount();
  });

  it("reports unsupported when the client has no webauthn api", async () => {
    const { webauthn: _unused, ...mfa } = passkeyMfa();

    const { view, unmount } = mount(
      createMfaController({ mfa, auth: fakeAuth() }),
    );

    const result = await view().registerPasskey();

    expect(!result.ok && result.error.code).toBe("MFA_PASSKEYS_UNSUPPORTED");
    expect(view().error?.code).toBe("MFA_PASSKEYS_UNSUPPORTED");
    unmount();
  });
});

describe("passkeys in the step-up controller", () => {
  it("challenges the first webauthn factor", async () => {
    const mfa = passkeyMfa();

    const { view, unmount } = mount(
      createStepUpController({ mfa, auth: fakeAuth() }),
    );

    await flush();
    expect(view().satisfied).toBe(false);

    const result = await view().verifyPasskey();

    expect(result.ok).toBe(true);
    expect(mfa.webauthn.authenticate).toHaveBeenCalledWith({
      factorId: "pk1",
      webauthn: {},
    });
    expect(view().satisfied).toBe(true);
    unmount();
  });

  it("reports a missing passkey and an unsupported client", async () => {
    const none = { ...passkeyMfa(), listFactors: () => reply({ all: [] }) };

    const first = mount(
      createStepUpController({ mfa: none, auth: fakeAuth() }),
    );

    await flush();
    const missing = await first.view().verifyPasskey();
    expect(!missing.ok && missing.error.kind).toBe("invalid_input");
    first.unmount();

    const { webauthn: _unused, ...bare } = passkeyMfa();

    const second = mount(
      createStepUpController({ mfa: bare, auth: fakeAuth() }),
    );

    const unsupported = await second.view().verifyPasskey();
    expect(!unsupported.ok && unsupported.error.code).toBe(
      "MFA_PASSKEYS_UNSUPPORTED",
    );
    second.unmount();
  });
});
