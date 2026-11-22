import { describe, expect, it } from "vitest";

import type { ConnectEveOptions } from "../../src/eve/index.ts";

import { connectAuth } from "../../src/eve/index.ts";

function capture(): {
  connect: (options: ConnectEveOptions) => ConnectEveOptions;
} {
  return { connect: (options) => options };
}

describe("connectAuth", () => {
  const supabaseUrl = "https://abc.supabase.co/";

  it("hands connect the connector, the principal type and the pass-through options", () => {
    const { connect } = capture();

    const options = connectAuth(connect, {
      connector: "linear",
      supabaseUrl,
      principalType: "user",
      connect: { validate: true, tokenParams: { scopes: ["read"] } },
    });

    expect(options).toMatchObject({
      connector: "linear",
      principalType: "user",
      validate: true,
      tokenParams: { scopes: ["read"] },
    });
  });

  it("maps a user to the subject the credential provider uses", () => {
    const { connect } = capture();
    const options = connectAuth(connect, { connector: "linear", supabaseUrl });

    expect(
      options.createSubject(
        { type: "user", id: "u1", issuer: "https://other" },
        { url: "https://mcp.linear.app" },
      ),
    ).toEqual({
      type: "user",
      id: "u1",
      issuer: "https://abc.supabase.co/auth/v1",
    });
  });

  it("maps an app principal to the app subject", () => {
    const { connect } = capture();

    const options = connectAuth(connect, {
      connector: "linear",
      supabaseUrl,
      principalType: "app",
    });

    expect(options.createSubject({ type: "app" }, {})).toEqual({ type: "app" });
    expect(options.principalType).toBe("app");
  });

  it("returns what connect returns, so its members survive", () => {
    const definition = { getToken: () => "t", evict: () => "e" };

    expect(connectAuth(() => definition, { connector: "x", supabaseUrl })).toBe(
      definition,
    );
  });
});
