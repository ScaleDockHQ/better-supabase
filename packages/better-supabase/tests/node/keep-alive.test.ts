import type { Server } from "node:http";

import { createServer } from "node:http";
import { describe, expect, it, vi } from "vitest";

import type { UndiciModule } from "../../src/node/keep-alive.ts";

import { keepAliveFetch } from "../../src/node/keep-alive.ts";

function fakeUndici() {
  const agents: unknown[] = [];

  const fetchSpy = vi.fn(
    async (_input: unknown, _init: unknown) => new Response("pooled"),
  );

  function Agent(this: unknown, options: unknown): void {
    agents.push(options);
  }

  const module: UndiciModule = {
    // SAFETY: the mock is only ever called with `new`.
    Agent: Agent as unknown as UndiciModule["Agent"],
    fetch: fetchSpy,
  };

  return { agents, fetchSpy, module };
}

describe("keepAliveFetch", () => {
  it("sends requests through one undici Agent with the pool options", async () => {
    const { agents, fetchSpy, module } = fakeUndici();

    const fetcher = keepAliveFetch({
      connections: 32,
      pipelining: 4,
      load: async () => module,
    });

    expect(await (await fetcher("https://x.test/a")).text()).toBe("pooled");
    await fetcher("https://x.test/b", { method: "POST" });

    expect(agents).toEqual([{ connections: 32, pipelining: 4 }]);
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    expect(fetchSpy.mock.calls[1]?.[1]).toMatchObject({ method: "POST" });
    expect(fetchSpy.mock.calls[0]?.[1]).toHaveProperty("dispatcher");
  });

  it("calls the fallback fetch when undici is not installed", async () => {
    const fallback = vi.fn(async () => new Response("global"));
    const fetcher = keepAliveFetch({ load: async () => undefined, fallback });

    expect(await (await fetcher("https://x.test/")).text()).toBe("global");
    expect(fallback).toHaveBeenCalledOnce();
  });

  it("loads the real undici peer", async () => {
    const real = keepAliveFetch({ connections: 2 });

    const server = await new Promise<Server>((resolve) => {
      const s = createServer((_req, res) => res.end("ok"));
      s.listen(0, "127.0.0.1", () => {
        resolve(s);
      });
    });

    const address = server.address();
    const port = typeof address === "object" && address ? address.port : 0;

    try {
      const response = await real(`http://127.0.0.1:${port}/`);

      expect(await response.text()).toBe("ok");
    } finally {
      server.close();
      server.closeAllConnections();
    }
  });
});
