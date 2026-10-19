import { subscribe, unsubscribe } from "node:diagnostics_channel";
import { describe, expect, it } from "vitest";

import type { HttpEvent } from "../../../src/cli/core/trace.ts";

import { CliError } from "../../../src/cli/core/errors.ts";
import { request, USER_AGENT } from "../../../src/cli/core/http.ts";
import { HTTP_CHANNEL } from "../../../src/cli/core/trace.ts";
import { VERSION } from "../../../src/cli/version.ts";
import { fakeFetch } from "../fixtures/fake-fetch.ts";

const URL = "https://api.supabase.com/v1/projects/abc";

describe("request", () => {
  it("sends the user agent and returns the body", async () => {
    const api = fakeFetch(() => ({ text: "ok" }));

    expect(
      await request(URL, {
        what: "Reading",
        headers: { authorization: "Bearer sbp_x" },
        fetch: api.fetch,
      }),
    ).toBe("ok");
    expect(USER_AGENT).toBe(`better-supabase/${VERSION}`);
    expect(api.calls[0]?.headers.get("user-agent")).toBe(USER_AGENT);
    expect(api.calls[0]?.headers.get("authorization")).toBe("Bearer sbp_x");
  });

  it.each([
    [401, "auth_required"],
    [403, "auth_required"],
    [500, "request_failed"],
  ])("maps status %i to %s", async (status, code) => {
    const api = fakeFetch(() => ({ status, text: "nope" }));

    await expect(
      request(URL, { what: "Reading", fetch: api.fetch }),
    ).rejects.toMatchObject({
      code,
      message: `Reading failed (${status}): nope`,
    });
  });

  it("reports no response as network_error, naming the host", async () => {
    const api = fakeFetch(() => {
      throw new TypeError("fetch failed");
    });

    const error: unknown = await request(URL, {
      what: "Reading",
      fetch: api.fetch,
    }).catch((cause: unknown) => cause);

    expect(error).toBeInstanceOf(CliError);
    expect(error).toMatchObject({
      code: "network_error",
      message: "Reading got no response from api.supabase.com: fetch failed",
    });
  });

  it("reports a timeout as network_error", async () => {
    const hang: typeof fetch = (_input, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          reject(init.signal?.reason);
        });
      });

    await expect(
      request(URL, { what: "Reading", fetch: hang, timeoutMs: 10 }),
    ).rejects.toMatchObject({
      code: "network_error",
      message: expect.stringContaining("timed out"),
    });
  });

  it("rethrows when the run's signal aborts", async () => {
    const controller = new AbortController();
    const reason = new Error("interrupted");

    const hang: typeof fetch = (_input, init) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          reject(init.signal?.reason);
        });
      });

    const pending = request(URL, {
      what: "Reading",
      fetch: hang,
      signal: controller.signal,
    });

    controller.abort(reason);

    await expect(pending).rejects.toBe(reason);
  });

  it("publishes each request without credentials in the URL", async () => {
    const events: HttpEvent[] = [];

    const listener = (message: unknown): void => {
      // SAFETY: http.ts publishes only HttpEvent objects on this channel.
      events.push(message as HttpEvent);
    };

    subscribe(HTTP_CHANNEL, listener);

    try {
      await request("https://user:secret@example.com/x", {
        what: "Reading",
        method: "POST",
        fetch: fakeFetch(() => ({ text: "" })).fetch,
      });
    } finally {
      unsubscribe(HTTP_CHANNEL, listener);
    }

    expect(events).toEqual([
      {
        method: "POST",
        url: "https://user:redacted@example.com/x",
        status: 200,
        milliseconds: expect.any(Number),
      },
    ]);
  });
});
