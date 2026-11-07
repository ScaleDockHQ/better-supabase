import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { ConsentRequest } from "../../../src/cli/core/agent.ts";

import {
  runSeedDefaults,
  runSeedSample,
  sampleRequest,
} from "../../../src/cli/commands/seed-cloud.ts";
import { saveLogin, tokenPath } from "../../../src/cli/seeds/cloud.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { seedDefaultsFunctions } from "../../../src/sql/index.ts";
import { fakeConnect } from "../fixtures/fake-connect.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";

const LOCAL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const REMOTE = "postgresql://u:secret@db.example.com:5432/app";

const GRANT = {
  status: "approved" as const,
  accessToken: "access",
  refreshToken: "refresh",
  expiresAt: 4_000_000_000,
  email: "a@b.test",
};

const SAMPLE = {
  statements: ["insert into a values (1)", "insert into b values (2)"],
  summary: "Two rows",
  estimatedRows: 2,
};

const answer = (status: number, body: unknown) =>
  Promise.resolve(Response.json(body, { status }));

describe("seed --defaults and --sample", () => {
  let root: string;
  let env: { XDG_CONFIG_HOME: string };

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-seed-cloud-"));
    env = { XDG_CONFIG_HOME: join(root, "xdg") };
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const withDefaults = () =>
    resolveConfig({ blocks: ["organizations", "leave"] }, root);

  const consents: ConsentRequest[] = [];

  const consent = (request: ConsentRequest): void => {
    consents.push(request);
  };

  describe("runSeedDefaults", () => {
    it("says so when no block declares defaults", async () => {
      const result = await runSeedDefaults(
        resolveConfig({ blocks: ["organizations"] }, root),
        {},
        env,
        fakeConnect(fakeSql().pg).connect,
        LOCAL,
        consent,
      );

      expect(result).toMatchObject({
        code: 0,
        data: { modules: [], applied: false },
      });
    });

    it("refuses an unknown variant and a malformed one", async () => {
      const open = fakeConnect(fakeSql().pg).connect;

      await expect(
        runSeedDefaults(
          withDefaults(),
          { variant: "oops" },
          env,
          open,
          LOCAL,
          consent,
        ),
      ).resolves.toMatchObject({ code: 1, errorCode: "invalid_input" });
      await expect(
        runSeedDefaults(
          withDefaults(),
          { variant: "tags=x" },
          env,
          open,
          LOCAL,
          consent,
        ),
      ).resolves.toMatchObject({
        code: 1,
        error: expect.stringContaining("declares no tenant defaults"),
      });
      await expect(
        runSeedDefaults(
          withDefaults(),
          { variant: "leave=nope" },
          env,
          open,
          LOCAL,
          consent,
        ),
      ).resolves.toMatchObject({
        code: 1,
        error: expect.stringContaining("knows"),
      });
    });

    it("needs the organizations block", async () => {
      const result = await runSeedDefaults(
        resolveConfig({ blocks: ["leave"] }, root),
        {},
        env,
        fakeConnect(fakeSql().pg).connect,
        LOCAL,
        consent,
      );

      expect(result).toMatchObject({ code: 1, errorCode: "invalid_input" });
    });

    it("plans without touching the database on a dry run", async () => {
      const result = await runSeedDefaults(
        withDefaults(),
        { "dry-run": true, tenant: "acme", locale: "nl" },
        env,
        fakeConnect(fakeSql().pg).connect,
        LOCAL,
        consent,
      );

      expect(result).toMatchObject({
        code: 0,
        data: { applied: false, locale: "nl" },
      });
      expect(result).toHaveProperty("output", expect.stringContaining("acme"));
    });

    it("seeds every organization in one transaction", async () => {
      const fake = fakeSql([
        [
          "select",
          [
            { id: "o1", slug: "acme", name: "Acme" },
            { id: "o2", slug: null, name: null },
          ],
        ],
      ]);

      const open = fakeConnect(fake.pg);

      const result = await runSeedDefaults(
        withDefaults(),
        { check: false },
        env,
        open.connect,
        LOCAL,
        consent,
      );

      const functions = seedDefaultsFunctions(withDefaults());

      expect(result).toMatchObject({
        code: 0,
        data: { applied: true, tenants: ["acme", "o2"] },
      });
      expect(fake.texts()).toContain("begin");
      expect(fake.texts()).toContain("commit");
      expect(
        fake
          .texts()
          .filter((text) => text.startsWith("select ") && text.includes("$3")),
      ).toHaveLength(2 * functions.length);
      expect(open.closed()).toBe(1);
    });

    it("reports an organization that does not exist", async () => {
      const result = await runSeedDefaults(
        withDefaults(),
        { tenant: "ghost" },
        env,
        fakeConnect(fakeSql().pg).connect,
        LOCAL,
        consent,
      );

      expect(result).toMatchObject({ code: 1, errorCode: "not_found" });

      const none = await runSeedDefaults(
        withDefaults(),
        {},
        env,
        fakeConnect(fakeSql().pg).connect,
        LOCAL,
        consent,
      );

      expect(none).toMatchObject({ code: 1, errorCode: "not_found" });
    });

    it("rolls back when a function fails and asks for consent off the local stack", async () => {
      consents.length = 0;

      const fake = fakeSql([
        ["from", [{ id: "o1", slug: "acme", name: "Acme" }]],
        [
          (call) => call.text.startsWith("select ") && call.text.includes("$3"),
          { throws: new Error("boom") },
        ],
      ]);

      await expect(
        runSeedDefaults(
          withDefaults(),
          {},
          env,
          fakeConnect(fake.pg).connect,
          REMOTE,
          consent,
        ),
      ).rejects.toThrow("boom");
      expect(fake.texts()).toContain("rollback");
      expect(consents).toHaveLength(1);
    });
  });

  describe("sampleRequest", () => {
    const config = resolveConfig({}, "/app");

    it("rejects a seed that is not a whole number", () => {
      expect(
        sampleRequest(config, { "demo-org": true, seed: "1.5" }, {}),
      ).toHaveProperty("error");
    });

    it("builds a tenant request with the preset and instances", () => {
      expect(
        sampleRequest(
          resolveConfig({ blocks: ["organizations"] }, "/app"),
          { tenant: "acme", size: "s", seed: "7", locale: "nl" },
          { leave: "nl" },
        ),
      ).toMatchObject({
        target: "tenant",
        tenant: "acme",
        size: "s",
        seed: 7,
        locale: "nl",
        variants: { leave: "nl" },
      });
    });
  });

  describe("runSeedSample", () => {
    const tools = (reply: () => Promise<Response>) => ({
      fetch: reply,
      now: () => 1000,
    });

    async function login(): Promise<void> {
      await saveLogin(tokenPath(env), GRANT);
    }

    it("rejects a bad variant and a bad request before any call", async () => {
      const open = fakeConnect(fakeSql().pg).connect;

      await expect(
        runSeedSample(
          withDefaults(),
          { variant: "x" },
          env,
          tools(() => answer(200, SAMPLE)),
          open,
          LOCAL,
          consent,
        ),
      ).resolves.toMatchObject({ code: 1, errorCode: "invalid_input" });
      await expect(
        runSeedSample(
          withDefaults(),
          {},
          env,
          tools(() => answer(200, SAMPLE)),
          open,
          LOCAL,
          consent,
        ),
      ).resolves.toMatchObject({ code: 1, errorCode: "invalid_input" });
    });

    it("reports a refresh that fails on the network", async () => {
      await saveLogin(tokenPath(env), { ...GRANT, expiresAt: 1 });

      const result = await runSeedSample(
        withDefaults(),
        { "demo-org": true },
        env,
        tools(() => Promise.reject(new Error("down"))),
        fakeConnect(fakeSql().pg).connect,
        LOCAL,
        consent,
      );

      expect(result).toMatchObject({ code: 1, errorCode: "network_error" });
    });

    it("names the upgrade page on a 402", async () => {
      await login();

      const result = await runSeedSample(
        withDefaults(),
        { "demo-org": true },
        env,
        tools(() =>
          answer(402, {
            title: "Pro only",
            status: 402,
            upgrade: "https://c.test/up",
          }),
        ),
        fakeConnect(fakeSql().pg).connect,
        LOCAL,
        consent,
      );

      expect(result).toMatchObject({
        code: 2,
        data: { upgrade: "https://c.test/up" },
      });
    });

    it("writes the statements to --out", async () => {
      await login();

      const result = await runSeedSample(
        withDefaults(),
        { "demo-org": true, out: "supabase/sample.sql" },
        env,
        tools(() => answer(200, SAMPLE)),
        fakeConnect(fakeSql().pg).connect,
        LOCAL,
        consent,
      );

      expect(result).toMatchObject({
        code: 0,
        data: { applied: false, statements: 2 },
      });
      expect(
        await readFile(join(root, "supabase/sample.sql"), "utf-8"),
      ).toContain("insert into b values (2)");
    });

    it("plans on a dry run and applies in a transaction otherwise", async () => {
      await login();

      const dry = await runSeedSample(
        withDefaults(),
        { "demo-org": true, "dry-run": true },
        env,
        tools(() => answer(200, SAMPLE)),
        fakeConnect(fakeSql().pg).connect,
        LOCAL,
        consent,
      );

      expect(dry).toMatchObject({ code: 0, data: { applied: false } });

      const fake = fakeSql();

      const applied = await runSeedSample(
        withDefaults(),
        { tenant: "acme" },
        env,
        tools(() => answer(200, SAMPLE)),
        fakeConnect(fake.pg).connect,
        LOCAL,
        consent,
      );

      expect(applied).toMatchObject({ code: 0, data: { applied: true } });
      expect(fake.texts()).toEqual([
        "begin",
        "insert into a values (1)",
        "insert into b values (2)",
        "commit",
      ]);
    });

    it("rolls back a failing statement and asks for consent off the local stack", async () => {
      await login();
      consents.length = 0;

      const fake = fakeSql([
        ["insert into b", { throws: new Error("bad row") }],
      ]);

      await expect(
        runSeedSample(
          withDefaults(),
          { tenant: "acme" },
          env,
          tools(() => answer(200, SAMPLE)),
          fakeConnect(fake.pg).connect,
          REMOTE,
          consent,
        ),
      ).rejects.toThrow("bad row");
      expect(fake.texts()).toContain("rollback");
      expect(consents).toHaveLength(1);
    });
  });
});
