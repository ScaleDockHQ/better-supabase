import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { createOAuthServer } from "../../src/blocks/oauth-server/oauth-server.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const INVALID = { status: "invalid" };

const recording = (answer: unknown = INVALID) => {
  const call = vi.fn<BlockTransport["call"]>(async () => answer);

  return { call, transport: { call } satisfies BlockTransport };
};

describe(`PKCE (RFC 7636, ${SPEC_PINS.rfc7636})`, () => {
  it("sends S256 of the verifier from Appendix B", async () => {
    const { call, transport } = recording();
    const oauth = createOAuthServer({ transport });

    await oauth.redeemAuthorizationCode({
      code: "code",
      clientId: "client",
      codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
    });

    expect(call.mock.calls[0]?.[2]).toMatchObject({
      code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
    });
  });

  it("refuses the plain method and a verifier outside section 4.1", async () => {
    const { call, transport } = recording();
    const oauth = createOAuthServer({ transport });

    const plain = await oauth.createAuthorizationCode({
      clientId: "client",
      userId: "user",
      codeChallenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
      codeChallengeMethod: "plain",
    });

    expect(plain).toMatchObject({
      ok: false,
      error: { hint: "OAUTH_PKCE_INVALID" },
    });

    const short = await oauth.redeemAuthorizationCode({
      code: "code",
      clientId: "client",
      codeVerifier: "too-short",
    });

    expect(short).toMatchObject({ ok: true, data: null });
    expect(call).not.toHaveBeenCalled();
  });
});

describe(`Client registration (RFC 7591, ${SPEC_PINS.rfc7591}; RFC 9700, ${SPEC_PINS.rfc9700})`, () => {
  it("stores hashes, never the issued secret or registration token", async () => {
    const { call, transport } = recording({
      clientId: "x",
      name: null,
      redirectUris: ["https://app.example.com/cb"],
      grantTypes: ["authorization_code"],
      tokenEndpointAuthMethod: "client_secret_basic",
      scope: null,
      metadata: {},
      createdBy: null,
      createdAt: "2026-10-18T00:00:00Z",
      updatedAt: "2026-10-18T00:00:00Z",
    });

    const oauth = createOAuthServer({ transport });

    const registered = await oauth
      .registerClient({ redirectUris: ["https://app.example.com/cb"] })
      .orThrow();

    const args = call.mock.calls[0]?.[2] ?? {};

    expect(registered.clientSecret).toBeTypeOf("string");
    expect(Object.values(args)).not.toContain(registered.clientSecret);
    expect(Object.values(args)).not.toContain(
      registered.registrationAccessToken,
    );
    expect(args["secret_hash"]).toMatch(/^[0-9a-f]{64}$/);
  });

  it.each([
    "http://app.example.com/cb",
    "https://app.example.com/cb#frag",
    "data:text/html,hi",
    "vbscript:msgbox",
    "/relative",
  ])("refuses the redirect URI %s (RFC 9700 section 2.1)", async (uri) => {
    const { call, transport } = recording();
    const oauth = createOAuthServer({ transport });

    expect(await oauth.registerClient({ redirectUris: [uri] })).toMatchObject({
      ok: false,
      error: { hint: "OAUTH_REDIRECT_URI_INVALID" },
    });
    expect(call).not.toHaveBeenCalled();
  });

  it("allows http on a loopback host (RFC 8252 section 7.3)", async () => {
    const { call, transport } = recording(null);
    const oauth = createOAuthServer({ transport });

    await oauth.updateClient("client", {
      redirectUris: ["http://127.0.0.1:8976/cb"],
    });

    expect(call).toHaveBeenCalledOnce();
  });
});

describe(`Device authorization (RFC 8628, ${SPEC_PINS.rfc8628})`, () => {
  it("issues an eight-consonant user code and the section 3.2 fields", async () => {
    const { call, transport } = recording(true);
    const oauth = createOAuthServer({ transport });

    const issued = await oauth
      .createDeviceCode("client", "contacts:read")
      .orThrow();

    expect(issued.userCode).toMatch(
      /^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$/,
    );
    expect(issued).toMatchObject({ expiresIn: 600, interval: 5 });
    expect(call.mock.calls[0]?.[2]).toMatchObject({
      user_code: issued.userCode.replace("-", ""),
    });
  });

  it.each([
    [
      { status: "authorization_pending", interval: 5 },
      { status: "authorization_pending", interval: 5 },
    ],
    [
      { status: "slow_down", interval: 10 },
      { status: "slow_down", interval: 10 },
    ],
    [{ status: "access_denied" }, { status: "access_denied" }],
    [{ status: "expired_token" }, { status: "expired_token" }],
  ])("maps the section 3.5 response %o", async (answer, expected) => {
    const { transport } = recording(answer);
    const oauth = createOAuthServer({ transport });

    expect(await oauth.pollDeviceCode("device", "client").orThrow()).toEqual(
      expected,
    );
  });

  it("matches a user code typed with a dash and in lower case", async () => {
    const { call, transport } = recording(true);
    const oauth = createOAuthServer({ transport });

    await oauth.approveDeviceCode("bdfg-hjkl", "user");

    expect(call.mock.calls[0]?.[2]).toMatchObject({ user_code: "BDFGHJKL" });
  });
});
