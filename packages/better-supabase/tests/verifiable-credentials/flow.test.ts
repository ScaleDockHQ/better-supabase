import { describe, expect, it } from "vitest";

import type { CredentialIssuer } from "../../src/verifiable-credentials/index.ts";

import { toBase64Url } from "../../src/core/base64.ts";
import { signCompact, importSigningKey } from "../../src/core/jws.ts";
import {
  PRE_AUTHORIZED_GRANT,
  PROOF_TYP,
  StatusList,
  createCredentialIssuer,
  createPresentationRequest,
  memoryIssuanceStore,
  passSource,
  presentSdJwt,
  qualificationSource,
  signStatusListToken,
  toResponse,
  verifyJwtVc,
  verifyPresentationResponse,
  courseCompletionSource,
} from "../../src/verifiable-credentials/index.ts";
import { testKey } from "./fixtures.ts";

const ISSUER = "https://issuer.example";
const VCT = "https://issuer.example/credentials/qualification";
const STATUS_URI = "https://issuer.example/status/1";

async function setup() {
  const issuerKey = await testKey("Ed25519");
  const holder = await testKey("ES256");
  let now = Temporal.Instant.from("2026-06-01T12:00:00Z");

  const qualification = qualificationSource({
    vct: VCT,
    validFor: Temporal.Duration.from({ hours: 24 * 30 }),
    lookup: (subject) =>
      Promise.resolve(
        subject === "qualification:q1"
          ? {
              holderName: "Ada",
              qualification: "First aid",
              issuedOn: "2026-05-01",
            }
          : undefined,
      ),
  });

  const store = memoryIssuanceStore(() => STATUS_URI);

  const issuer = createCredentialIssuer({
    issuer: ISSUER,
    signer: issuerKey.signer,
    sources: [
      qualification,
      {
        ...qualification,
        configuration: {
          id: "qualification-w3c",
          format: "jwt_vc_json",
          types: ["QualificationCredential"],
        },
      },
    ],
    store,
    endpoints: {
      token: `${ISSUER}/token`,
      credential: `${ISSUER}/credential`,
      nonce: `${ISSUER}/nonce`,
    },
    now: () => now,
  });

  return {
    issuerKey,
    holder,
    issuer,
    advance: (seconds: number) => {
      now = now.add({ seconds });
    },
    now: () => now,
  };
}

async function proof(
  holder: Awaited<ReturnType<typeof testKey>>,
  nonce: string,
  now: Temporal.Instant,
  aud = ISSUER,
) {
  return signCompact(
    await importSigningKey(holder.privateKey),
    "ES256",
    { typ: PROOF_TYP, alg: "ES256", jwk: holder.publicKey },
    { aud, iat: Math.floor(now.epochMilliseconds / 1000), nonce },
  );
}

async function run(
  issuer: CredentialIssuer,
  holder: Awaited<ReturnType<typeof testKey>>,
  now: Temporal.Instant,
  configurationId = "qualification",
  subject = "qualification:q1",
) {
  const { offer } = await issuer.createOffer({ configurationId, subject });

  // SAFETY: the offer is built by createOffer with this shape.
  const code = (
    offer["grants"] as Record<string, { "pre-authorized_code": string }>
  )[PRE_AUTHORIZED_GRANT]!["pre-authorized_code"];

  const token = await issuer.token({
    grant_type: PRE_AUTHORIZED_GRANT,
    "pre-authorized_code": code,
  });

  const accessToken = String(token.body["access_token"]);
  const nonce = String((await issuer.nonce()).body["c_nonce"]);

  return {
    token,
    accessToken,
    send: async (jwt?: string) =>
      issuer.credential(`Bearer ${accessToken}`, {
        credential_configuration_id: configurationId,
        proofs: { jwt: [jwt ?? (await proof(holder, nonce, now))] },
      }),
    nonce,
  };
}

describe("OpenID4VCI pre-authorized code flow", () => {
  it("publishes issuer and authorization server metadata", async () => {
    const { issuer } = await setup();
    const metadata = issuer.metadata();

    expect(metadata["credential_issuer"]).toBe(ISSUER);
    expect(metadata["nonce_endpoint"]).toBe(`${ISSUER}/nonce`);
    expect(
      (
        metadata["credential_configurations_supported"] as Record<
          string,
          { format: string; vct?: string }
        >
      )["qualification"],
    ).toMatchObject({ format: "dc+sd-jwt", vct: VCT });
    expect(
      issuer.authorizationServerMetadata()["grant_types_supported"],
    ).toEqual([PRE_AUTHORIZED_GRANT]);
  });

  it("issues an SD-JWT VC that a verifier accepts with a key binding", async () => {
    const { issuer, holder, issuerKey, now } = await setup();
    const flow = await run(issuer, holder, now());

    expect(flow.token.body["token_type"]).toBe("Bearer");

    const credential = await flow.send();

    expect(credential.status).toBe(200);

    const [first] = credential.body["credentials"] as { credential: string }[];

    const sdjwt = first!.credential;

    const created = createPresentationRequest({
      responseUri: "https://verifier.example/response",
      credentials: [
        { id: "q", vct: VCT, claims: ["qualification", "holder_name"] },
      ],
    });

    const presentation = await presentSdJwt(sdjwt, {
      reveal: ["holder_name"],
      keyBinding: {
        signer: holder.signer,
        audience: created.request.clientId,
        nonce: created.request.nonce,
        issuedAt: now(),
      },
    });

    const outcome = await verifyPresentationResponse(
      { vp_token: { q: [presentation] }, state: created.request.state },
      {
        request: created.request,
        issuers: (iss) => (iss === ISSUER ? issuerKey.jwks : undefined),
        now: now(),
      },
    );

    expect(outcome).toMatchObject({ ok: true });
    expect(outcome.ok && outcome.presentations[0]?.claims).toMatchObject({
      holder_name: "Ada",
      qualification: "First aid",
    });
    expect(created.uri.startsWith("openid4vp://authorize?")).toBe(true);
  });

  it("issues a W3C credential bound to the holder key", async () => {
    const { issuer, holder, issuerKey, now } = await setup();
    const flow = await run(issuer, holder, now(), "qualification-w3c");
    const sent = await flow.send();

    const [first] = sent.body["credentials"] as { credential: string }[];

    const credential = first!.credential;

    const verified = await verifyJwtVc(credential, {
      jwks: issuerKey.jwks,
      now: now(),
    });

    expect(verified.types).toEqual([
      "VerifiableCredential",
      "QualificationCredential",
    ]);
    expect(verified.issuer).toBe(ISSUER);
    expect(verified.subject["qualification"]).toBe("First aid");
    expect(String(verified.subject["id"]).startsWith("did:jwk:")).toBe(true);
    expect(verified.credential["credentialStatus"]).toMatchObject({
      type: "BitstringStatusListEntry",
      statusListIndex: "0",
    });
  });

  it("uses an offer and an access token once, and a nonce once", async () => {
    const { issuer, holder, now } = await setup();

    const { offer } = await issuer.createOffer({
      configurationId: "qualification",
      subject: "qualification:q1",
    });

    // SAFETY: shape built by createOffer.
    const code = (
      offer["grants"] as Record<string, { "pre-authorized_code": string }>
    )[PRE_AUTHORIZED_GRANT]!["pre-authorized_code"];

    const params = {
      grant_type: PRE_AUTHORIZED_GRANT,
      "pre-authorized_code": code,
    };

    expect((await issuer.token(params)).status).toBe(200);
    expect(await issuer.token(params)).toMatchObject({
      status: 400,
      body: { error: "invalid_grant" },
    });

    const flow = await run(issuer, holder, now());
    const first = await flow.send();

    expect(first.status).toBe(200);
    expect((await flow.send()).status).toBe(401);

    const again = await run(issuer, holder, now());
    const jwt = await proof(holder, again.nonce, now());

    expect((await again.send(jwt)).status).toBe(200);

    const third = await run(issuer, holder, now());

    // The nonce the first run used is spent.
    expect(
      await third.send(await proof(holder, again.nonce, now())),
    ).toMatchObject({ status: 400, body: { error: "invalid_nonce" } });
  });

  it("keeps the grant after a bad proof so the wallet can retry", async () => {
    const { issuer, holder, now } = await setup();
    const flow = await run(issuer, holder, now());

    const wrongAudience = await flow.send(
      await proof(holder, flow.nonce, now(), "https://other.example"),
    );

    expect(wrongAudience).toMatchObject({
      status: 400,
      body: { error: "invalid_proof" },
    });

    const fresh = String((await issuer.nonce()).body["c_nonce"]);

    expect((await flow.send(await proof(holder, fresh, now()))).status).toBe(
      200,
    );
  });

  it("checks the tx_code and burns the offer on a wrong one", async () => {
    const { issuer } = await setup();

    const created = await issuer.createOffer({
      configurationId: "qualification",
      subject: "qualification:q1",
      txCode: "4827",
    });

    // SAFETY: shape built by createOffer.
    const grant = (
      created.offer["grants"] as Record<
        string,
        { "pre-authorized_code": string; tx_code: unknown }
      >
    )[PRE_AUTHORIZED_GRANT]!;

    expect(grant.tx_code).toEqual({ input_mode: "numeric", length: 4 });

    const params = {
      grant_type: PRE_AUTHORIZED_GRANT,
      "pre-authorized_code": grant["pre-authorized_code"],
    };

    expect(await issuer.token({ ...params, tx_code: "0000" })).toMatchObject({
      body: { error: "invalid_grant" },
    });
    expect(await issuer.token({ ...params, tx_code: "4827" })).toMatchObject({
      body: { error: "invalid_grant" },
    });
  });

  it("refuses an expired offer, an unknown configuration and a missing token", async () => {
    const { issuer, advance } = await setup();

    const created = await issuer.createOffer({
      configurationId: "qualification",
      subject: "qualification:q1",
    });

    // SAFETY: shape built by createOffer.
    const code = (
      created.offer["grants"] as Record<
        string,
        { "pre-authorized_code": string }
      >
    )[PRE_AUTHORIZED_GRANT]!["pre-authorized_code"];

    advance(3600);
    expect(
      (
        await issuer.token({
          grant_type: PRE_AUTHORIZED_GRANT,
          "pre-authorized_code": code,
        })
      ).status,
    ).toBe(400);
    await expect(
      issuer.createOffer({ configurationId: "nope", subject: "x" }),
    ).rejects.toThrow("Unknown credential configuration");
    expect(await issuer.credential(undefined, {})).toMatchObject({
      status: 401,
    });
    expect(await issuer.credential("Bearer abc", {})).toMatchObject({
      body: { error: "unknown_credential_configuration" },
    });
    expect(await issuer.token({ grant_type: "password" })).toMatchObject({
      body: { error: "unsupported_grant_type" },
    });
  });

  it("stops issuing when the source no longer qualifies", async () => {
    const { issuer, holder, now } = await setup();

    const flow = await run(
      issuer,
      holder,
      now(),
      "qualification",
      "qualification:gone",
    );

    expect(await flow.send()).toMatchObject({
      status: 400,
      body: { error: "invalid_credential_request" },
    });
  });

  it("wraps results in a Response", async () => {
    const { issuer } = await setup();
    const response = toResponse(await issuer.nonce());

    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(typeof (await response.json()).c_nonce).toBe("string");
  });
});

describe("OpenID4VP verification", () => {
  async function issueOne() {
    const env = await setup();
    const flow = await run(env.issuer, env.holder, env.now());
    const sent = await flow.send();

    const [first] = sent.body["credentials"] as { credential: string }[];

    const credential = first!.credential;

    return { ...env, credential };
  }

  const query = { id: "q", vct: VCT, claims: ["holder_name"] };

  it("rejects a wrong state, a missing credential and an untrusted issuer", async () => {
    const { holder, issuerKey, credential, now } = await issueOne();

    const created = createPresentationRequest({
      responseUri: "https://v.example/r",
      credentials: [query],
    });

    const presentation = await presentSdJwt(credential, {
      reveal: ["holder_name"],
      keyBinding: {
        signer: holder.signer,
        audience: created.request.clientId,
        nonce: created.request.nonce,
        issuedAt: now(),
      },
    });

    const options = {
      request: created.request,
      issuers: () => issuerKey.jwks,
      now: now(),
    };

    expect(
      await verifyPresentationResponse(
        { vp_token: { q: [presentation] }, state: "x" },
        options,
      ),
    ).toMatchObject({ ok: false, code: "OPENID4VP_STATE" });
    expect(
      await verifyPresentationResponse(
        { vp_token: {}, state: created.request.state },
        options,
      ),
    ).toMatchObject({ code: "OPENID4VP_MISSING" });
    expect(
      await verifyPresentationResponse(
        { vp_token: { q: [presentation] }, state: created.request.state },
        { ...options, issuers: () => undefined },
      ),
    ).toMatchObject({ code: "OPENID4VP_ISSUER" });
    expect(
      await verifyPresentationResponse(
        {
          vp_token: JSON.stringify({ q: presentation }),
          state: created.request.state,
        },
        options,
      ),
    ).toMatchObject({ ok: true });
  });

  it("rejects a presentation missing a requested claim or replayed for another nonce", async () => {
    const { holder, issuerKey, credential, now } = await issueOne();

    const created = createPresentationRequest({
      responseUri: "https://v.example/r",
      credentials: [query],
    });

    const options = {
      request: created.request,
      issuers: () => issuerKey.jwks,
      now: now(),
    };

    const binding = {
      signer: holder.signer,
      audience: created.request.clientId,
      nonce: created.request.nonce,
      issuedAt: now(),
    };

    const hidden = await presentSdJwt(credential, {
      reveal: [],
      keyBinding: binding,
    });

    expect(
      await verifyPresentationResponse(
        { vp_token: { q: [hidden] }, state: created.request.state },
        options,
      ),
    ).toMatchObject({ code: "OPENID4VP_CLAIMS" });

    const replay = await presentSdJwt(credential, {
      reveal: ["holder_name"],
      keyBinding: { ...binding, nonce: "an-older-request" },
    });

    expect(
      await verifyPresentationResponse(
        { vp_token: { q: [replay] }, state: created.request.state },
        options,
      ),
    ).toMatchObject({ code: "SD_JWT_KEY_BINDING" });
  });

  it("rejects a revoked credential through its status list", async () => {
    const { holder, issuerKey, credential, now } = await issueOne();

    const created = createPresentationRequest({
      responseUri: "https://v.example/r",
      credentials: [query],
    });

    const presentation = await presentSdJwt(credential, {
      reveal: ["holder_name"],
      keyBinding: {
        signer: holder.signer,
        audience: created.request.clientId,
        nonce: created.request.nonce,
        issuedAt: now(),
      },
    });

    const serve = async (revoked: boolean) => {
      const list = StatusList.create(64);

      if (revoked) {
        list.set(0, 1);
      }

      const token = await signStatusListToken({
        signer: issuerKey.signer,
        uri: STATUS_URI,
        list,
        issuedAt: now(),
      });

      return verifyPresentationResponse(
        { vp_token: { q: [presentation] }, state: created.request.state },
        {
          request: created.request,
          issuers: () => issuerKey.jwks,
          now: now(),
          fetchStatusList: (uri) =>
            uri === STATUS_URI
              ? Promise.resolve(token)
              : Promise.reject(new Error("unknown list")),
        },
      );
    };

    expect(await serve(false)).toMatchObject({ ok: true });
    expect(await serve(true)).toMatchObject({
      ok: false,
      code: "OPENID4VP_REVOKED",
    });
  });
});

describe("credential sources", () => {
  it("maps course completions and passes to claims", async () => {
    const course = courseCompletionSource({
      vct: "https://x/course",
      lookup: () =>
        Promise.resolve({
          learnerName: "Ada",
          course: "Safety",
          completedOn: "2026-05-01",
          score: 92,
        }),
    });

    const pass = passSource({
      vct: "https://x/pass",
      lookup: () =>
        Promise.resolve({
          holderName: "Ada",
          event: "Conf",
          validUntil: "2026-07-01",
        }),
    });

    expect(await course.claims("course:1")).toEqual({
      learner_name: "Ada",
      course: "Safety",
      completed_on: "2026-05-01",
      score: 92,
    });
    expect(await pass.claims("pass:1")).toEqual({
      holder_name: "Ada",
      event: "Conf",
      valid_until: "2026-07-01",
    });
    expect(toBase64Url("x")).toBe("eA");
  });
});
