import type { AddressInfo } from "node:net";

import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { loadStackEnvCheck, ENV_RULES } from "../../../src/cli/doctor/env.ts";
import { PROCESS_ENV, parseEnv } from "../../../src/cli/env.ts";

const STATUS = {
  API_URL: "http://127.0.0.1:55021",
  PUBLISHABLE_KEY: "sb_publishable_stack",
  SECRET_KEY: "sb_secret_stack",
};

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "better-supabase-stack-env-"));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

async function fakeSupabase(script: string): Promise<string> {
  const bin = join(root, "fake-supabase");
  await writeFile(bin, `#!/bin/sh\n${script}\n`);
  await chmod(bin, 0o755);

  return bin;
}

const check = (stackEnv: DoctorContext["stackEnv"]) => {
  const rule = ENV_RULES.find((candidate) => candidate.code === "BS503")!;

  // SAFETY: BS503 reads only stackEnv from the context.
  return rule.check({ stackEnv } as DoctorContext);
};

describe("BS503", () => {
  it("names each stale variable with redacted values", async () => {
    const bin = await fakeSupabase(`echo '${JSON.stringify(STATUS)}'`);

    const stackEnv = await loadStackEnvCheck(
      root,
      parseEnv({
        SUPABASE_BIN: bin,
        SUPABASE_URL: "http://127.0.0.1:54321",
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_old",
        SUPABASE_SECRET_KEY: "sb_secret_stack",
      }),
    );

    const findings = await check(stackEnv);

    expect(findings.map((finding) => finding.target)).toEqual([
      "SUPABASE_URL",
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    ]);
    expect(findings[0]?.message).toContain(
      "SUPABASE_URL is exported as 127.0.0.1:54321, but the running stack has 127.0.0.1:55021.",
    );
    expect(JSON.stringify(findings)).not.toContain("sb_publishable_");
  });

  it("warns that exported inline keys override the running stack's JWKS URL", async () => {
    const bin = await fakeSupabase(`echo '${JSON.stringify(STATUS)}'`);
    const jwks = JSON.stringify({ keys: [{ kty: "EC", kid: "hosted" }] });

    const stackEnv = await loadStackEnvCheck(
      root,
      parseEnv({ SUPABASE_BIN: bin, SUPABASE_JWKS: jwks }),
    );

    const findings = await check(stackEnv);

    expect(findings.map((finding) => finding.target)).toEqual([
      "SUPABASE_JWKS",
    ]);
    expect(JSON.stringify(findings)).not.toContain("hosted");
  });

  it("accepts exported inline keys the running stack serves", async () => {
    const served = { keys: [{ kty: "EC", kid: "local" }] };

    const server = createServer((_request, response) => {
      response.end(JSON.stringify(served));
    });

    await new Promise<void>((done) => {
      server.listen(0, "127.0.0.1", done);
    });

    try {
      const { port } = server.address() as AddressInfo;
      const status = { ...STATUS, API_URL: `http://127.0.0.1:${port}` };
      const statusBin = await fakeSupabase(`echo '${JSON.stringify(status)}'`);

      const env = (jwks: unknown) =>
        parseEnv({
          SUPABASE_BIN: statusBin,
          SUPABASE_JWKS: JSON.stringify(jwks),
        });

      expect(await check(await loadStackEnvCheck(root, env(served)))).toEqual(
        [],
      );
      expect(
        (
          await check(
            await loadStackEnvCheck(
              root,
              env({ keys: [{ kty: "EC", kid: "hosted" }] }),
            ),
          )
        ).map((finding) => finding.target),
      ).toEqual(["SUPABASE_JWKS"]);
    } finally {
      server.close();
    }
  });

  it("never starts supabase status when no SUPABASE_* variable is exported", async () => {
    const bin = await fakeSupabase("exit 99");

    expect(
      await loadStackEnvCheck(
        root,
        parseEnv({ SUPABASE_BIN: bin, PATH: "/bin" }),
      ),
    ).toEqual({ skipped: "No SUPABASE_* variable is exported." });
    expect(await loadStackEnvCheck(root, {})).toMatchObject({
      skipped: expect.any(String),
    });
  });

  it("skips quietly when the stack is down or the CLI is missing", async () => {
    const down = await fakeSupabase("exit 1");

    const stopped = await loadStackEnvCheck(
      root,
      parseEnv({ SUPABASE_BIN: down, SUPABASE_URL: "http://127.0.0.1:54321" }),
    );

    expect(stopped).toEqual({ skipped: "The local stack is not running." });
    expect(await check(stopped)).toEqual([]);

    const missing = await loadStackEnvCheck(root, {
      SUPABASE_BIN: join(root, "nope"),
      [PROCESS_ENV]: { SUPABASE_URL: "http://127.0.0.1:54321" },
    });

    expect(missing).toMatchObject({
      skipped: expect.stringContaining("Supabase CLI"),
    });
  });
});

describe("BS506", () => {
  const checkUrls = (text: string) => {
    const rule = ENV_RULES.find((candidate) => candidate.code === "BS506")!;

    // SAFETY: BS506 reads only envFiles from the context.
    return rule.check({
      envFiles: [{ path: ".env.local", text }],
    } as unknown as DoctorContext);
  };

  it("warns when a browser URL differs from the server URL", async () => {
    const findings = await checkUrls(
      [
        "SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co",
        "NEXT_PUBLIC_SUPABASE_URL=https://auth.example.com",
        "SUPABASE_PUBLISHABLE_KEY=sb_publishable_x",
      ].join("\n"),
    );

    expect(findings).toEqual([
      {
        message:
          "NEXT_PUBLIC_SUPABASE_URL in .env.local (auth.example.com) differs from SUPABASE_URL (abcdefghijklmnopqrst.supabase.co). The server and the browser then read different session cookies. Use one URL, or set auth.cookie.name on both clients.",
        target: ".env.local:NEXT_PUBLIC_SUPABASE_URL",
        location: { file: ".env.local", line: 2 },
      },
    ]);
  });

  it("accepts the same URL in several spellings, with or without a slash", async () => {
    expect(
      await checkUrls(
        [
          "SUPABASE_URL=http://127.0.0.1:54321",
          'NEXT_PUBLIC_SUPABASE_URL="http://127.0.0.1:54321/"',
          "EXPO_PUBLIC_SUPABASE_URL=",
          "VITE_SUPABASE_URL=not a url",
        ].join("\n"),
      ),
    ).toEqual([]);
    expect(
      await checkUrls("SUPABASE_PUBLISHABLE_KEY=sb_publishable_x"),
    ).toEqual([]);
  });
});

describe("BS509", () => {
  const checkJwks = (text: string) => {
    const rule = ENV_RULES.find((candidate) => candidate.code === "BS509")!;

    // SAFETY: BS509 reads only envFiles from the context.
    return rule.check({
      envFiles: [{ path: ".env.local", text }],
    } as unknown as DoctorContext);
  };

  it("reports a SUPABASE_JWKS that loadEnv would reject", async () => {
    const findings = await checkJwks(
      ["SUPABASE_URL=http://127.0.0.1:54321", "SUPABASE_JWKS={keys:"].join(
        "\n",
      ),
    );

    expect(findings).toEqual([
      {
        message:
          'SUPABASE_JWKS in .env.local must be JSON: {"keys":[...]} or [...]. Fill it with the output of curl <url>/auth/v1/.well-known/jwks.json, or leave it empty to fetch SUPABASE_JWKS_URL.',
        target: ".env.local:SUPABASE_JWKS",
        location: { file: ".env.local", line: 2 },
      },
    ]);
    expect(
      (await checkJwks('SUPABASE_JWKS={"keys":[]}')).map(
        (finding) => finding.message,
      ),
    ).toEqual([
      expect.stringContaining("must hold at least one JSON Web Key with a kty"),
    ]);
  });

  it("accepts keys in either shape, and an empty value", async () => {
    const key = { kty: "EC", kid: "k1", crv: "P-256", x: "x", y: "y" };

    expect(
      await checkJwks(
        [
          `SUPABASE_JWKS='${JSON.stringify({ keys: [key] })}'`,
          `SUPABASE_JWKS=${JSON.stringify([key])}`,
          "SUPABASE_JWKS=",
        ].join("\n"),
      ),
    ).toEqual([]);
  });
});
