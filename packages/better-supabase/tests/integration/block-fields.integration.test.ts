import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import type { AiFileStorage } from "../../src/blocks/ai-files/index.ts";
import type { Result } from "../../src/core/result.ts";

import { createAgents } from "../../src/blocks/agents/index.ts";
import { createAiChat } from "../../src/blocks/ai-chat/index.ts";
import { createAiFiles } from "../../src/blocks/ai-files/index.ts";
import { createAiTasks } from "../../src/blocks/ai-tasks/index.ts";
import { createAnnouncements } from "../../src/blocks/announcements/index.ts";
import { createApiKeys } from "../../src/blocks/api-keys/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

/** `extraColumns` for a module: one text column and one integer column. */
const extraColumns = (module: string) => ({
  modules: {
    [module]: {
      options: { extraColumns: { label: "text", priority: "integer" } },
    },
  },
});

const Fields = v.object({
  label: v.nullable(v.string()),
  priority: v.nullable(v.pipe(v.number(), v.minValue(1))),
});

const kind = (result: Result<unknown>) =>
  result.ok ? "ok" : result.error.kind;

// Each block that takes `fields` writes its extra columns, returns them
// from its reads and refuses a value the schema rejects (ADR 0015).
describe.skipIf(!live)("block fields", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("agents", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "agents"], extraColumns("agents"));
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const agents = createAgents({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.asRole(owner);
      expect(
        await agents
          .create(tenant, { slug: "bad", name: "Bad", priority: 0 })
          .then(kind),
      ).toBe("validation");
      const created = await agents
        .create(tenant, { slug: "writer", name: "Writer", label: "blog" })
        .orThrow();
      expect(created).toMatchObject({ label: "blog", priority: null });
      const updated = await agents
        .update(tenant, created.id, { priority: 2 })
        .orThrow();
      expect(updated).toMatchObject({ label: "blog", priority: 2 });
      expect(await agents.get(created.id).orThrow()).toMatchObject({
        priority: 2,
      });
      const [listed] = await agents.list(tenant, { filter: "mine" }).orThrow();
      expect(listed).toMatchObject({ label: "blog", priority: 2 });
    } finally {
      await s.close();
    }
  });

  it("ai-chat", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "ai-chat"], extraColumns("ai-chat"));
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const chat = createAiChat({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.asRole(owner);
      expect(await chat.chats.create(tenant, { priority: 0 }).then(kind)).toBe(
        "validation",
      );
      const created = await chat.chats
        .create(tenant, { title: "Plan", label: "work" })
        .orThrow();
      expect(created).toMatchObject({ title: "Plan", label: "work" });
      const updated = await chat.chats
        .update(created.id, { priority: 3 })
        .orThrow();
      expect(updated).toMatchObject({ label: "work", priority: 3 });
      expect(await chat.chats.get(created.id).orThrow()).toMatchObject({
        priority: 3,
      });
      const page = await chat.chats.list().orThrow();
      expect(page.items[0]).toMatchObject({ label: "work", priority: 3 });
    } finally {
      await s.close();
    }
  });

  it("ai-files", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "ai-files"], {
        modules: {
          "ai-files": {
            options: {
              bucket: "bs-it-ai-file-fields",
              extraColumns: { label: "text", priority: "integer" },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const storage: AiFileStorage = {
        from: () => ({
          createSignedUploadUrl: (path) =>
            Promise.resolve({
              data: { signedUrl: `https://storage.test/${path}`, token: "t" },
              error: null,
            }),
          createSignedUrl: (path) =>
            Promise.resolve({
              data: { signedUrl: `https://storage.test/${path}` },
              error: null,
            }),
          download: () => Promise.resolve({ data: new Blob([]), error: null }),
          remove: () => Promise.resolve({ data: [], error: null }),
        }),
      };
      const files = createAiFiles({
        transport: sqlTransport(s.sql),
        storage,
        fields: Fields,
      });

      await s.asRole(owner);
      expect(
        await files.files
          .upload(tenant, {
            filename: "a.png",
            mediaType: "image/png",
            size: 3,
            priority: 0,
          })
          .then(kind),
      ).toBe("validation");
      const { file } = await files.files
        .upload(tenant, {
          filename: "a.png",
          mediaType: "image/png",
          size: 3,
          label: "logo",
        })
        .orThrow();
      expect(file).toMatchObject({ filename: "a.png", label: "logo" });
      expect(await files.files.get(file.id).orThrow()).toMatchObject({
        label: "logo",
        priority: null,
      });
    } finally {
      await s.close();
    }
  });

  it("ai-tasks", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(
        ["organizations", "agents", "ai-tasks"],
        extraColumns("ai-tasks"),
      );
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const tasks = createAiTasks({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.asRole(owner);
      const task = { title: "Digest", prompt: "Sum up", cron: "0 9 * * *" };
      expect(
        await tasks.create(tenant, { ...task, priority: 0 }).then(kind),
      ).toBe("validation");
      const created = await tasks
        .create(tenant, { ...task, label: "daily" })
        .orThrow();
      expect(created).toMatchObject({ title: "Digest", label: "daily" });
      const paused = await tasks.pause(tenant, created.id).orThrow();
      expect(paused).toMatchObject({ enabled: false, label: "daily" });
      await tasks.update(tenant, created.id, { priority: 4 }).orThrow();
      const [listed] = await tasks.list(tenant).orThrow();
      expect(listed).toMatchObject({ label: "daily", priority: 4 });
    } finally {
      await s.close();
    }
  });

  it("announcements", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(
        ["organizations", "announcements"],
        extraColumns("announcements"),
      );
      const member = await s.user("member");
      await s.organization(await s.user("owner"), { member });
      const announcements = createAnnouncements({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.service();
      expect(
        await announcements.publish({ title: "Bad", priority: 0 }).then(kind),
      ).toBe("validation");
      const published = await announcements
        .publish({ title: "Release", label: "product" })
        .orThrow();
      expect(published).toMatchObject({ title: "Release", label: "product" });
      const updated = await announcements
        .update(published.id, { priority: 2 })
        .orThrow();
      expect(updated).toMatchObject({ label: "product", priority: 2 });
      const [managed] = await announcements.list().orThrow();
      expect(managed).toMatchObject({ priority: 2 });

      await s.as(member);
      const [active] = await announcements.listActive().orThrow();
      expect(active).toMatchObject({ label: "product", priority: 2 });
    } finally {
      await s.close();
    }
  });

  it("api-keys", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "api-keys"], extraColumns("api-keys"));
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      const keys = createApiKeys({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.as(owner);
      expect(
        await keys
          .create({ name: "Bad", organizationId: tenant, priority: 0 })
          .then(kind),
      ).toBe("validation");
      const { key, token } = await keys
        .create({ name: "CI", organizationId: tenant, label: "deploys" })
        .orThrow();
      expect(key).toMatchObject({ name: "CI", label: "deploys" });
      const rotated = await keys.rotate(key.id).orThrow();
      expect(rotated.key).toMatchObject({ label: "deploys" });
      const listed = await keys.list(tenant).orThrow();
      expect(listed.map((row) => row.label)).toEqual(["deploys", "deploys"]);

      await s.service();
      const check = await keys.verify(token).orThrow();
      expect(check.status === "ok" ? check.key.label : undefined).toBe(
        "deploys",
      );
    } finally {
      await s.close();
    }
  });
});
