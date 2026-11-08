import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  cloudFailure,
  cloudUrl,
  runLogin,
  runLogout,
  runWhoami,
} from "../../../src/cli/commands/account.ts";
import {
  CloudError,
  readLogin,
  saveLogin,
  tokenPath,
} from "../../../src/cli/seeds/cloud.ts";

const START = {
  deviceCode: "dev",
  userCode: "ABCD",
  verificationUrl: "https://c.test/device",
  interval: 1,
  expiresIn: 10,
};

const GRANT = {
  status: "approved" as const,
  accessToken: "access",
  refreshToken: "refresh",
  expiresAt: 4_000_000_000,
  email: "a@b.test",
};

const answer = (status: number, body: unknown) =>
  Promise.resolve(Response.json(body, { status }));

async function home(): Promise<{ XDG_CONFIG_HOME: string }> {
  return { XDG_CONFIG_HOME: await mkdtemp(join(tmpdir(), "bsb-account-")) };
}

function tools(replies: (() => Promise<Response>)[], startAt = 0) {
  const clock = { now: startAt };

  const shown: string[] = [];
  const urls: string[] = [];

  return {
    shown,
    urls,
    tools: {
      fetch: (url: string) => {
        urls.push(url);
        const next = replies.shift();

        return next === undefined
          ? Promise.reject(new Error("no reply left"))
          : next();
      },
      sleep: (ms: number) => {
        clock.now += ms;

        return Promise.resolve();
      },
      now: () => clock.now,
      show: (text: string) => {
        shown.push(text);
      },
    },
  };
}

describe("cloudUrl", () => {
  it("defaults to the cloud app and trims a trailing slash", () => {
    expect(cloudUrl({})).toBe("https://app.bettersupabase.com");
    expect(cloudUrl({ BETTER_SUPABASE_CLOUD_URL: "https://c.test/" })).toBe(
      "https://c.test",
    );
  });
});

describe("runLogin", () => {
  it("shows the code, polls until approved and saves the login", async () => {
    const env = await home();

    const run = tools([
      () => answer(200, START),
      () => answer(202, { status: "pending" }),
      () => answer(200, GRANT),
    ]);

    const result = await runLogin(
      { ...env, BETTER_SUPABASE_CLOUD_URL: "https://c.test" },
      run.tools,
    );

    expect(result).toMatchObject({ code: 0, output: "Logged in as a@b.test." });
    expect(run.shown[0]).toContain("ABCD");
    expect(run.urls).toEqual([
      "https://c.test/api/cli/auth/start",
      "https://c.test/api/cli/auth/poll",
      "https://c.test/api/cli/auth/poll",
    ]);
    expect((await readLogin(tokenPath(env)))?.email).toBe("a@b.test");
  });

  it("fails when the login is not approved before it expires", async () => {
    const env = await home();

    const run = tools([
      () => answer(200, { ...START, expiresIn: 2 }),
      () => answer(202, {}),
      () => answer(202, {}),
      () => answer(202, {}),
    ]);

    await expect(runLogin(env, run.tools)).resolves.toMatchObject({
      code: 1,
      errorCode: "request_failed",
    });
  });

  it("reports a denied login", async () => {
    const run = tools([
      () => answer(200, START),
      () => answer(410, { status: "denied" }),
    ]);

    await expect(runLogin(await home(), run.tools)).resolves.toMatchObject({
      code: 1,
      errorCode: "request_failed",
    });
  });

  it("reports a cloud that cannot start the login", async () => {
    const run = tools([() => answer(500, {})]);

    await expect(runLogin(await home(), run.tools)).resolves.toMatchObject({
      code: 1,
      errorCode: "request_failed",
    });
  });
});

describe("cloudFailure", () => {
  it("maps each kind to a code", () => {
    expect(cloudFailure(new CloudError("network", "down"))).toMatchObject({
      code: 1,
      errorCode: "network_error",
    });
    expect(cloudFailure(new CloudError("unauthorized", "no"))).toMatchObject({
      code: 2,
      errorCode: "auth_required",
      next: [{ command: "better-supabase login" }],
    });
    expect(
      cloudFailure(
        new CloudError("upgrade", "Pro only", { upgrade: "https://c.test/up" }),
      ),
    ).toMatchObject({ code: 2, data: { upgrade: "https://c.test/up" } });
    expect(cloudFailure(new CloudError("upgrade", "Pro only"))).toMatchObject({
      error: expect.stringContaining("https://app.bettersupabase.com/billing"),
    });

    for (const kind of ["pending", "expired", "rejected"] as const) {
      expect(cloudFailure(new CloudError(kind, "x"))).toMatchObject({
        code: 1,
        errorCode: "request_failed",
      });
    }
  });

  it("rethrows an error that is not from the cloud", () => {
    expect(() => cloudFailure(new Error("bug"))).toThrow("bug");
  });
});

describe("runLogout", () => {
  it("removes the saved login, then says there was none", async () => {
    const env = await home();

    await saveLogin(tokenPath(env), GRANT);

    await expect(runLogout(env)).resolves.toMatchObject({
      output: "Logged out.",
    });
    await expect(runLogout(env)).resolves.toMatchObject({
      output: "You were not logged in.",
    });
  });
});

describe("runWhoami", () => {
  it("asks for a login when none is saved", async () => {
    await expect(
      runWhoami(await home(), () => answer(200, {}), 0),
    ).resolves.toMatchObject({ code: 2, errorCode: "auth_required" });
  });

  it("reports the account and its plan", async () => {
    const env = await home();

    await saveLogin(tokenPath(env), GRANT);

    await expect(
      runWhoami(env, () => answer(200, { plan: "pro" }), 1000),
    ).resolves.toMatchObject({
      code: 0,
      output: "a@b.test (pro plan)",
      data: { plan: "pro" },
    });
  });

  it("reports a rejected token and an unreachable cloud", async () => {
    const env = await home();

    await saveLogin(tokenPath(env), GRANT);

    await expect(
      runWhoami(env, () => answer(401, {}), 1000),
    ).resolves.toMatchObject({ code: 2 });
    await expect(
      runWhoami(env, () => Promise.reject(new Error("down")), 1000),
    ).resolves.toMatchObject({ code: 1, errorCode: "network_error" });
  });

  it("reports a cloud that cannot refresh an expired login", async () => {
    const env = await home();

    await saveLogin(tokenPath(env), { ...GRANT, expiresAt: 10 });

    await expect(
      runWhoami(env, () => Promise.reject(new Error("down")), 1_000_000),
    ).resolves.toMatchObject({ code: 1, errorCode: "network_error" });
    expect(
      await readFile(tokenPath(env), "utf-8").then((text) => text.length),
    ).toBeGreaterThan(0);
  });
});
