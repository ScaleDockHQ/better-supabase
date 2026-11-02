import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import type { AiFileStorage } from "../../src/blocks/ai-files/index.ts";
import type { Result } from "../../src/core/result.ts";

import { createAgents } from "../../src/blocks/agents/index.ts";
import { createAiChat } from "../../src/blocks/ai-chat/index.ts";
import { createAiFiles } from "../../src/blocks/ai-files/index.ts";
import { createAiSchedules } from "../../src/blocks/ai-schedules/index.ts";
import { createAnnouncements } from "../../src/blocks/announcements/index.ts";
import { createApiKeys } from "../../src/blocks/api-keys/index.ts";
import { createApprovals } from "../../src/blocks/approvals/index.ts";
import { createAttachments } from "../../src/blocks/attachments/index.ts";
import { createBookings } from "../../src/blocks/bookings/index.ts";
import { createCalendar } from "../../src/blocks/calendar/index.ts";
import { createCatalog } from "../../src/blocks/catalog/index.ts";
import { createCollections } from "../../src/blocks/collections/index.ts";
import { createComments } from "../../src/blocks/comments/index.ts";
import { createConnectors } from "../../src/blocks/connectors/index.ts";
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
          .create({
            organizationId: tenant,
            agent: { slug: "bad", name: "Bad", priority: 0 },
          })
          .then(kind),
      ).toBe("validation");

      const created = await agents
        .create({
          organizationId: tenant,
          agent: { slug: "writer", name: "Writer", label: "blog" },
        })
        .orThrow();

      expect(created).toMatchObject({ label: "blog", priority: null });

      const updated = await agents
        .update({
          organizationId: tenant,
          agentId: created.id,
          fields: { priority: 2 },
        })
        .orThrow();

      expect(updated).toMatchObject({ label: "blog", priority: 2 });
      expect(await agents.get(created.id).orThrow()).toMatchObject({
        priority: 2,
      });

      const [listed] = await agents
        .list({ organizationId: tenant, filter: "mine" })
        .orThrow();

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
      expect(
        await chat.chats
          .create({ organizationId: tenant, input: { priority: 0 } })
          .then(kind),
      ).toBe("validation");

      const created = await chat.chats
        .create({
          organizationId: tenant,
          input: { title: "Plan", label: "work" },
        })
        .orThrow();

      expect(created).toMatchObject({ title: "Plan", label: "work" });

      const updated = await chat.chats
        .update({ chatId: created.id, patch: { priority: 3 } })
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
              bucket: "bsb-it-ai-file-fields",
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
          .upload({
            organizationId: tenant,
            file: {
              filename: "a.png",
              mediaType: "image/png",
              size: 3,
              priority: 0,
            },
          })
          .then(kind),
      ).toBe("validation");

      const { file } = await files.files
        .upload({
          organizationId: tenant,
          file: {
            filename: "a.png",
            mediaType: "image/png",
            size: 3,
            label: "logo",
          },
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

  it("ai-schedules", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(
        ["organizations", "agents", "ai-schedules"],
        extraColumns("ai-schedules"),
      );
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const tasks = createAiSchedules({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.asRole(owner);
      const task = { title: "Digest", prompt: "Sum up", cron: "0 9 * * *" };
      expect(
        await tasks
          .create({ organizationId: tenant, task: { ...task, priority: 0 } })
          .then(kind),
      ).toBe("validation");

      const created = await tasks
        .create({ organizationId: tenant, task: { ...task, label: "daily" } })
        .orThrow();

      expect(created).toMatchObject({ title: "Digest", label: "daily" });

      const paused = await tasks
        .pause({ organizationId: tenant, taskId: created.id })
        .orThrow();

      expect(paused).toMatchObject({ enabled: false, label: "daily" });
      await tasks
        .update({
          organizationId: tenant,
          taskId: created.id,
          fields: { priority: 4 },
        })
        .orThrow();
      const [listed] = await tasks.list({ organizationId: tenant }).orThrow();
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
        .update({ announcementId: published.id, input: { priority: 2 } })
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
      const rotated = await keys.rotate({ id: key.id }).orThrow();
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

  it("approvals", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "approvals"], {
        modules: {
          approvals: {
            options: {
              policies: {
                doc: { publish: { steps: [{ approvers: { role: "owner" } }] } },
              },
              extraColumns: { label: "text", priority: "integer" },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });

      const approvals = createApprovals({
        transport: sqlTransport(s.sql),
        tenant,
        fields: Fields,
      });

      await s.asRole(member);
      expect(
        await approvals
          .request({
            subject: { type: "doc", id: "d0" },
            input: { action: "publish", priority: 0 },
          })
          .then(kind),
      ).toBe("validation");

      const request = await approvals
        .request({
          subject: { type: "doc", id: "d1" },
          input: { action: "publish", label: "launch" },
        })
        .orThrow();

      expect(request).toMatchObject({ status: "pending", label: "launch" });
      expect(await approvals.get(request.id).orThrow()).toMatchObject({
        label: "launch",
        priority: null,
      });
      await s.asRole(owner);
      const approved = await approvals.approve({ id: request.id }).orThrow();
      expect(approved).toMatchObject({ status: "approved", label: "launch" });
      const [listed] = await approvals.list({ status: null }).orThrow();
      expect(listed).toMatchObject({ label: "launch" });
    } finally {
      await s.close();
    }
  });

  it("attachments", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "attachments"], {
        modules: {
          attachments: {
            options: {
              bucket: "bsb-it-attachment-fields",
              requireScan: false,
              extraColumns: {
                label: "text",
                priority: "integer not null default 1",
              },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const attachments = createAttachments({
        transport: sqlTransport(s.sql),
        storage: {
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
            download: () =>
              Promise.resolve({ data: new Blob([]), error: null }),
            remove: () => Promise.resolve({ data: [], error: null }),
          }),
        },
        fields: v.object({
          label: v.nullable(v.string()),
          priority: v.pipe(v.number(), v.minValue(1)),
        }),
        tenant,
      });

      const file = { name: "a.pdf", mimeType: "application/pdf", size: 3 };

      await s.asRole(owner);
      expect(
        await attachments
          .upload({ subject: null, attachment: { ...file, priority: 0 } })
          .then(kind),
      ).toBe("validation");

      const { attachment } = await attachments
        .upload({ subject: null, attachment: { ...file, label: "contract" } })
        .orThrow();

      expect(attachment).toMatchObject({ label: "contract", priority: 1 });
      const [listed] = await attachments.list().orThrow();
      expect(listed).toMatchObject({ label: "contract", priority: 1 });
      expect(await attachments.get(attachment.id).orThrow()).toMatchObject({
        label: "contract",
      });
    } finally {
      await s.close();
    }
  });

  it("bookings", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "bookings"], extraColumns("bookings"));
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const bookings = createBookings({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.as(owner);

      const { id: resource } = await bookings
        .saveResource({
          organizationId: tenant,
          input: { name: "Ann", kind: "staff", tz: "UTC" },
        })
        .orThrow();

      await bookings
        .setAvailability({
          resourceId: resource,
          hours: [{ weekday: 1, start: "09:00", end: "12:00" }],
        })
        .orThrow();

      const { id: service } = await bookings
        .saveService({
          organizationId: tenant,
          input: { name: "Call", duration: "PT30M" },
        })
        .orThrow();

      const startsAt = Temporal.Instant.from("2030-03-04T09:00:00Z");
      expect(
        await bookings
          .hold({
            serviceId: service,
            resourceId: resource,
            startsAt,
            customer: { name: "Ada", priority: 0 },
          })
          .then(kind),
      ).toBe("validation");

      const held = await bookings
        .hold({
          serviceId: service,
          resourceId: resource,
          startsAt,
          customer: { name: "Ada", label: "vip" },
        })
        .orThrow();

      expect(held).toMatchObject({ customerName: "Ada", label: "vip" });
      const confirmed = await bookings.confirm(held.id).orThrow();
      expect(confirmed).toMatchObject({ status: "confirmed", label: "vip" });

      const [listed] = await bookings
        .list({
          organizationId: tenant,
          range: {
            from: Temporal.Instant.from("2030-03-04T00:00:00Z"),
            until: Temporal.Instant.from("2030-03-05T00:00:00Z"),
          },
        })
        .orThrow();

      expect(listed).toMatchObject({ label: "vip", priority: null });
    } finally {
      await s.close();
    }
  });

  it("calendar", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "calendar"], extraColumns("calendar"));
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const calendar = createCalendar({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.as(owner);

      const { id: calendarId } = await calendar
        .createCalendar({ organizationId: tenant, name: "Team" })
        .orThrow();

      const event = {
        title: "Standup",
        startsAt: Temporal.Instant.from("2030-03-04T09:00:00Z"),
        endsAt: Temporal.Instant.from("2030-03-04T09:15:00Z"),
      };

      expect(
        await calendar
          .upsert({ calendarId, input: { ...event, priority: 0 } })
          .then(kind),
      ).toBe("validation");

      const { id } = await calendar
        .upsert({ calendarId, input: { ...event, label: "daily" } })
        .orThrow();

      await calendar
        .upsert({ calendarId, input: { id, priority: 2 } })
        .orThrow();

      const [listed] = await calendar
        .events({
          calendarIds: [calendarId],
          range: {
            from: Temporal.Instant.from("2030-03-04T00:00:00Z"),
            until: Temporal.Instant.from("2030-03-05T00:00:00Z"),
          },
        })
        .orThrow();

      expect(listed).toMatchObject({
        title: "Standup",
        label: "daily",
        priority: 2,
      });
    } finally {
      await s.close();
    }
  });

  it("catalog", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "catalog"], extraColumns("catalog"));
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const catalog = createCatalog({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.as(owner);
      expect(
        await catalog
          .createProduct({
            organizationId: tenant,
            input: { title: "Mug", priority: 0 },
          })
          .then(kind),
      ).toBe("validation");

      const created = await catalog
        .createProduct({
          organizationId: tenant,
          input: { title: "Mug", label: "kitchen" },
        })
        .orThrow();

      expect(created).toMatchObject({ slug: "mug", label: "kitchen" });

      const updated = await catalog
        .updateProduct({
          organizationId: tenant,
          productId: created.id,
          input: { title: "Mug", priority: 5 },
        })
        .orThrow();

      expect(updated).toMatchObject({ label: "kitchen", priority: 5 });
    } finally {
      await s.close();
    }
  });

  it("collections", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(
        "create table if not exists public.block_fields_memos (id uuid primary key default gen_random_uuid(), organization_id uuid not null)",
      );
      await s.install(["organizations", "subjects", "collections"], {
        subjects: {
          memo: { table: "public.block_fields_memos", idType: "uuid" },
        },
        ...extraColumns("collections"),
      });
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const collections = createCollections({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.as(owner);
      const input = { name: "Reading", subjectType: "memo" };
      expect(
        await collections
          .create({ organizationId: tenant, input: { ...input, priority: 0 } })
          .then(kind),
      ).toBe("validation");

      const created = await collections
        .create({ organizationId: tenant, input: { ...input, label: "later" } })
        .orThrow();

      expect(created).toMatchObject({ name: "Reading", label: "later" });

      const renamed = await collections
        .rename({ id: created.id, input: { priority: 3 } })
        .orThrow();

      expect(renamed).toMatchObject({ label: "later", priority: 3 });

      const [listed] = await collections
        .list({ organizationId: tenant })
        .orThrow();

      expect(listed).toMatchObject({ label: "later", priority: 3 });
    } finally {
      await s.close();
    }
  });

  it("comments", async () => {
    const s = await BlockSession.open(pool);

    try {
      const table = `public.bsb_fields_projects_${crypto.randomUUID().slice(0, 8)}`;
      await s.rows(
        `create table ${table} (id uuid primary key default gen_random_uuid(), organization_id uuid not null);
         alter table ${table} enable row level security;
         grant select on ${table} to authenticated;
         create policy "read" on ${table} for select to authenticated using (true);`,
      );
      // Comments are messages, so their extra columns live on messaging.
      await s.install(["organizations", "subjects", "messaging", "comments"], {
        subjects: { project: { table } },
        ...extraColumns("messaging"),
      });
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const [row] = await s.rows<{ id: string }>(
        `insert into ${table} (organization_id) values ($1) returning id`,
        [tenant],
      );

      const comments = createComments({
        transport: sqlTransport(s.sql),
        fields: Fields,
        tenant,
      });

      await s.asRole(owner);

      const project = { type: "project", id: row!.id };
      const input = { body: "Looks good" };

      expect(
        await comments
          .create({
            subject: project,
            comment: { ...input, fields: { priority: 0 } },
          })
          .then(kind),
      ).toBe("validation");

      const created = await comments
        .create({
          subject: project,
          comment: { ...input, fields: { label: "review" } },
        })
        .orThrow();

      expect(created.fields).toMatchObject({ label: "review", priority: null });
      expect(created.editedAt).toBeUndefined();

      const edited = await comments
        .edit({
          id: created.id,
          edit: { body: "Looks great", fields: { priority: 2 } },
        })
        .orThrow();

      expect(edited).toMatchObject({
        body: "Looks great",
        fields: { label: "review", priority: 2 },
      });
      const [listed] = await comments.list({ subject: project }).orThrow();
      expect(listed?.fields).toMatchObject({ label: "review", priority: 2 });
    } finally {
      await s.close();
    }
  });

  it("connectors", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(
        ["organizations", "connectors"],
        extraColumns("connectors"),
      );
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const connectors = createConnectors({
        transport: sqlTransport(s.sql),
        fields: Fields,
      });

      await s.asRole(owner);
      const input = { name: "GitHub", url: "https://mcp.example.com/mcp" };
      expect(
        await connectors.servers
          .create({
            organizationId: tenant,
            server: { ...input, fields: { priority: 0 } },
          })
          .then(kind),
      ).toBe("validation");

      const created = await connectors.servers
        .create({
          organizationId: tenant,
          server: { ...input, fields: { label: "code" } },
        })
        .orThrow();

      expect(created.fields).toMatchObject({ label: "code", priority: null });

      const updated = await connectors.servers
        .update({
          organizationId: tenant,
          serverId: created.id,
          fields: { enabled: false, fields: { priority: 4 } },
        })
        .orThrow();

      expect(updated).toMatchObject({
        enabled: false,
        fields: { label: "code", priority: 4 },
      });
      const [listed] = await connectors.servers.list(tenant).orThrow();
      expect(listed?.fields).toMatchObject({ label: "code", priority: 4 });
      expect(
        (await connectors.servers.get({ serverId: created.id }).orThrow())
          .fields,
      ).toMatchObject({ label: "code", priority: 4 });
    } finally {
      await s.close();
    }
  });
});
