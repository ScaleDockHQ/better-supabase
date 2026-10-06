import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";
import type { Logger } from "../../src/core/logger.ts";

import { memoryCache } from "../../src/core/cache.ts";
import { defineRepository } from "../../src/core/define-repository.ts";
import { BetterSupabase, defineSupabase } from "../../src/core/define.ts";
import { definePlugin } from "../../src/core/plugin.ts";
import { ok } from "../../src/core/result.ts";
import { providedTemporal, provideTemporal } from "../../src/core/temporal.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const ACME = "00000000-0000-4000-8000-000000000001";

function echo(): Executor {
  return {
    name: "echo",
    execute: (op) => {
      if (op.kind === "insert")
        return Promise.resolve(
          ok({ rows: op.rows.map((row) => ({ ...row })), count: null }),
        );
      if (op.kind === "delete" || op.kind === "update")
        return Promise.resolve(ok({ rows: [{ id: "t1" }], count: null }));
      return Promise.resolve(ok({ rows: [{ id: "t1", name: "a" }], count: 1 }));
    },
  };
}

function recordingLogger(): Logger & { readonly messages: string[] } {
  const messages: string[] = [];
  const record = (message: string): void => void messages.push(message);
  return { messages, debug: record, info: record, warn: record, error: record };
}

describe("betterSupabase.cache", () => {
  it("invalidates the table, cascaded tables, row keys and tenant after mutations", async () => {
    const betterSupabase = defineSupabase(schema).use(tenant());
    const cache = memoryCache();
    const detach = betterSupabase.cache(cache);
    const db = betterSupabase.connect(echo(), { tenant: ACME });

    await db.tags
      .create({ id: "t1", name: "a", organizationId: ACME })
      .orThrow();
    await db.tags.delete("t1").orThrow();
    await db.tags.findMany({ limit: 1 }).orThrow();
    expect(cache.invalidated).toEqual([
      { table: "tags", tables: ["tags"], ids: ["t1"], tenant: ACME },
      {
        table: "tags",
        tables: ["tags", "customerTags"],
        ids: ["t1"],
        tenant: ACME,
      },
    ]);

    detach();
    await db.tags
      .create({ id: "t2", name: "b", organizationId: ACME })
      .orThrow();
    expect(cache.invalidated).toHaveLength(2);
  });

  it("logs adapter failures without failing the mutation", async () => {
    const logger = recordingLogger();
    const betterSupabase = defineSupabase(schema, { logger });
    betterSupabase.cache({
      name: "sync",
      invalidate: () => {
        throw new Error("down");
      },
    });
    betterSupabase.cache({
      name: "async",
      invalidate: () => Promise.reject(new Error("down")),
    });

    const created = await betterSupabase
      .connect(echo())
      .tags.create({ id: "t1", name: "a", organizationId: ACME });
    await Promise.resolve();
    expect(created.ok).toBe(true);
    expect(logger.messages).toEqual([
      'cache adapter "sync" failed',
      'cache adapter "async" failed',
    ]);
  });
});

describe("logger", () => {
  it("receives event handler and afterMutation failures", async () => {
    const logger = recordingLogger();
    const betterSupabase = defineSupabase(schema, { logger }).use(
      definePlugin({
        name: "noisy",
        afterMutation: () => {
          throw new Error("hook");
        },
      }),
    );
    betterSupabase.on("query", () => {
      throw new Error("handler");
    });
    const result = await betterSupabase
      .connect(echo())
      .tags.create({ id: "t1", name: "a", organizationId: ACME });
    expect(result.ok).toBe(true);
    expect(logger.messages).toEqual([
      '"query" handler threw',
      'plugin "noisy" afterMutation threw',
    ]);
  });
});

describe("per-definition state", () => {
  const ORG = "00000000-0000-4000-8000-000000000002";
  const claims = { sub: "u1", org_id: ACME, app_metadata: { tenant: ORG } };

  it("resolves each definition's tenant from its own claim paths", () => {
    const byOrganization = defineSupabase(schema).use(
      tenant({ claim: "org_id" }),
    );
    const byMetadata = defineSupabase(schema).use(
      tenant({ claim: "app_metadata.tenant" }),
    );
    expect(byOrganization.connect(echo(), { claims }).$context.tenant).toBe(
      ACME,
    );
    expect(byMetadata.connect(echo(), { claims }).$context.tenant).toBe(ORG);
    expect(byOrganization.connect(echo(), { claims }).$context.tenant).toBe(
      ACME,
    );
  });

  it("derives the context again for $with and drops it for $withoutPlugins", () => {
    const db = defineSupabase(schema)
      .use(tenant({ claim: "org_id" }))
      .connect(echo(), { claims });
    expect(
      db.$with({ claims: { sub: "u1", org_id: ORG } }).$context.tenant,
    ).toBe(ORG);
    expect(db.$withoutPlugins().$context.tenant).toBeUndefined();
  });

  it("logs a context hook that throws and keeps the caller's context", () => {
    const logger = recordingLogger();
    const db = defineSupabase(schema, { logger })
      .use(
        definePlugin({
          name: "broken",
          context: () => {
            throw new Error("boom");
          },
        }),
      )
      .connect(echo(), { tenant: ACME });
    expect(db.$context.tenant).toBe(ACME);
    expect(logger.messages).toEqual(['plugin "broken" context threw']);
  });

  it("warns when a second definition provides a different Temporal", () => {
    const previous = providedTemporal();
    try {
      const logger = recordingLogger();
      // SAFETY: the copy only needs to be a distinct namespace object.
      const first = Object.create(Temporal) as typeof Temporal;
      // SAFETY: as above.
      const second = Object.create(Temporal) as typeof Temporal;
      defineSupabase(schema, { logger, temporal: first });
      defineSupabase(schema, { logger, temporal: first });
      expect(logger.messages).toEqual([]);
      defineSupabase(schema, { logger, temporal: second });
      expect(logger.messages).toHaveLength(1);
      expect(logger.messages[0]).toMatch(/different `temporal` namespace/);
    } finally {
      provideTemporal(previous);
    }
  });
});

describe("defineRepository", () => {
  const base = defineSupabase(schema);

  it("adds methods to one table only", async () => {
    const tags = defineRepository(base, "tags", (repo) => ({
      named: (name: string) => repo.findFirst({ where: { name } }),
    }));
    expect(tags.name).toBe("repository:tags");
    const db = base.use(tags).connect(echo());
    await expect(db.tags.named("a").orThrow()).resolves.toEqual({
      id: "t1",
      name: "a",
    });
    expect("named" in db.customers).toBe(false);
  });

  it("sees methods from other plugins and rejects clashes and unknown tables", () => {
    const scoped = defineRepository(base, "tags", (repo) => ({
      all: () => repo.findMany({}),
    }));
    const clash = defineRepository(base, "tags", () => ({ findMany: () => 1 }));
    expect(() => base.use(scoped).use(clash)).toThrow(/already installed/);
    expect(() => base.use(clash).connect(echo()).tags).toThrow(
      /redefines "tags.findMany"/,
    );
    // @ts-expect-error unknown table
    expect(() => defineRepository(base, "nope", () => ({}))).toThrow(
      /unknown table "nope"/,
    );
  });
});

describe("pipeline consistency", () => {
  it("passes the caller's signal to transformQuery and beforeMutation", async () => {
    const seen: (AbortSignal | undefined)[] = [];
    const db = defineSupabase(schema)
      .use(
        definePlugin({
          name: "spy",
          transformQuery: (op, { signal }) => {
            seen.push(signal);
            return op;
          },
          beforeMutation: (op, { signal }) => {
            seen.push(signal);
            return op;
          },
        }),
      )
      .connect(echo());
    const controller = new AbortController();
    await db.tags
      .create(
        { id: "t1", name: "a", organizationId: ACME },
        { signal: controller.signal },
      )
      .orThrow();
    await db.tags.findMany({ limit: 1 }).orThrow();
    expect(seen).toEqual([controller.signal, controller.signal, undefined]);
  });

  it("reports a hook's unexpected throw as an error result with the table and plugin", async () => {
    const errors: unknown[] = [];
    const betterSupabase = defineSupabase(schema).use(
      definePlugin({
        name: "buggy",
        beforeMutation: () => {
          throw new TypeError("cannot read x");
        },
      }),
    );
    betterSupabase.on("error", (event) => errors.push(event));
    const result = await betterSupabase
      .connect(echo())
      .tags.create({ id: "t1", name: "a", organizationId: ACME });
    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "unexpected",
      message: "cannot read x",
      table: "tags",
      details: 'plugin "buggy" beforeMutation threw',
    });
    expect(errors).toEqual([
      expect.objectContaining({
        table: "tags",
        error: expect.objectContaining({ kind: "unexpected" }),
      }),
    ]);
  });

  it("keeps the named plugins in $withoutPlugins and refuses unknown names", async () => {
    const calls: string[] = [];
    const named = (name: string) =>
      definePlugin({
        name,
        transformQuery: (op) => {
          calls.push(name);
          return op;
        },
      });
    const db = defineSupabase(schema)
      .use(named("trace"))
      .use(named("scope"))
      .connect(echo());
    await db
      .$withoutPlugins({ keep: ["trace"] })
      .tags.findMany()
      .orThrow();
    await db.$withoutPlugins().tags.findMany().orThrow();
    expect(calls).toEqual(["trace"]);
    expect(() => db.$withoutPlugins({ keep: ["trcae"] })).toThrow(
      '$withoutPlugins({ keep }) names "trcae", which is not installed',
    );
  });

  it("validates plugins in the constructor, not only in use()", () => {
    const plugin = definePlugin({ name: "twice" });
    expect(
      () => new BetterSupabase(defineSupabase(schema).schema, [plugin, plugin]),
    ).toThrow('plugin "twice" is already installed');
    const future = { ...plugin, name: "future", apiVersion: 2 } as never;
    expect(
      () => new BetterSupabase(defineSupabase(schema).schema, [future]),
    ).toThrow('plugin "future" targets plugin API v2');
  });
});
