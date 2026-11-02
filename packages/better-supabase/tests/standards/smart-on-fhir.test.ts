import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { createSmartLaunch } from "../../src/fhir/smart.ts";

describe(`SMART App Launch ${SPEC_PINS.smartAppLaunch}`, () => {
  it("discovers at .well-known/smart-configuration and sends aud, PKCE and launch", async () => {
    const seen: string[] = [];

    const launch = createSmartLaunch({
      clientId: "app",
      redirectUri: "https://app.example/cb",
      scope: "launch/patient openid fhirUser",
      allowedIssuers: ["https://ehr.example/fhir"],
      store: {
        apiVersion: 1,
        save: async () => {},
        take: async () => undefined,
      },
      fetch: async (input: RequestInfo | URL) => {
        seen.push(String(input));

        return Response.json({
          authorization_endpoint: "https://ehr.example/auth",
          token_endpoint: "https://ehr.example/token",
          code_challenge_methods_supported: ["S256"],
        });
      },
    });

    const result = await launch.begin({
      iss: "https://ehr.example/fhir",
      launch: "L",
    });

    expect(seen).toEqual([
      "https://ehr.example/fhir/.well-known/smart-configuration",
    ]);

    const url = new URL(result.ok ? result.data : "https://none.invalid");

    expect(url.searchParams.get("response_type")).toBe("code");
    expect(url.searchParams.get("aud")).toBe("https://ehr.example/fhir");
    expect(url.searchParams.get("launch")).toBe("L");
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
  });
});
