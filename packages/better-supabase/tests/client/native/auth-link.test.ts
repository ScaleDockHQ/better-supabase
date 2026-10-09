import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, expectTypeOf, it } from "vitest";

import type {
  AuthFailure,
  AuthLinkClient,
  OAuthClient,
  WebBrowserLike,
} from "../../../src/client/native/auth-link.ts";

import {
  handleAuthDeepLink,
  linkParams,
  signInWithOAuthBrowser,
} from "../../../src/client/native/auth-link.ts";

function fakeAuth(error: AuthFailure | null = null) {
  const calls: unknown[] = [];
  const reply = () => Promise.resolve({ error });
  const client = {
    auth: {
      exchangeCodeForSession: (code: string) => {
        calls.push(["code", code]);
        return reply();
      },
      setSession: (tokens: unknown) => {
        calls.push(["tokens", tokens]);
        return reply();
      },
      verifyOtp: (params: unknown) => {
        calls.push(["otp", params]);
        return reply();
      },
      signInWithOAuth: (credentials: unknown) => {
        calls.push(["oauth", credentials]);
        return Promise.resolve({
          data: { url: "https://auth.example/authorize" },
          error: null,
        });
      },
    },
  } satisfies OAuthClient;
  return { client, calls };
}

describe("linkParams", () => {
  it("reads the query and the fragment, decoding both", () => {
    const params = linkParams(
      "app://cb?code=a%20b&x=1+2#access_token=t&bad=%E0&flag",
    );
    expect(params.get("code")).toBe("a b");
    expect(params.get("x")).toBe("1 2");
    expect(params.get("access_token")).toBe("t");
    expect(params.get("flag")).toBe("");
    expect(params.has("bad")).toBe(false);
    expect(linkParams("app://cb").size).toBe(0);
  });
});

describe("handleAuthDeepLink", () => {
  it("exchanges a code, sets tokens and verifies a token hash", async () => {
    const fake = fakeAuth();
    expect(await handleAuthDeepLink(fake.client, "app://cb?code=abc")).toEqual({
      type: "signed-in",
      via: "code",
    });
    expect(
      await handleAuthDeepLink(
        fake.client,
        "app://cb#access_token=a&refresh_token=r",
      ),
    ).toEqual({ type: "signed-in", via: "tokens" });
    expect(
      await handleAuthDeepLink(
        fake.client,
        "app://cb?token_hash=h&type=magiclink",
      ),
    ).toEqual({ type: "signed-in", via: "otp" });
    expect(fake.calls).toEqual([
      ["code", "abc"],
      ["tokens", { access_token: "a", refresh_token: "r" }],
      ["otp", { token_hash: "h", type: "magiclink" }],
    ]);
  });

  it("returns none for other links and errors the link or the server reports", async () => {
    const fake = fakeAuth({ message: "expired", code: "otp_expired" });
    expect(await handleAuthDeepLink(fake.client, "app://home?tab=1")).toEqual({
      type: "none",
    });
    expect(
      await handleAuthDeepLink(fake.client, "app://cb?token_hash=h&type=nope"),
    ).toEqual({ type: "none" });
    expect(
      await handleAuthDeepLink(
        fake.client,
        "app://cb#error=access_denied&error_code=otp_expired&error_description=Link+expired",
      ),
    ).toEqual({
      type: "error",
      error: { message: "Link expired", code: "otp_expired" },
    });
    expect(await handleAuthDeepLink(fake.client, "app://cb?code=abc")).toEqual({
      type: "error",
      error: { message: "expired", code: "otp_expired" },
    });
  });

  it("accepts a real supabase-js client", () => {
    const asLink = (client: SupabaseClient): AuthLinkClient => client;
    const asOAuth = (client: SupabaseClient): OAuthClient => client;
    expectTypeOf(asLink).returns.toEqualTypeOf<AuthLinkClient>();
    expectTypeOf(asOAuth).returns.toEqualTypeOf<OAuthClient>();
  });
});

describe("signInWithOAuthBrowser", () => {
  it("opens the auth session and finishes from the redirect", async () => {
    const fake = fakeAuth();
    const opened: unknown[] = [];
    const browser: WebBrowserLike = {
      openAuthSessionAsync: (url, redirect) => {
        opened.push([url, redirect]);
        return Promise.resolve({ type: "success", url: "app://cb?code=xyz" });
      },
    };
    const result = await signInWithOAuthBrowser(
      fake.client,
      browser,
      "github",
      {
        redirectTo: "app://cb",
        scopes: "repo",
        queryParams: { prompt: "consent" },
      },
    );
    expect(result).toEqual({ type: "signed-in", via: "code" });
    expect(opened).toEqual([["https://auth.example/authorize", "app://cb"]]);
    expect(fake.calls[0]).toEqual([
      "oauth",
      {
        provider: "github",
        options: {
          redirectTo: "app://cb",
          skipBrowserRedirect: true,
          scopes: "repo",
          queryParams: { prompt: "consent" },
        },
      },
    ]);
  });

  it("returns none when the browser is dismissed and an error without a URL", async () => {
    const fake = fakeAuth();
    const dismissed: WebBrowserLike = {
      openAuthSessionAsync: () => Promise.resolve({ type: "dismiss" }),
    };
    expect(
      await signInWithOAuthBrowser(fake.client, dismissed, "github", {
        redirectTo: "app://cb",
      }),
    ).toEqual({ type: "none" });
    const noUrl: OAuthClient = {
      auth: {
        ...fake.client.auth,
        signInWithOAuth: () =>
          Promise.resolve({ data: { url: null }, error: null }),
      },
    };
    expect(
      await signInWithOAuthBrowser(noUrl, dismissed, "github", {
        redirectTo: "app://cb",
      }),
    ).toMatchObject({ type: "error" });
    const failing: OAuthClient = {
      auth: {
        ...fake.client.auth,
        signInWithOAuth: () =>
          Promise.resolve({
            data: { url: null },
            error: { message: "bad provider" },
          }),
      },
    };
    expect(
      await signInWithOAuthBrowser(failing, dismissed, "github", {
        redirectTo: "app://cb",
      }),
    ).toEqual({ type: "error", error: { message: "bad provider" } });
  });
});
