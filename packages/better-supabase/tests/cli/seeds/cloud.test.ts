import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  runSeedSample,
  sampleRequest,
} from "../../../src/cli/commands/seed-cloud.ts";
import {
  activeLogin,
  CloudError,
  readLogin,
  requestSample,
  saveLogin,
} from "../../../src/cli/seeds/cloud.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const reply = (status: number, body: unknown) => () =>
  Promise.resolve(Response.json(body, { status }));

const REQUEST = {
  variants: {},
  locale: "en",
  size: "m" as const,
  seed: 1,
  target: "demoOrg" as const,
};

describe("requestSample", () => {
  it("returns the statements of a 200", async () => {
    const body = { statements: ["select 1"], summary: "ok", estimatedRows: 1 };

    await expect(
      requestSample(reply(200, body), "https://c.test", "t", REQUEST),
    ).resolves.toEqual(body);
  });

  it("turns a 402 into an upgrade error with the url", async () => {
    const problem = {
      title: "Pro only",
      status: 402,
      upgrade: "https://c.test/up",
    };

    const error = await requestSample(
      reply(402, problem),
      "https://c.test",
      "t",
      REQUEST,
    ).catch((error_: unknown) => error_);

    expect(error).toBeInstanceOf(CloudError);
    expect(error).toMatchObject({
      kind: "upgrade",
      upgrade: "https://c.test/up",
    });
  });

  it("reports an unreachable cloud", async () => {
    const error = await requestSample(
      () => Promise.reject(new Error("down")),
      "https://c.test",
      "t",
      REQUEST,
    ).catch((error_: unknown) => error_);

    expect(error).toMatchObject({ kind: "network" });
  });
});

describe("sampleRequest", () => {
  const config = resolveConfig({}, "/app");

  it("needs a target", () => {
    expect(sampleRequest(config, {}, {})).toHaveProperty("error");
  });

  it("builds a demo org request from the config defaults", () => {
    expect(sampleRequest(config, { "demo-org": true }, {})).toMatchObject({
      target: "demoOrg",
      size: "m",
      seed: 1,
      locale: "en",
    });
  });

  it("rejects a bad size and both targets", () => {
    expect(
      sampleRequest(config, { "demo-org": true, size: "xl" }, {}),
    ).toHaveProperty("error");
    expect(
      sampleRequest(config, { "demo-org": true, tenant: "a" }, {}),
    ).toHaveProperty("error");
  });
});

describe("runSeedSample", () => {
  it("asks for a login when none is saved", async () => {
    const result = await runSeedSample(
      resolveConfig({}, "/app"),
      { "demo-org": true },
      { XDG_CONFIG_HOME: "/nonexistent-bsb" },
      { fetch: reply(200, {}), now: () => 0 },
      () => Promise.reject(new Error("no db")),
      undefined,
      () => {},
    );

    expect(result).toMatchObject({ code: 3, errorCode: "auth_required" });
  });
});

describe("activeLogin", () => {
  const GRANT = {
    status: "approved",
    accessToken: "new-access",
    refreshToken: "new-refresh",
    expiresAt: 4_000_000_000,
    email: "a@b.test",
  };

  const setup = async (expiresAt: number) => {
    const dir = await mkdtemp(join(tmpdir(), "bsb-login-"));
    const path = join(dir, "auth.json");

    await saveLogin(path, {
      status: "approved",
      accessToken: "old-access",
      refreshToken: "old-refresh",
      expiresAt,
      email: "a@b.test",
    });

    return path;
  };

  it("keeps a token that is still valid", async () => {
    const path = await setup(4_000_000_000);

    const login = await activeLogin(
      path,
      () => Promise.reject(new Error("must not be called")),
      "https://c.test",
      1000,
    );

    expect(login?.accessToken).toBe("old-access");
  });

  it("refreshes an expired token and saves the rotated grant", async () => {
    const path = await setup(10);
    let sent = "";

    const login = await activeLogin(
      path,
      (url, init) => {
        sent = `${url} ${String(init?.body)}`;

        return Promise.resolve(Response.json(GRANT));
      },
      "https://c.test",
      1_000_000,
    );

    expect(sent).toBe(
      'https://c.test/api/cli/auth/refresh {"refreshToken":"old-refresh"}',
    );
    expect(login?.accessToken).toBe("new-access");
    expect((await readLogin(path))?.refreshToken).toBe("new-refresh");
  });

  it("returns nothing when the cloud refuses the refresh token", async () => {
    const path = await setup(10);

    await expect(
      activeLogin(path, reply(401, {}), "https://c.test", 1_000_000),
    ).resolves.toBeUndefined();
  });
});
