import { describe, expect, it, vi } from "vitest";

import type { SmartLaunchStore, SmartPending } from "../../src/fhir/smart.ts";

import {
  createSmartLaunch,
  fetchSmartConfiguration,
  pkceChallenge,
  smartLaunchStoreOf,
} from "../../src/fhir/smart.ts";

const ISS = "https://ehr.example/fhir";

const configuration = {
  authorization_endpoint: "https://ehr.example/auth",
  token_endpoint: "https://ehr.example/token",
  capabilities: ["launch-ehr", "context-ehr-patient"],
  code_challenge_methods_supported: ["S256"],
};

function memoryStore(): SmartLaunchStore {
  const map = new Map<string, SmartPending>();

  return {
    apiVersion: 1,
    save: async (state, pending) => {
      map.set(state, pending);
    },
    take: async (state) => {
      const value = map.get(state);

      map.delete(state);

      return value;
    },
  };
}

function fakeFetch(token: unknown = {}): typeof fetch {
  return vi.fn(async (input: RequestInfo | URL) =>
    String(input).endsWith("smart-configuration")
      ? Response.json(configuration)
      : Response.json(token),
  );
}

describe("SMART App Launch", () => {
  it("computes the RFC 7636 S256 challenge", async () => {
    expect(
      await pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
    ).toBe("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
  });

  it("reads the configuration and refuses a server without S256", async () => {
    const good = await fetchSmartConfiguration(ISS, fakeFetch());

    expect(good.ok && good.data.tokenEndpoint).toBe(
      configuration.token_endpoint,
    );

    const weak = await fetchSmartConfiguration(ISS, async () =>
      Response.json({
        ...configuration,
        code_challenge_methods_supported: ["plain"],
      }),
    );

    expect(!weak.ok && weak.error.hint).toBe("SMART_PKCE");
  });

  it("starts an EHR launch with PKCE and finishes it once", async () => {
    const launch = createSmartLaunch({
      clientId: "app",
      redirectUri: "https://app.example/cb",
      scope: "patient/Patient.rs openid",
      store: memoryStore(),
      allowedIssuers: [ISS],
      fetch: fakeFetch({
        access_token: "at",
        token_type: "Bearer",
        expires_in: 300,
        scope: "launch patient/Patient.rs",
        patient: "p-1",
        need_patient_banner: true,
      }),
    });

    const started = await launch.begin({ iss: ISS, launch: "xyz" });

    expect(started.ok).toBe(true);

    if (!started.ok) {
      return;
    }

    const url = new URL(started.data);

    expect(url.searchParams.get("aud")).toBe(ISS);
    expect(url.searchParams.get("launch")).toBe("xyz");
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
    expect(url.searchParams.get("scope")).toBe(
      "launch patient/Patient.rs openid",
    );

    const state = url.searchParams.get("state") ?? "";
    const done = await launch.complete({ code: "c", state });

    expect(done.ok && done.data.patient).toBe("p-1");
    expect(done.ok && done.data.needPatientBanner).toBe(true);
    expect(done.ok && done.data.scope).toEqual([
      "launch",
      "patient/Patient.rs",
    ]);

    const again = await launch.complete({ code: "c", state });

    expect(!again.ok && again.error.hint).toBe("SMART_STATE");
  });

  it("refuses an unknown issuer and an expired launch", async () => {
    let time = 1000;

    const launch = createSmartLaunch({
      clientId: "app",
      redirectUri: "https://app.example/cb",
      scope: "launch",
      store: memoryStore(),
      allowedIssuers: [ISS],
      fetch: fakeFetch(),
      now: () => time,
      ttlSeconds: 10,
    });

    const unknown = await launch.begin({ iss: "https://evil.example" });

    expect(!unknown.ok && unknown.error.hint).toBe("SMART_ISSUER");

    const started = await launch.begin({ iss: ISS });

    const state = started.ok
      ? (new URL(started.data).searchParams.get("state") ?? "")
      : "";

    time += 20_000;

    const late = await launch.complete({ code: "c", state });

    expect(!late.ok && late.error.hint).toBe("SMART_STATE");
  });

  it("rejects a store of another API version", () => {
    expect(() =>
      smartLaunchStoreOf({
        ...memoryStore(),
        apiVersion: 2,
      } as unknown as SmartLaunchStore),
    ).toThrow(/supports 1/);
  });
});
