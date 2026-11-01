import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import {
  PRE_AUTHORIZED_GRANT,
  PROOF_TYP,
  createPresentationRequest,
  dcqlQuery,
} from "../../src/verifiable-credentials/index.ts";

describe("OpenID4VCI 1.0 and OpenID4VP 1.0", () => {
  it("pins the versions", () => {
    expect(SPEC_PINS.openid4vci).toBe("1.0");
    expect(SPEC_PINS.openid4vp).toBe("1.0");
  });

  it("names the pre-authorized grant and the proof type as the spec does", () => {
    expect(PRE_AUTHORIZED_GRANT).toBe(
      "urn:ietf:params:oauth:grant-type:pre-authorized_code",
    );
    expect(PROOF_TYP).toBe("openid4vci-proof+jwt");
  });

  it("writes a DCQL query for dc+sd-jwt with vct_values and claim paths", () => {
    expect(
      dcqlQuery([{ id: "q", vct: "https://x/v", claims: ["a", "b"] }]),
    ).toEqual({
      credentials: [
        {
          id: "q",
          format: "dc+sd-jwt",
          meta: { vct_values: ["https://x/v"] },
          claims: [{ path: ["a"] }, { path: ["b"] }],
        },
      ],
    });
  });

  it("asks for a vp_token with direct_post and the redirect_uri client prefix", () => {
    const { params, request } = createPresentationRequest({
      responseUri: "https://v.example/r",
      credentials: [{ id: "q", vct: "v", claims: [] }],
    });

    expect(params).toMatchObject({
      client_id: "redirect_uri:https://v.example/r",
      response_type: "vp_token",
      response_mode: "direct_post",
      response_uri: "https://v.example/r",
    });
    expect(request.nonce).not.toBe(request.state);
  });
});
