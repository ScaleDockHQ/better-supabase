import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createMemory, sqlTransport } from "../../src/blocks/memory/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";
import { wordEmbedder } from "./word-embedder.ts";

const live = await reachable();

describe.skipIf(!live)("memory owners, tenants and limits", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("keeps private organization and record memory to its owner", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "memory"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const other = await s.user("other");
      const tenant = await s.organization(owner, { member, member2: other });
      const memory = createMemory({ transport: sqlTransport(s.sql) });
      const mine = { scope: "organization", private: true } as const;

      await s.asRole(member);
      await memory.core
        .write({
          organizationId: tenant,
          path: "/memories/notes.md",
          content: "my view of the org",
          ns: mine,
        })
        .orThrow();
      await memory.core
        .write({
          organizationId: tenant,
          path: "/memories/notes.md",
          content: "my edited view",
          ns: mine,
        })
        .orThrow();
      expect(
        await memory.core
          .view({
            organizationId: tenant,
            path: "/memories/notes.md",
            ns: mine,
          })
          .orThrow(),
      ).toMatchObject({ content: "my edited view" });

      const shared = await memory.core.write({
        organizationId: tenant,
        path: "/memories/notes.md",
        content: "x",
        ns: { scope: "organization" },
      });

      expect(shared.ok ? undefined : shared.error.hint).toBe(
        "MEMORY_FORBIDDEN",
      );

      await s.asRole(other);
      expect(
        await memory.core
          .view({
            organizationId: tenant,
            path: "/memories/notes.md",
            ns: mine,
          })
          .orThrow(),
      ).toBeUndefined();
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.memories where scope = 'organization')",
        ),
      ).toBe(0);

      await s.asRole(owner);
      expect(
        await memory.core
          .view({
            organizationId: tenant,
            path: "/memories/notes.md",
            ns: { scope: "organization" },
          })
          .orThrow(),
      ).toBeUndefined();

      await s.service();

      const record = {
        scope: "record",
        private: true,
        ownerId: member.id,
        subject: { type: "deal", id: "d1" },
      } as const;

      await memory.core
        .write({
          organizationId: tenant,
          path: "/memories/deal.md",
          content: "call back friday",
          ns: record,
        })
        .orThrow();

      const unnamed = await memory.core.view({
        organizationId: tenant,
        path: "/memories",
        ns: {
          scope: "record",
          private: true,
          subject: { type: "deal", id: "d1" },
        },
      });

      expect(unnamed.ok ? undefined : unnamed.error.hint).toBe(
        "MEMORY_NAMESPACE",
      );

      await s.asRole(member);
      expect(
        await memory.core
          .view({
            organizationId: tenant,
            path: "/memories/deal.md",
            ns: {
              scope: "record",
              private: true,
              subject: { type: "deal", id: "d1" },
            },
          })
          .orThrow(),
      ).toMatchObject({ content: "call back friday" });
    } finally {
      await s.close();
    }
  });

  it("keeps personal memory without a tenant with options.tenant false", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "memory"], {
        modules: { memory: { options: { tenant: false } } },
      });
      const user = await s.user("user");
      const memory = createMemory({ transport: sqlTransport(s.sql) });

      await s.asRole(user);
      await memory.core
        .write({
          organizationId: null,
          path: "/memories/me.md",
          content: "prefers short answers",
        })
        .orThrow();
      expect(
        await memory.core
          .view({ organizationId: null, path: "/memories/me.md" })
          .orThrow(),
      ).toMatchObject({ content: "prefers short answers" });

      const [file] = await memory.core.list({ organizationId: null }).orThrow();

      expect(file).toMatchObject({ organizationId: null, ownerId: user.id });

      const shared = await memory.core.view({
        organizationId: null,
        path: "/memories",
        ns: { scope: "organization" },
      });

      expect(shared.ok ? undefined : shared.error.hint).toBe(
        "MEMORY_NAMESPACE",
      );
    } finally {
      await s.close();
    }
  });

  it("caps archival facts with options.maxItems and purges one tenant", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "memory"], {
        modules: { memory: { options: { maxItems: 2 } } },
      });
      const owner = await s.user("owner");
      const first = await s.organization(owner);
      const second = await s.organization(owner);

      const memory = createMemory({
        transport: sqlTransport(s.sql),
        embedder: wordEmbedder(),
      });

      await s.asRole(owner);

      for (const [age, fact] of [
        [3, "has a dog"],
        [2, "lives in Utrecht"],
        [1, "drinks coffee"],
      ] as const) {
        await s.asRole(owner);

        const saved = await memory.archival
          .upsert({ organizationId: first, content: `The user ${fact}.` })
          .orThrow();

        await s.service();
        await s.sql.queryRaw(
          "update better_supabase.memories set created_at = now() - make_interval(mins => $2) where id = $1",
          [saved.id, age],
        );
      }

      await s.asRole(owner);

      const chess = await memory.archival
        .upsert({ organizationId: second, content: "The user plays chess." })
        .orThrow();

      await memory.archival.forget({ memoryId: chess.id }).orThrow();

      const kept = await memory.archival
        .list({ organizationId: first })
        .orThrow();

      expect(kept.map((fact) => fact.content).toSorted()).toEqual([
        "The user drinks coffee.",
        "The user lives in Utrecht.",
      ]);

      await s.service();
      await s.sql.queryRaw(
        "update better_supabase.memories set deleted_at = now() - interval '40 days' where deleted_at is not null",
      );
      expect(
        await memory.archival
          .purge({ retentionDays: 30, organizationId: first })
          .orThrow(),
      ).toBe(1);
      expect(
        await memory.archival
          .purge({ retentionDays: 30, organizationId: second })
          .orThrow(),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });
});
