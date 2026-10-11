import { describe, expect, it, vi } from "vitest";

import { createClients } from "../../src/server/clients.ts";

const env = () => ({
  url: "http://localhost:54321",
  publishableKey: "pk",
  secretKey: "sk",
});

function build(overrides: Record<string, unknown> = {}) {
  const createClient = vi.fn(() => ({ id: Math.random() }));
  const clients = createClients({
    options: {},
    // SAFETY: the test environment has the keys the clients read.
    env: env as never,
    definitionExecutor: {},
    lite: undefined,
    // SAFETY: a stub that returns an opaque client.
    createClient: createClient as never,
    ...overrides,
  });
  return { clients, createClient };
}

describe("createClients", () => {
  it("shares one service client for the primary URL", () => {
    const { clients, createClient } = build();
    expect(clients.supabaseFor({ kind: "service", keyName: "secret" })).toBe(
      clients.supabaseFor({ kind: "service", keyName: "secret" }),
    );
    expect(createClient).toHaveBeenCalledTimes(1);
  });

  it("builds a user client per call", () => {
    const { clients, createClient } = build();
    clients.supabaseFor({ kind: "user", token: "a" } as never);
    clients.supabaseFor({ kind: "user", token: "b" } as never);
    expect(createClient).toHaveBeenCalledTimes(2);
  });

  it("refuses clients for API keys", () => {
    const { clients } = build();
    expect(() =>
      clients.restAt("http://x", { kind: "apiKey" } as never),
    ).toThrow(/API key/);
  });

  it("needs a tuned executor only when db options are given", () => {
    expect(build().clients.tunedExecutor).toBe(false);
    expect(
      build({ options: { db: { timeout: 5 } } }).clients.tunedExecutor,
    ).toBe(true);
  });
});
