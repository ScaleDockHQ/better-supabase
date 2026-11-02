import { describe, expect, it } from "vitest";

import {
  ltiHasRole,
  ltiJwksOf,
  verifyLtiLaunch,
} from "../../../src/blocks/courses/lti.ts";
import { toBase64Url } from "../../../src/core/base64.ts";

const CLAIM = "https://purl.imsglobal.org/spec/lti/claim/";
const NOW = 1_800_000_000_000;

const pair = await crypto.subtle.generateKey(
  {
    name: "RSASSA-PKCS1-v1_5",
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256",
  },
  true,
  ["sign", "verify"],
);

const publicJwk = {
  ...(await crypto.subtle.exportKey("jwk", pair.publicKey)),
  kid: "k1",
  alg: "RS256",
};

const jwks = ltiJwksOf({ keys: [publicJwk] });

async function token(
  claims: Record<string, unknown>,
  header: Record<string, unknown> = {},
): Promise<string> {
  const head = toBase64Url(
    JSON.stringify({ alg: "RS256", typ: "JWT", kid: "k1", ...header }),
  );

  const body = toBase64Url(JSON.stringify(claims));

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    pair.privateKey,
    new TextEncoder().encode(`${head}.${body}`),
  );

  return `${head}.${body}.${toBase64Url(new Uint8Array(signature))}`;
}

const valid = {
  iss: "https://lms.example",
  aud: "client-1",
  sub: "user-9",
  exp: NOW / 1000 + 300,
  iat: NOW / 1000 - 5,
  nonce: "n-1",
  name: "Ada",
  [`${CLAIM}version`]: "1.3.0",
  [`${CLAIM}message_type`]: "LtiResourceLinkRequest",
  [`${CLAIM}deployment_id`]: "d-1",
  [`${CLAIM}target_link_uri`]: "https://tool.example/launch",
  [`${CLAIM}roles`]: [
    "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner",
  ],
  [`${CLAIM}resource_link`]: { id: "rl-1", title: "Week 1" },
  [`${CLAIM}context`]: { id: "c-1", title: "Algebra", type: ["CourseSection"] },
  [`${CLAIM}custom`]: { lesson: "3" },
};

const options = {
  jwks,
  issuer: "https://lms.example",
  clientId: "client-1",
  nonce: "n-1",
  now: NOW,
};

describe("verifyLtiLaunch", () => {
  it("reads a valid resource link launch", async () => {
    const result = await verifyLtiLaunch(await token(valid), options);

    expect(result.ok).toBe(true);

    const data = result.ok ? result.data : undefined;

    expect(data?.subject).toBe("user-9");
    expect(data?.resourceLink?.id).toBe("rl-1");
    expect(data?.context?.title).toBe("Algebra");
    expect(data?.custom).toEqual({ lesson: "3" });
    expect(ltiHasRole(data?.roles ?? [], "Learner")).toBe(true);
    expect(ltiHasRole(data?.roles ?? [], "Instructor")).toBe(false);
  });

  it.each([
    ["LTI_NONCE", { nonce: "other" }],
    ["LTI_ISSUER", { iss: "https://evil.example" }],
    ["LTI_AUDIENCE", { aud: "client-2" }],
    ["LTI_AUDIENCE", { aud: ["client-1", "client-2"] }],
    ["LTI_EXPIRED", { exp: NOW / 1000 - 600 }],
    ["LTI_ISSUED_AT", { iat: NOW / 1000 + 600, exp: NOW / 1000 + 900 }],
    ["LTI_LIFETIME", { exp: NOW / 1000 + 90_000 }],
    ["LTI_VERSION", { [`${CLAIM}version`]: "1.1.0" }],
    ["LTI_MESSAGE_TYPE", { [`${CLAIM}message_type`]: "LtiOther" }],
    ["LTI_DEPLOYMENT", { [`${CLAIM}deployment_id`]: "d-2" }],
    ["LTI_CLAIMS", { [`${CLAIM}resource_link`]: undefined }],
  ] as const)("refuses with %s", async (hint, change) => {
    const result = await verifyLtiLaunch(await token({ ...valid, ...change }), {
      ...options,
      deploymentIds: ["d-1"],
    });

    expect(result.ok).toBe(false);

    const error = result.ok ? undefined : result.error;

    expect(error?.kind).toBe("unauthorized");
    expect(error?.hint).toBe(hint);
  });

  it("accepts the right azp for several audiences", async () => {
    const result = await verifyLtiLaunch(
      await token({ ...valid, aud: ["client-1", "client-2"], azp: "client-1" }),
      options,
    );

    expect(result.ok).toBe(true);
  });

  it("refuses a bad signature and an HS256 downgrade", async () => {
    const good = await token(valid);
    const tampered = `${good.slice(0, -4)}AAAA`;
    const forged = await token(valid, { alg: "none" });

    for (const value of [tampered, forged]) {
      const result = await verifyLtiLaunch(value, options);

      expect(result.ok).toBe(false);

      expect(result.ok ? undefined : result.error.hint).toBe("LTI_SIGNATURE");
    }
  });

  it("needs deep linking settings for a deep linking launch", async () => {
    const result = await verifyLtiLaunch(
      await token({
        ...valid,
        [`${CLAIM}message_type`]: "LtiDeepLinkingRequest",
        [`${CLAIM}resource_link`]: undefined,
      }),
      options,
    );

    expect(result.ok).toBe(false);
  });
});
