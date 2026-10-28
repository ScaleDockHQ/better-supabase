import { describe, expect, it, vi } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { createClients, lazyClient } from "../../src/server/clients.ts";

const URL_PRIMARY = "http://localhost:54321";

const env = () => ({ url: URL_PRIMARY, publishableKey: "pk", secretKey: "sk" });

const user = (token: string): AuthState => ({
  kind: "user",
  token,
  claims: { sub: "u", role: "authenticated" },
  user: { id: "u", role: "authenticated" },
  source: "bearer",
  expiresAt: null,
});

function build(overrides: Record<string, unknown> = {}) {
  const fetch = vi.fn<typeof globalThis.fetch>(async () => Response.json([]));

  const clients = createClients({
    options: { fetch },
    // SAFETY: the test environment has the keys the clients read.
    env: env as never,
    definitionExecutor: {},
    lite: undefined,
    ...overrides,
  });

  const sent = (index: number): Request => {
    const [input, init] = fetch.mock.calls[index]!;

    return new Request(input, init);
  };

  return { clients, fetch, sent };
}

describe("createClients", () => {
  it("shares one lazy admin client for the primary URL", async () => {
    const { clients, fetch, sent } = build();
    const admin = clients.contextClient({ kind: "secret", keyName: "default" });
    expect(admin).toBe(
      clients.contextClient({ kind: "secret", keyName: "default" }),
    );
    expect(fetch).not.toHaveBeenCalled();
    await admin.from("items").select("id");
    expect(sent(0).headers.get("apikey")).toBe("sk");
    expect(sent(0).headers.get("authorization")).toBe("Bearer sk");
  });

  it("builds a context client per user with the token on REST and Realtime", async () => {
    const { clients, sent } = build();
    const first = clients.contextClient(user("a"), { "x-request-id": "r1" });
    expect(first).not.toBe(clients.contextClient(user("a")));
    await first.from("items").select("id");
    expect(sent(0).headers.get("authorization")).toBe("Bearer a");
    expect(sent(0).headers.get("apikey")).toBe("pk");
    expect(sent(0).headers.get("x-request-id")).toBe("r1");
    expect(await first.realtime.accessToken?.()).toBe("a");
  });

  it("shares the anon client for the primary only", async () => {
    const { clients, sent } = build();
    const anon: AuthState = { kind: "none", reason: "none" };
    expect(clients.contextClient(anon)).toBe(clients.contextClient(anon));
    const other = clients.restAt("http://replica:54321", anon);
    expect(other).not.toBe(clients.contextClient(anon));
    await clients.contextClient(anon).from("items").select("id");
    expect(sent(0).headers.get("authorization")).toBe("Bearer pk");
  });

  it("refuses clients for API keys", () => {
    const { clients } = build();
    expect(() =>
      clients.restAt("http://x", { kind: "apiKey" } as never),
    ).toThrow(/API key/);
    expect(() => clients.contextClient({ kind: "apiKey" } as never)).toThrow(
      /API key/,
    );
  });

  it("checks the secret key when the admin client is asked for", () => {
    const { clients } = build({
      // SAFETY: an environment without a secret key.
      env: () => ({ url: URL_PRIMARY, publishableKey: "pk" }),
    });

    expect(() => clients.serviceClient()).toThrow(/SUPABASE_SECRET_KEY/);
  });

  it("needs a tuned executor only when db options are given", () => {
    expect(build().clients.tunedExecutor).toBe(false);
    expect(
      build({ options: { db: { timeout: 5 } } }).clients.tunedExecutor,
    ).toBe(true);
  });
});

describe("lazyClient", () => {
  class Counter {
    #count = 0;
    label = "counter";

    increment(): number {
      this.#count += 1;

      return this.#count;
    }
  }

  it("builds once, on first use, and binds methods to the instance", () => {
    const build = vi.fn(() => new Counter());
    const client = lazyClient(build);
    expect(build).not.toHaveBeenCalled();
    const increment = client.increment.bind(undefined);
    expect(increment()).toBe(1);
    expect(client.increment()).toBe(2);
    expect(build).toHaveBeenCalledOnce();
  });

  it("forwards writes, checks, prototypes and keys", () => {
    const client = lazyClient(() => new Counter());
    client.label = "renamed";
    expect(client.label).toBe("renamed");
    expect("increment" in client).toBe(true);
    expect(client).toBeInstanceOf(Counter);
    expect(Object.keys(client)).toEqual(["label"]);
    expect(Object.getOwnPropertyDescriptor(client, "label")?.value).toBe(
      "renamed",
    );
  });
});
