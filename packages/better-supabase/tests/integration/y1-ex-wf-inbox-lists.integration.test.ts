import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createInbox, sqlTransport } from "../../src/blocks/inbox/index.ts";
import { createWorkflowEditor } from "../../src/blocks/workflow-editor/index.ts";
import { createWorkflows } from "../../src/blocks/workflows/index.ts";
import { testBlockList } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)(
  "the workflow definitions, workflow runs and inbox lists follow the list contract",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 2 });

    afterAll(() => pool.end());

    it("pages workflow definitions by name, state and search", async () => {
      const s = await BlockSession.open(pool);

      try {
        await s.install(["organizations", "outbox", "workflow-editor"]);
        const owner = await s.user("defs-owner");
        const tenant = await s.organization(owner);
        await s.asRole(owner);

        const builder = createWorkflowEditor({
          transport: sqlTransport(s.sql),
          compile: (graph) => ({ engine: "test", nodes: graph.nodes.length }),
        });

        const graph = {
          nodes: [{ id: "start", kind: "trigger" as const }],
          edges: [],
        };

        const made: string[] = [];

        for (const name of [
          "Welcome mail",
          "Welcome call",
          "Invoice reminder",
          "Churn check",
          "Renewal notice",
        ]) {
          const created = await builder.definitions
            .upsert({
              tenant,
              slug: name.toLowerCase().replaceAll(" ", "-"),
              name,
            })
            .orThrow();

          made.push(created.id);
        }

        const draft = await builder.versions
          .upsert({ definition: made[1]!, graph })
          .orThrow();

        const published = await builder.versions
          .upsert({ definition: made[0]!, graph })
          .orThrow();

        await builder.versions.publish({ version: published.id }).orThrow();
        expect(draft.status).toBe("draft");

        // A transaction gives every row the same now(); the updatedAt and
        // createdAt sorts need distinct values.
        await s.client.query("reset role");

        await s.client.query(
          `update better_supabase.workflow_definitions a set created_at = now() + (r.n || ' minutes')::interval, updated_at = now() + (r.n || ' minutes')::interval from (select id, row_number() over (order by random()) as n from better_supabase.workflow_definitions) r where r.id = a.id`,
        );

        await s.asRole(owner);

        await testBlockList({
          name: "workflow-editor.definitions",
          target: {
            page: (options) =>
              builder.definitions.page({ ...options, organizationId: tenant }),
            count: (options) =>
              builder.definitions.count({ ...options, organizationId: tenant }),
            facets: (options) =>
              builder.definitions.facets({
                ...options,
                organizationId: tenant,
              }),
            get: (id) => builder.definitions.getDefinition(id),
          },
          rows: 5,
          sorts: ["name", "updatedAt", "createdAt"],
          facets: { state: { published: 1, draft: 1, new: 3 } },
          arrayFilter: { column: "state", values: ["published", "draft"] },
          search: "welcome",
        });

        const [first] = (
          await builder.definitions
            .page({ organizationId: tenant, filters: { state: ["published"] } })
            .orThrow()
        ).items;

        expect(first).toMatchObject({ id: made[0], published: 1 });
      } finally {
        await s.close();
      }
    });

    it("lists the runs of a definition id on the server", async () => {
      const s = await BlockSession.open(pool);

      try {
        await s.install(["organizations", "outbox", "workflow-editor"]);
        const owner = await s.user("runs-owner");
        const tenant = await s.organization(owner);
        await s.service();
        const workflows = createWorkflows({ transport: sqlTransport(s.sql) });

        const definitions = [crypto.randomUUID(), crypto.randomUUID()];

        for (const [index, definition] of [
          definitions[0]!,
          definitions[0]!,
          definitions[1]!,
          "",
        ].entries()) {
          await workflows.runs
            .record({
              engine: "workflow-sdk",
              externalId: `wrun_${String(index)}`,
              definition: "dynamic",
              status: "running",
              tenant,
              attributes:
                definition === "" ? {} : { "bsb.definition": definition },
            })
            .orThrow();
        }

        await s.asRole(owner);

        const idsOf = async (
          definitionId?: string | readonly string[],
        ): Promise<string[]> =>
          (
            await workflows.runs
              .list({
                tenant,
                ...(definitionId === undefined ? {} : { definitionId }),
              })
              .orThrow()
          )
            .map((run) => run.externalId)
            .toSorted();

        expect(await idsOf()).toEqual(["wrun_0", "wrun_1", "wrun_2", "wrun_3"]);
        expect(await idsOf(definitions[0])).toEqual(["wrun_0", "wrun_1"]);
        expect(await idsOf(definitions[1])).toEqual(["wrun_2"]);
        expect(await idsOf(definitions)).toEqual([
          "wrun_0",
          "wrun_1",
          "wrun_2",
        ]);
        expect(await idsOf(crypto.randomUUID())).toEqual([]);
        expect(await idsOf([])).toEqual([
          "wrun_0",
          "wrun_1",
          "wrun_2",
          "wrun_3",
        ]);
      } finally {
        await s.close();
      }
    });

    it("pages inboxes and templates and filters conversations by priority, sla and tag", async () => {
      const s = await BlockSession.open(pool);

      try {
        await s.install(["organizations", "queue", "streams", "tags", "inbox"]);

        const owner = await s.user("inbox-owner");
        const visitor = await s.user("inbox-visitor");
        const tenant = await s.organization(owner);
        const inbox = createInbox({ transport: sqlTransport(s.sql) });

        await s.asRole(owner);
        const boxes: string[] = [];

        for (const [name, channel] of [
          ["Help desk", "in_app"],
          ["Help email", "email"],
          ["Sales line", "whatsapp"],
          ["Sales chat", "in_app"],
          ["Billing", "email"],
        ] as const) {
          const created = await inbox.inboxes
            .create({
              tenant,
              name,
              channel,
              ...(channel === "in_app" ? {} : { address: `${name}@x.test` }),
              settings: { widget: true },
            })
            .orThrow();

          boxes.push(created.id);
        }

        for (const [name, channel, language] of [
          ["Welcome", "whatsapp", "en"],
          ["Welcome nl", "whatsapp", "nl"],
          ["Refund", "email", "en"],
          ["Shipping", "email", "en"],
          ["Goodbye", "slack", "en"],
        ] as const) {
          await inbox.templates
            .upsert({
              tenant,
              input: { name, channel, body: `${name} body`, language },
            })
            .orThrow();
        }

        await s.client.query("reset role");

        await s.client.query(
          `update better_supabase.inboxes a set created_at = now() + (r.n || ' minutes')::interval from (select id, row_number() over (order by random()) as n from better_supabase.inboxes) r where r.id = a.id`,
        );

        await s.client.query(
          `update better_supabase.inbox_message_templates a set created_at = now() + (r.n || ' minutes')::interval from (select id, row_number() over (order by random()) as n from better_supabase.inbox_message_templates) r where r.id = a.id`,
        );

        await s.asRole(owner);

        await testBlockList({
          name: "inbox.inboxes",
          target: {
            page: (options) =>
              inbox.inboxes.page({ ...options, organizationId: tenant }),
            count: (options) =>
              inbox.inboxes.count({ ...options, organizationId: tenant }),
            facets: (options) =>
              inbox.inboxes.facets({ ...options, organizationId: tenant }),
            get: (id) => inbox.inboxes.getInbox(id),
          },
          rows: 5,
          sorts: ["name", "createdAt"],
          facets: { channel: { in_app: 2, email: 2, whatsapp: 1 } },
          arrayFilter: { column: "channel", values: ["whatsapp", "email"] },
          search: "help",
        });

        await testBlockList({
          name: "inbox.templates",
          target: {
            page: (options) =>
              inbox.templates.page({ ...options, organizationId: tenant }),
            count: (options) =>
              inbox.templates.count({ ...options, organizationId: tenant }),
            facets: (options) =>
              inbox.templates.facets({ ...options, organizationId: tenant }),
            get: (id) => inbox.templates.getTemplate(id),
          },
          rows: 5,
          sorts: ["name", "createdAt"],
          facets: { channel: { whatsapp: 2, email: 2, slack: 1 } },
          arrayFilter: { column: "channel", values: ["slack", "email"] },
          search: "welcome",
        });

        await s.asRole(visitor);
        const conversations: string[] = [];

        for (const index of [0, 1, 2, 3, 4]) {
          const opened = await inbox.conversations
            .open({
              inboxId: boxes[0]!,
              input: { message: `Question ${String(index)}` },
            })
            .orThrow();

          conversations.push(opened.id);
        }

        // Priority, last inbound and first response differ per conversation:
        // 0 urgent and waiting two hours (breached), 1 high and waiting
        // forty minutes (due), 2 normal and waiting a minute (ok), 3 low and
        // answered (met), 4 normal and resolved (met).
        await s.client.query("reset role");

        const setup = [
          ["urgent", "2 hours", false, "open"],
          ["high", "40 minutes", false, "open"],
          ["normal", "1 minute", false, "open"],
          ["low", "3 hours", true, "open"],
          ["normal", "5 hours", false, "resolved"],
        ] as const;

        for (const [
          index,
          [priority, waited, answered, status],
        ] of setup.entries()) {
          await s.client.query(
            `update better_supabase.inbox_conversations
             set priority = $2, last_inbound_at = now() - $3::interval,
                 first_response_at = case when $4 then now() end, status = $5,
                 last_message_at = now() + ($6 || ' minutes')::interval,
                 created_at = now() + ($6 || ' minutes')::interval
             where id = $1`,
            [
              conversations[index],
              priority,
              waited,
              answered,
              status,
              String(index + 1),
            ],
          );
        }

        const [tag] = (
          await s.client.query<{ id: string }>(
            `insert into better_supabase.tags (tenant_id, kind, name, slug)
             values ($1, 'conversation', 'VIP', 'vip') returning id`,
            [tenant],
          )
        ).rows;

        for (const index of [0, 3]) {
          await s.client.query(
            `insert into better_supabase.taggings (tenant_id, tag_id, subject_type, subject_id)
             values ($1, $2, 'conversation', $3)`,
            [tenant, tag!.id, conversations[index]],
          );
        }

        await s.asRole(owner);

        const all = { status: ["all"] };

        const idsOf = async (
          filters: Readonly<Record<string, readonly string[]>>,
        ): Promise<number[]> =>
          (
            await inbox.conversations
              .page({ organizationId: tenant, filters: { ...all, ...filters } })
              .orThrow()
          ).items
            .map((item) => conversations.indexOf(item.id))
            .toSorted((a, b) => a - b);

        expect(await idsOf({ priority: ["urgent", "high"] })).toEqual([0, 1]);
        expect(await idsOf({ priority: ["low"] })).toEqual([3]);
        expect(await idsOf({ sla: ["breached"] })).toEqual([0]);
        expect(await idsOf({ sla: ["due"] })).toEqual([1]);
        expect(await idsOf({ sla: ["ok"] })).toEqual([2]);
        expect(await idsOf({ sla: ["met"] })).toEqual([3, 4]);
        expect(await idsOf({ sla: ["breached", "due"] })).toEqual([0, 1]);

        expect(await idsOf({ sla: ["breached"], slaMinutes: ["300"] })).toEqual(
          [],
        );

        expect(await idsOf({ sla: ["breached"], slaMinutes: ["20"] })).toEqual([
          0, 1,
        ]);

        expect(await idsOf({ tagId: [tag!.id] })).toEqual([0, 3]);
        expect(await idsOf({ tagId: [tag!.id], priority: ["low"] })).toEqual([
          3,
        ]);

        const facets = await inbox.conversations
          .facets({
            organizationId: tenant,
            filters: all,
            facets: ["priority", "sla"],
          })
          .orThrow();

        expect(
          Object.fromEntries(
            facets
              .find((facet) => facet.facet === "sla")!
              .values.map((entry) => [entry.value, entry.count.value]),
          ),
        ).toEqual({ breached: 1, due: 1, ok: 1, met: 2 });

        const refused = await inbox.conversations.page({
          organizationId: tenant,
          filters: { priority: ["critical"] },
        });

        expect(!refused.ok && refused.error.hint).toBe("INBOX_INVALID");

        const noMinutes = await inbox.conversations.page({
          organizationId: tenant,
          filters: { sla: ["due"], slaMinutes: ["soon"] },
        });

        expect(!noMinutes.ok && noMinutes.error.hint).toBe("INBOX_INVALID");
      } finally {
        await s.close();
      }
    });

    it("refuses a tag filter when the tags block is not installed", async () => {
      const s = await BlockSession.open(pool);

      try {
        await s.install(["organizations", "queue", "streams", "inbox"]);
        const owner = await s.user("inbox-notags");
        const tenant = await s.organization(owner);
        await s.asRole(owner);
        const inbox = createInbox({ transport: sqlTransport(s.sql) });

        const refused = await inbox.conversations.page({
          organizationId: tenant,
          filters: { tagId: [crypto.randomUUID()] },
        });

        expect(!refused.ok && refused.error.hint).toBe("INBOX_INVALID");
        expect(
          (await inbox.conversations.page({ organizationId: tenant }).orThrow())
            .items,
        ).toEqual([]);
      } finally {
        await s.close();
      }
    });
  },
);
