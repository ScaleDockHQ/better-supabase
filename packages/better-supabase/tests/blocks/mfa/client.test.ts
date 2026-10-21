import { describe, expect, it, vi } from "vitest";

import type { MfaApi, RawMfaFactor } from "../../../src/blocks/mfa/client.ts";

import { checkAal } from "../../../src/auth/mfa.ts";
import {
  createMfaController,
  createStepUpController,
  needsStepUp,
} from "../../../src/blocks/mfa/client.ts";
import { dbError } from "../../../src/core/errors.ts";
import { fakeAuth, flush, mount } from "../../fixtures/ports.ts";

const reply = <T>(data: T) => Promise.resolve({ data, error: null });

function fakeMfa(verified = false) {
  let level: "aal1" | "aal2" = "aal1";

  const factors: RawMfaFactor[] = verified
    ? [{ id: "f0", factor_type: "totp", status: "verified" }]
    : [];

  const api = {
    listFactors: vi.fn(() => reply({ all: [...factors] })),
    getAuthenticatorAssuranceLevel: vi.fn(() =>
      reply({
        currentLevel: level,
        nextLevel: factors.some((each) => each.status === "verified")
          ? "aal2"
          : "aal1",
      }),
    ),
    enroll: vi.fn((params: { friendlyName?: string }) => {
      factors.push({
        id: "f1",
        factor_type: "totp",
        status: "unverified",
        ...(params.friendlyName ? { friendly_name: params.friendlyName } : {}),
      });

      return reply({
        id: "f1",
        totp: { qr_code: "data:qr", secret: "S3CRET", uri: "otpauth://x" },
      });
    }),
    challengeAndVerify: vi.fn((params: { factorId: string; code: string }) => {
      if (params.code !== "123456") {
        return Promise.resolve({
          data: null,
          error: {
            message: "Invalid TOTP code entered",
            status: 422,
            code: "mfa_verification_failed",
          },
        });
      }

      const factor = factors.find((each) => each.id === params.factorId);

      if (factor) {
        factors[factors.indexOf(factor)] = { ...factor, status: "verified" };
      }

      level = "aal2";

      return reply({});
    }),
    unenroll: vi.fn((params: { factorId: string }) => {
      factors.splice(
        factors.findIndex((each) => each.id === params.factorId),
        1,
      );

      return reply({ id: params.factorId });
    }),
  } satisfies MfaApi;

  return api;
}

describe("createMfaController", () => {
  it("enrols a TOTP factor, verifies it and reads aal2", async () => {
    const mfa = fakeMfa();

    const { view, unmount } = mount(
      createMfaController({ mfa, auth: fakeAuth(), issuer: "Acme" }),
    );

    await flush();
    expect(view().factors).toEqual([]);
    expect(view().level).toBe("aal1");

    const enrolled = await view().enroll({ name: "Phone" });
    expect(enrolled.ok && enrolled.data.qrCode).toBe("data:qr");
    expect(mfa.enroll).toHaveBeenCalledWith({
      factorType: "totp",
      friendlyName: "Phone",
      issuer: "Acme",
    });
    expect(view().enrollment?.secret).toBe("S3CRET");
    expect(view().factors).toEqual([
      { id: "f1", name: "Phone", type: "totp", verified: false },
    ]);

    const wrong = await view().verify("000000");
    expect(wrong.ok).toBe(false);
    expect(view().error).toMatchObject({
      kind: "invalid_input",
      code: "mfa_verification_failed",
    });
    expect(view().enrollment).toBeDefined();

    const verified = await view().verify("123456");
    expect(verified.ok && verified.data.level).toBe("aal2");
    expect(view().enrollment).toBeUndefined();
    expect(view().level).toBe("aal2");
    expect(view().factors?.[0]?.verified).toBe(true);
    unmount();
  });

  it("cancels an unconfirmed enrolment and unenrols factors", async () => {
    const mfa = fakeMfa(true);

    const { view, unmount } = mount(
      createMfaController({ mfa, auth: fakeAuth() }),
    );

    await flush();
    await view().enroll();
    await view().cancel();
    expect(mfa.unenroll).toHaveBeenCalledWith({ factorId: "f1" });
    expect(view().enrollment).toBeUndefined();
    const removed = await view().unenroll("f0");
    expect(removed.ok).toBe(true);
    expect(view().factors).toEqual([]);
    unmount();
  });

  it("refuses verify without an enrolment", async () => {
    const { view, unmount } = mount(
      createMfaController({ mfa: fakeMfa(), auth: fakeAuth() }),
    );

    const result = await view().verify("123456");
    expect(!result.ok && result.error.kind).toBe("invalid_input");
    unmount();
  });
});

describe("createStepUpController", () => {
  it("challenges the first verified factor and is satisfied at aal2", async () => {
    const mfa = fakeMfa(true);

    const { view, unmount } = mount(
      createStepUpController({ mfa, auth: fakeAuth() }),
    );

    await flush();
    expect(view().factors?.map((each) => each.id)).toEqual(["f0"]);
    expect(view().satisfied).toBe(false);
    expect(view().nextLevel).toBe("aal2");
    const result = await view().verify("123456");
    expect(result.ok).toBe(true);
    expect(mfa.challengeAndVerify).toHaveBeenCalledWith({
      factorId: "f0",
      code: "123456",
    });
    expect(view().satisfied).toBe(true);
    unmount();
  });

  it("reports a missing factor", async () => {
    const { view, unmount } = mount(
      createStepUpController({ mfa: fakeMfa(), auth: fakeAuth() }),
    );

    await flush();
    const result = await view().verify("123456");
    expect(result.ok).toBe(false);
    expect(view().error?.kind).toBe("invalid_input");
    unmount();
  });
});

describe("needsStepUp", () => {
  it("matches the INSUFFICIENT_AAL refusal of checkAal only", () => {
    expect(
      needsStepUp(checkAal({ kind: "user", claims: { aal: "aal1" } }, "aal2")),
    ).toBe(true);
    expect(needsStepUp(dbError("forbidden", "No"))).toBe(false);
    expect(needsStepUp(undefined)).toBe(false);
  });
});

describe("MFA read failures", () => {
  const failing = { message: "Auth is down", status: 503 };

  it("keeps the factors read error and clears it on dismiss", async () => {
    const mfa = fakeMfa();
    mfa.listFactors.mockResolvedValueOnce({
      data: null,
      error: failing,
    } as never);

    const { view, unmount } = mount(
      createMfaController({ mfa, auth: fakeAuth() }),
    );

    await flush();
    expect(view().error).toMatchObject({ message: "Auth is down" });
    view().dismiss();
    expect(view().error).toBeUndefined();
    await view().cancel();
    expect(mfa.unenroll).not.toHaveBeenCalled();
    unmount();
  });

  it("keeps the assurance read error", async () => {
    const mfa = fakeMfa();
    mfa.getAuthenticatorAssuranceLevel.mockResolvedValueOnce({
      data: null,
      error: failing,
    } as never);

    const { view, unmount } = mount(
      createMfaController({ mfa, auth: fakeAuth() }),
    );

    await flush();
    expect(view().error).toMatchObject({ message: "Auth is down" });
    unmount();
  });

  it("keeps the step-up read errors and clears them on dismiss", async () => {
    const mfa = fakeMfa(true);
    mfa.listFactors.mockResolvedValueOnce({
      data: null,
      error: failing,
    } as never);

    const { view, unmount } = mount(
      createStepUpController({ mfa, auth: fakeAuth() }),
    );

    await flush();
    expect(view().error).toMatchObject({ message: "Auth is down" });
    view().dismiss();
    expect(view().error).toBeUndefined();
    mfa.getAuthenticatorAssuranceLevel.mockResolvedValueOnce({
      data: null,
      error: failing,
    } as never);
    view().refresh();
    await flush();
    expect(view().error).toMatchObject({ message: "Auth is down" });
    unmount();
  });
});
