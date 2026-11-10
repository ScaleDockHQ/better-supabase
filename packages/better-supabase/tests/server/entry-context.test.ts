import { describe, expect, it, vi } from "vitest";

import type { ContextEntry } from "../../src/server/entry-context.ts";

import {
  CRON_KEY_NAME,
  cronHandler,
  entryContext,
} from "../../src/server/entry-context.ts";

function fakeServer() {
  const context = vi.fn((_request: Request, _options?: unknown) =>
    Promise.resolve({ from: "context" }),
  );

  const contextFromResolution = vi.fn(
    (_r: unknown, _q: Request, _o?: unknown) => ({ from: "resolution" }),
  );

  const contextFor = vi.fn((_auth: unknown, _o?: unknown) => ({
    from: "auth",
  }));

  // SAFETY: the test only calls the three context methods.
  const bsb = { context, contextFromResolution, contextFor } as never;

  return { bsb, context, contextFromResolution, contextFor };
}

const request = new Request("https://app.test/api/cron/digest");

describe("entryContext", () => {
  it("builds the context each entry kind names", async () => {
    const { bsb, context, contextFromResolution, contextFor } = fakeServer();

    const resolution = { auth: { kind: "none" } } as never;
    const auth = { kind: "none", reason: "no_token" } as never;

    expect(await entryContext(bsb, { kind: "request", request })).toEqual({
      from: "context",
    });

    expect(
      await entryContext(bsb, { kind: "resolution", resolution, request }),
    ).toEqual({ from: "resolution" });

    expect(await entryContext(bsb, { kind: "auth", auth })).toEqual({
      from: "auth",
    });

    expect(context).toHaveBeenCalledWith(request, undefined);
    expect(contextFromResolution).toHaveBeenCalledWith(
      resolution,
      request,
      undefined,
    );
    expect(contextFor).toHaveBeenCalledWith(auth, undefined);
  });

  it("runs a cron entry as the service role under a key name", async () => {
    const { bsb, contextFor } = fakeServer();

    await entryContext(bsb, { kind: "cron" });
    await entryContext(bsb, { kind: "cron", keyName: "nightly" });

    expect(contextFor.mock.calls.map(([auth]) => auth)).toEqual([
      { kind: "secret", keyName: CRON_KEY_NAME },
      { kind: "secret", keyName: "nightly" },
    ]);
  });

  it("refuses an unknown kind", async () => {
    const { bsb } = fakeServer();

    await expect(
      entryContext(bsb, { kind: "nope" } as unknown as ContextEntry),
    ).rejects.toThrow("Unknown context entry");
  });
});

describe("cronHandler", () => {
  const options = { name: "digest", secret: "s3cret" };

  it("needs a secret", () => {
    const { bsb } = fakeServer();

    expect(() =>
      cronHandler(bsb, { name: "digest", secret: undefined }, () => 1),
    ).toThrow("needs a secret");
  });

  it("answers 405 and 401 before it runs", async () => {
    const { bsb, contextFor } = fakeServer();
    const run = vi.fn();
    const route = cronHandler(bsb, options, run);

    expect((await route(new Request(request, { method: "PUT" }))).status).toBe(
      405,
    );
    expect((await route(request)).status).toBe(401);
    expect(run).not.toHaveBeenCalled();
    expect(contextFor).not.toHaveBeenCalled();
  });

  it("runs with a service context and sends the result as JSON", async () => {
    const { bsb } = fakeServer();

    const route = cronHandler(bsb, options, (ctx, req) => ({
      from: (ctx as unknown as { from: string }).from,
      path: new URL(req.url).pathname,
    }));

    const response = await route(
      new Request(request, { headers: { authorization: "Bearer s3cret" } }),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      from: "auth",
      path: "/api/cron/digest",
    });
  });

  it("answers { ok: true } for nothing and passes a Response through", async () => {
    const { bsb } = fakeServer();
    const headers = { authorization: "Bearer s3cret" };

    const empty = await cronHandler(
      bsb,
      options,
      () => undefined,
    )(new Request(request, { headers }));

    expect(await empty.json()).toEqual({ ok: true });

    const custom = await cronHandler(
      bsb,
      options,
      () => new Response(null, { status: 204 }),
    )(new Request(request, { headers }));

    expect(custom.status).toBe(204);
  });
});
