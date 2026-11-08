import { describe, expect, it, vi } from "vitest";

import { dbError } from "../../src/core/errors.ts";
import { adapterBase } from "../../src/server/adapter-base.ts";

type Server = Parameters<typeof adapterBase>[0];

function serverWith(pending: boolean): Server {
  // SAFETY: adapterBase reads only events.pending and events.settled().
  return { events: { pending, settled: () => Promise.resolve() } } as never;
}

describe("adapterBase", () => {
  it("defaults expose from the environment and honours exposeErrors", () => {
    expect(adapterBase(serverWith(false), { exposeErrors: true }).expose).toBe(
      true,
    );
    expect(adapterBase(serverWith(false), { exposeErrors: false }).expose).toBe(
      false,
    );
  });

  it("flushes pending sends to the option's waitUntil before the platform's", () => {
    const own = vi.fn<(promise: Promise<unknown>) => void>();
    const platform = vi.fn<(promise: Promise<unknown>) => void>();

    adapterBase(serverWith(true), { waitUntil: own }).flush(platform);

    expect(own).toHaveBeenCalledOnce();
    expect(platform).not.toHaveBeenCalled();
  });

  it("flushes to the platform's waitUntil without an option, and not when idle", () => {
    const platform = vi.fn<(promise: Promise<unknown>) => void>();

    adapterBase(serverWith(true)).flush(platform);
    adapterBase(serverWith(false)).flush(platform);

    expect(platform).toHaveBeenCalledOnce();
  });

  it("refuses with Problem Details at the request path", async () => {
    const response = adapterBase(serverWith(false), {
      exposeErrors: true,
    }).refuse(
      dbError("forbidden", "Not allowed"),
      new Request("https://app.test/api/notes"),
    );

    expect(response.status).toBe(403);
    expect(response.headers.get("content-type")).toContain("problem+json");
    expect(await response.json()).toMatchObject({
      instance: "/api/notes",
      detail: "Not allowed",
    });
  });
});
