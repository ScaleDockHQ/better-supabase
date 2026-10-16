import { describe, expect, it, vi } from "vitest";

import type { OAuthApi } from "../../../src/blocks/sessions/client.ts";

import {
  createOAuthConsentController,
  createOAuthGrantsController,
} from "../../../src/blocks/sessions/client.ts";
import { fakeAuth, flush, mount } from "../../fixtures/ports.ts";

const reply = <T>(data: T) => Promise.resolve({ data, error: null });
const CLIENT = { id: "c1", name: "Claude", uri: "", logo_uri: "" };

function fakeOAuth(details: "consent" | "approved" = "consent") {
  const grants = [
    { client: CLIENT, scopes: ["openid"], granted_at: "2026-10-01T00:00:00Z" },
    {
      client: { ...CLIENT, id: "c2", name: "Cursor" },
      scopes: ["openid", "email"],
      granted_at: "2026-10-02T00:00:00Z",
    },
  ];
  return {
    getAuthorizationDetails: vi.fn((id: string) =>
      details === "approved"
        ? reply({ redirect_url: "https://client.example/cb?code=old" })
        : reply({
            authorization_id: id,
            redirect_uri: "https://client.example/cb",
            client: CLIENT,
            user: { id: "u1", email: "u@example.com" },
            scope: "openid email",
          }),
    ),
    approveAuthorization: vi.fn(() =>
      reply({ redirect_url: "https://client.example/cb?code=new" }),
    ),
    denyAuthorization: vi.fn(() =>
      Promise.resolve({
        data: null,
        error: { message: "authorization expired", status: 400 },
      }),
    ),
    listGrants: vi.fn(() => reply([...grants])),
    revokeGrant: vi.fn((options: { clientId: string }) => {
      grants.splice(
        grants.findIndex((each) => each.client.id === options.clientId),
        1,
      );
      return reply({});
    }),
  } satisfies OAuthApi;
}

describe("createOAuthConsentController", () => {
  it("reads the request and approves through the redirect_url Auth returns", async () => {
    const oauth = fakeOAuth();
    const redirect = vi.fn();
    const { view, unmount } = mount(
      createOAuthConsentController({
        oauth,
        auth: fakeAuth(),
        authorizationId: "a1",
        redirect,
      }),
    );
    await flush();
    expect(view().request).toMatchObject({
      authorizationId: "a1",
      client: { id: "c1", name: "Claude", uri: undefined },
      scopes: ["openid", "email"],
      redirectHost: "client.example",
    });
    const approving = view().approve();
    expect(view().deciding).toBe("approve");
    expect(await approving).toEqual({
      ok: true,
      data: "https://client.example/cb?code=new",
      error: null,
    });
    expect(oauth.approveAuthorization).toHaveBeenCalledWith("a1", {
      skipBrowserRedirect: true,
    });
    expect(redirect).toHaveBeenCalledWith("https://client.example/cb?code=new");
    expect(view().deciding).toBe("approve");
    unmount();
  });

  it("keeps the request and the error when a decision fails", async () => {
    const { view, unmount } = mount(
      createOAuthConsentController({
        oauth: fakeOAuth(),
        auth: fakeAuth(),
        authorizationId: "a2",
        redirect: vi.fn(),
      }),
    );
    await flush();
    const denied = await view().deny();
    expect(denied.ok).toBe(false);
    expect(view().deciding).toBeUndefined();
    expect(view().error?.kind).toBe("invalid_input");
    expect(view().request).toBeDefined();
    unmount();
  });

  it("redirects at once for an approved client and shares the read per id", async () => {
    const oauth = fakeOAuth("approved");
    const redirect = vi.fn();
    const options = {
      oauth,
      auth: fakeAuth(),
      authorizationId: "a3",
      redirect,
    };
    const first = mount(createOAuthConsentController(options));
    const second = mount(createOAuthConsentController(options));
    await flush();
    expect(oauth.getAuthorizationDetails).toHaveBeenCalledTimes(1);
    expect(redirect).toHaveBeenCalledWith("https://client.example/cb?code=old");
    expect(first.view().redirectUrl).toBe("https://client.example/cb?code=old");
    first.unmount();
    second.unmount();
  });
});

describe("createOAuthGrantsController", () => {
  it("lists grants newest first and revokes one", async () => {
    const oauth = fakeOAuth();
    const { view, unmount } = mount(
      createOAuthGrantsController({ oauth, auth: fakeAuth() }),
    );
    await flush();
    expect(view().grants?.map((each) => each.client.id)).toEqual(["c2", "c1"]);
    expect(view().grants?.[0]?.grantedAt.toString()).toBe(
      "2026-10-02T00:00:00Z",
    );
    const revoked = await view().revoke("c2");
    expect(revoked.ok).toBe(true);
    expect(view().grants?.map((each) => each.client.id)).toEqual(["c1"]);
    expect(view().revoking).toEqual([]);
    unmount();
  });
});
