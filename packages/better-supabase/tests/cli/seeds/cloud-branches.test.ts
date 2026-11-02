import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { Fetch } from "../../../src/cli/seeds/cloud.ts";

import {
  activeLogin,
  billingSummary,
  clearLogin,
  CloudError,
  pollLogin,
  readLogin,
  requestSample,
  saveLogin,
  startLogin,
  tokenPath,
} from "../../../src/cli/seeds/cloud.ts";

const BASE = "https://c.test";

const reply =
  (status: number, body: unknown): Fetch =>
  () =>
    Promise.resolve(Response.json(body, { status }));

const GRANT = {
  status: "approved" as const,
  accessToken: "a2",
  refreshToken: "r2",
  expiresAt: 4_000_000_000,
  email: "me@example.com",
};

const REQUEST = {
  variants: {},
  locale: "en",
  size: "m" as const,
  seed: 1,
  target: "demoOrg" as const,
};

async function failure(run: () => Promise<unknown>): Promise<CloudError> {
  const error = await run().catch((cause: unknown) => cause);

  expect(error).toBeInstanceOf(CloudError);

  // SAFETY: the expectation above checked the class.
  return error as CloudError;
}

async function tempPath(): Promise<string> {
  return join(await mkdtemp(join(tmpdir(), "bsb-cloud-")), "auth.json");
}

describe("tokenPath", () => {
  it("prefers XDG_CONFIG_HOME, then HOME, then the home directory", () => {
    expect(tokenPath({ XDG_CONFIG_HOME: "/x", HOME: "/h" })).toBe(
      "/x/better-supabase/auth.json",
    );
    expect(tokenPath({ XDG_CONFIG_HOME: "", HOME: "/h" })).toBe(
      "/h/.config/better-supabase/auth.json",
    );
    expect(tokenPath({ HOME: "/h" })).toBe(
      "/h/.config/better-supabase/auth.json",
    );
    expect(tokenPath({})).toMatch(/\.config\/better-supabase\/auth\.json$/);
  });
});

describe("saved login", () => {
  it("returns undefined for a missing file, bad JSON or a wrong shape", async () => {
    const path = await tempPath();

    await expect(readLogin(path)).resolves.toBeUndefined();
    await writeFile(path, "{bad");
    await expect(readLogin(path)).resolves.toBeUndefined();
    await writeFile(path, JSON.stringify({ accessToken: "a" }));
    await expect(readLogin(path)).resolves.toBeUndefined();
    await writeFile(path, "null");
    await expect(readLogin(path)).resolves.toBeUndefined();
  });

  it("saves, reads and clears a login", async () => {
    const path = await tempPath();

    await expect(clearLogin(path)).resolves.toBe(false);

    const stored = await saveLogin(path, GRANT);

    expect(stored).toEqual({
      accessToken: "a2",
      refreshToken: "r2",
      expiresAt: 4_000_000_000,
      email: "me@example.com",
    });
    await expect(readLogin(path)).resolves.toEqual(stored);
    await expect(readFile(path, "utf-8")).resolves.not.toContain("approved");
    await expect(clearLogin(path)).resolves.toBe(true);
    await expect(readLogin(path)).resolves.toBeUndefined();
  });
});

describe("CloudError", () => {
  it("keeps the status and upgrade url only when given", () => {
    const plain = new CloudError("network", "down");

    expect(plain).toMatchObject({ name: "CloudError", kind: "network" });
    expect(plain.status).toBeUndefined();
    expect(plain.upgrade).toBeUndefined();
    expect(
      new CloudError("upgrade", "pay", { status: 402, upgrade: "u" }),
    ).toMatchObject({ status: 402, upgrade: "u" });
  });
});

describe("requestSample failures", () => {
  it("falls back to the billing page and a default message on a bare 402", async () => {
    const error = await failure(() =>
      requestSample(reply(402, {}), BASE, "t", REQUEST),
    );

    expect(error.kind).toBe("upgrade");
    expect(error.upgrade).toBe(`${BASE}/billing`);
    expect(error.message).toBe("Sample data needs the Pro plan");
  });

  it("uses the detail, then the title, of an upgrade problem", async () => {
    const problem = { title: "Pro only", status: 402, upgrade: "u" };

    expect(
      (
        await failure(() =>
          requestSample(
            reply(402, { ...problem, detail: "Upgrade now" }),
            BASE,
            "t",
            REQUEST,
          ),
        )
      ).message,
    ).toBe("Upgrade now");
    expect(
      (
        await failure(() =>
          requestSample(reply(402, problem), BASE, "t", REQUEST),
        )
      ).message,
    ).toBe("Pro only");
  });

  it("reports a 401, a failed status and a body of the wrong shape", async () => {
    expect(
      (await failure(() => requestSample(reply(401, {}), BASE, "t", REQUEST)))
        .kind,
    ).toBe("unauthorized");
    expect(
      (await failure(() => requestSample(reply(500, {}), BASE, "t", REQUEST)))
        .message,
    ).toContain("status 500");
    expect(
      (await failure(() => requestSample(reply(200, {}), BASE, "t", REQUEST)))
        .kind,
    ).toBe("rejected");
  });

  it("names a network failure, with an error or a bare value", async () => {
    const error = await failure(() =>
      requestSample(
        () => Promise.reject(new Error("ECONNREFUSED")),
        BASE,
        "t",
        REQUEST,
      ),
    );

    expect(error.message).toBe("Could not reach https://c.test: ECONNREFUSED");

    const bare = await failure(() =>
      requestSample(() => Promise.reject("offline"), BASE, "t", REQUEST),
    );

    expect(bare.message).toBe("Could not reach https://c.test: offline");
  });

  it("treats a body that is not JSON as missing", async () => {
    const fetcher: Fetch = async () => ({
      ok: true,
      status: 200,
      json: () => Promise.reject(new Error("not json")),
      text: async () => "nope",
    });

    expect(
      (await failure(() => requestSample(fetcher, BASE, "t", REQUEST))).kind,
    ).toBe("rejected");
  });
});

describe("startLogin and pollLogin", () => {
  const start = {
    deviceCode: "d",
    userCode: "U-1",
    verificationUrl: "https://c.test/v",
    interval: 5,
    expiresIn: 600,
  };

  it("starts a login and rejects a bad start", async () => {
    await expect(startLogin(reply(200, start), BASE)).resolves.toEqual(start);
    expect(
      (await failure(() => startLogin(reply(500, {}), BASE))).message,
    ).toBe("The login could not start (status 500)");
    expect((await failure(() => startLogin(reply(200, {}), BASE))).kind).toBe(
      "rejected",
    );
  });

  it("returns the grant, or a pending, expired or rejected error", async () => {
    await expect(pollLogin(reply(200, GRANT), BASE, "d")).resolves.toEqual(
      GRANT,
    );
    expect(
      (await failure(() => pollLogin(reply(202, {}), BASE, "d"))).kind,
    ).toBe("pending");
    expect(
      (await failure(() => pollLogin(reply(200, {}), BASE, "d"))).kind,
    ).toBe("pending");
    expect(
      (await failure(() => pollLogin(reply(410, {}), BASE, "d"))).kind,
    ).toBe("expired");
    expect(
      (await failure(() => pollLogin(reply(400, {}), BASE, "d"))).kind,
    ).toBe("expired");
    expect(
      (await failure(() => pollLogin(reply(500, {}), BASE, "d"))).message,
    ).toBe("The login failed (status 500)");
  });
});

describe("activeLogin", () => {
  const NOW = 1_000_000;

  const expired = {
    accessToken: "old",
    refreshToken: "r1",
    expiresAt: NOW / 1000 - 10,
    email: "me@example.com",
  };

  it("returns undefined without a saved login", async () => {
    await expect(
      activeLogin(await tempPath(), reply(200, GRANT), BASE, NOW),
    ).resolves.toBeUndefined();
  });

  it("returns a login that has not expired without calling the cloud", async () => {
    const path = await tempPath();

    await saveLogin(path, { ...GRANT, expiresAt: NOW / 1000 + 3600 });

    const login = await activeLogin(
      path,
      () => Promise.reject(new Error("must not be called")),
      BASE,
      NOW,
    );

    expect(login?.accessToken).toBe("a2");
  });

  it("refreshes an expired login and saves the rotated tokens", async () => {
    const path = await tempPath();

    await writeFile(path, JSON.stringify(expired));

    const login = await activeLogin(path, reply(200, GRANT), BASE, NOW);

    expect(login).toEqual({
      accessToken: "a2",
      refreshToken: "r2",
      expiresAt: 4_000_000_000,
      email: "me@example.com",
    });
    await expect(readLogin(path)).resolves.toEqual(login);
  });

  it("gives up quietly when the cloud refuses the refresh", async () => {
    for (const status of [400, 401, 410, 500]) {
      const path = await tempPath();

      await writeFile(path, JSON.stringify(expired));
      await expect(
        activeLogin(path, reply(status, {}), BASE, NOW),
      ).resolves.toBeUndefined();
      await expect(readLogin(path)).resolves.toEqual(expired);
    }
  });

  it("throws when the cloud is unreachable", async () => {
    const path = await tempPath();

    await writeFile(path, JSON.stringify(expired));

    const error = await failure(() =>
      activeLogin(path, () => Promise.reject(new Error("down")), BASE, NOW),
    );

    expect(error.kind).toBe("network");
  });
});

describe("billingSummary", () => {
  it("returns the summary and sends the token", async () => {
    const seen: RequestInit[] = [];

    const fetcher: Fetch = async (_url, init) => {
      if (init) {
        seen.push(init);
      }

      return Response.json({ plan: "pro", email: "me@example.com" });
    };

    await expect(billingSummary(fetcher, BASE, "tok")).resolves.toEqual({
      plan: "pro",
      email: "me@example.com",
    });
    expect(seen[0]).toMatchObject({
      method: "GET",
      headers: { authorization: "Bearer tok" },
    });
  });

  it("reports a 401, a failed status and a bad body", async () => {
    expect(
      (await failure(() => billingSummary(reply(401, {}), BASE, "t"))).kind,
    ).toBe("unauthorized");
    expect(
      (await failure(() => billingSummary(reply(500, {}), BASE, "t"))).message,
    ).toBe("The account lookup failed (status 500)");
    expect(
      (await failure(() => billingSummary(reply(200, {}), BASE, "t"))).kind,
    ).toBe("rejected");
  });
});
