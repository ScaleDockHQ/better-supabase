import { mkdtemp } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { run } from "../../../src/cli/index.ts";

async function cloud(): Promise<{ url: string; close: () => Promise<void> }> {
  const server = createServer((request, response) => {
    response.setHeader("content-type", "application/json");

    if (request.url === "/api/cli/auth/start") {
      response.end(
        JSON.stringify({
          deviceCode: "dev",
          userCode: "ABCD",
          verificationUrl: "https://c.test/device",
          interval: 1,
          expiresIn: 30,
        }),
      );

      return;
    }

    response.end(
      JSON.stringify({
        status: "approved",
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: 4_000_000_000,
        email: "a@b.test",
      }),
    );
  });

  await new Promise<void>((done) => {
    server.listen(0, "127.0.0.1", done);
  });
  const address = server.address();

  if (address === null || typeof address === "string") {
    throw new Error("no port");
  }

  return {
    url: `http://127.0.0.1:${String(address.port)}`,
    close: () =>
      new Promise((done) => {
        server.close(() => {
          done();
        });
      }),
  };
}

describe("login, whoami and logout commands", () => {
  it("logs in over the device flow, then logs out", async () => {
    const server = await cloud();
    const dir = await mkdtemp(join(tmpdir(), "bsb-account-cli-"));
    const env = { XDG_CONFIG_HOME: dir, BETTER_SUPABASE_CLOUD_URL: server.url };

    try {
      const login = await run(["login", "--cwd", dir], { env });

      expect(login.code).toBe(0);
      expect(login.stdout).toContain("Logged in as a@b.test");

      const out = await run(["logout", "--cwd", dir], { env });

      expect(out.code).toBe(0);
    } finally {
      await server.close();
    }
  });

  it("asks for a login when whoami has none", async () => {
    const dir = await mkdtemp(join(tmpdir(), "bsb-account-cli-"));

    const result = await run(["whoami", "--cwd", dir], {
      env: { XDG_CONFIG_HOME: dir },
    });

    expect(result.code).toBe(2);
  });
});
