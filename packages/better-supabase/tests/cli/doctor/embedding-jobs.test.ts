import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { LIVE_CODES } from "../../../src/cli/doctor/live-source.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);

const context = (
  database: LiveDatabase | undefined,
  blocks: Record<string, unknown> = {},
): DoctorContext => ({
  config: resolveConfig(
    {
      appTables: {
        articles: {
          columns: { title: { type: "text" } },
          embedding: { content: ["title"], dimensions: 8 },
        },
      },
      blocks,
      // SAFETY: the knowledge options are partial on purpose.
    } as never,
    "/project",
  ),
  snapshot,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  sqlFiles: [],
  ...(database === undefined ? {} : { database }),
});

const database = (
  answer: (sql: string) => Record<string, unknown>[] | Error,
  seen: string[] = [],
): LiveDatabase => ({
  describe: "test database",
  session: true,
  // SAFETY: each answer holds the columns its query selects.
  query: ((sql: string) => {
    seen.push(sql);
    const result = answer(sql);

    return result instanceof Error
      ? Promise.reject(result)
      : Promise.resolve(result);
  }) as LiveDatabase["query"],
});

const run = (ctx: DoctorContext, code: string) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === code),
  );

describe("BS241", () => {
  it("is a live check", () => {
    expect(LIVE_CODES.has("BS241")).toBe(true);
    expect(LIVE_CODES.has("BS242")).toBe(true);
  });

  it("reports a queue with jobs read five times or more", async () => {
    const seen: string[] = [];

    const findings = await run(
      context(database(() => [{ stuck: "2", reads: "9" }], seen)),
      "BS241",
    );

    expect(seen[0]).toContain('pgmq."q_articles_embed"');
    expect(findings).toMatchObject([
      {
        code: "BS241",
        target: "pgmq.articles_embed",
        message: expect.stringContaining("2 embedding jobs read 5 times"),
      },
    ]);
  });

  it("stays silent for a clean queue and a queue not created yet", async () => {
    expect(
      await run(
        context(database(() => [{ stuck: "0", reads: null }])),
        "BS241",
      ),
    ).toEqual([]);

    expect(
      await run(
        context(
          database(
            () => new Error('relation "pgmq.q_articles_embed" does not exist'),
          ),
        ),
        "BS241",
      ),
    ).toEqual([]);
  });

  it("skips without a database", async () => {
    expect(await run(context(undefined), "BS241")).toEqual([]);
  });
});

describe("BS242", () => {
  it("reports failed pg_net responses of the last hour", async () => {
    const findings = await run(
      context(database(() => [{ failed: "3", status: 401, error: null }])),
      "BS242",
    );

    expect(findings).toMatchObject([
      {
        code: "BS242",
        target: "net._http_response",
        message: expect.stringContaining("3 pg_net requests failed"),
      },
    ]);
  });

  it("stays silent without failures", async () => {
    expect(
      await run(
        context(database(() => [{ failed: "0", status: null, error: null }])),
        "BS242",
      ),
    ).toEqual([]);
  });
});

describe("embedding job rules, remaining paths", () => {
  it("reports a single job and an unreadable queue", async () => {
    const one = await run(
      context(database(() => [{ stuck: "1", reads: null }])),
      "BS241",
    );

    const broken = await run(
      context(database(() => new Error("connection reset"))),
      "BS241",
    );

    expect(one).toMatchObject([
      { message: expect.stringContaining("1 embedding job read 5") },
    ]);
    expect(broken).toMatchObject([
      { message: expect.stringContaining("Could not read the queue") },
    ]);
  });

  it("names the error or the status of failed requests", async () => {
    const withError = await run(
      context(
        database(() => [{ failed: "1", status: null, error: "timeout" }]),
      ),
      "BS242",
    );

    const withoutReason = await run(
      context(database(() => [{ failed: "2", status: null, error: null }])),
      "BS242",
    );

    expect(withError).toMatchObject([
      { message: expect.stringContaining("1 pg_net request failed") },
    ]);
    expect(withError[0]?.message).toContain("(timeout)");
    expect(withoutReason[0]?.message).toContain("()");
  });

  it("skips without a pipeline, without a database and without pg_net", async () => {
    const none: DoctorContext = {
      ...context(database(() => [])),
      config: resolveConfig({}, "/project"),
    };

    expect(await run(none, "BS242")).toEqual([]);
    expect(await run(context(undefined), "BS242")).toEqual([]);
    expect(
      await run(
        context(
          database(
            () => new Error('relation "net._http_response" does not exist'),
          ),
        ),
        "BS242",
      ),
    ).toEqual([]);
    expect(
      await run(
        context(database(() => new Error("permission denied"))),
        "BS242",
      ),
    ).toMatchObject([{ code: "BS242" }]);
  });

  it("counts a knowledge auto-embed pipeline", async () => {
    const ctx: DoctorContext = {
      ...context(database(() => [{ failed: "1", status: 500, error: null }])),
      config: resolveConfig(
        { blocks: { knowledge: { options: { autoEmbed: true } } } },
        "/project",
      ),
    };

    expect((await run(ctx, "BS242"))[0]?.message).toContain("status 500");
  });
});
