import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { WorkflowGraph } from "../../src/blocks/workflow-builder/index.ts";
import type { AutomationRef } from "../../src/core/contracts/authorization-hooks.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import {
  createWorkflowBuilder,
  sqlTransport,
} from "../../src/blocks/workflow-builder/index.ts";
import { moduleProvider } from "../fixtures/authorization-provider.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const CRM_GRAPH: WorkflowGraph = {
  nodes: [
    { id: "start", kind: "trigger" },
    { id: "lookup", kind: "step", step: "crm.lookup" },
  ],
  edges: [{ id: "e1", source: "start", target: "lookup" }],
};

const EMAIL_GRAPH: WorkflowGraph = {
  nodes: [
    { id: "start", kind: "trigger" },
    { id: "send", kind: "step", step: "email.send" },
  ],
  edges: [{ id: "e1", source: "start", target: "send" }],
};

// Admins edit and publish workflows but don't hold crm.read, which the
// provider's operations table says the crm.lookup step needs.
const LAYOUT: ModuleLayout = {
  modules: {
    access: {
      roles: {
        owner: ["*"],
        admin: ["organization.read", "members.read", "workflow.*"],
        member: ["organization.read", "members.read"],
      },
    },
  },
  accessProvider: {
    ...moduleProvider,
    operations: { "workflow.node.crm.lookup": { permission: "crm.read" } },
  },
};

const STEPS = [
  { name: "crm.lookup", title: "Look up a contact" },
  { name: "email.send", title: "Send an email" },
];

describe.skipIf(!live)("workflow-builder publisher rights", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  async function setUp(s: BlockSession) {
    await s.install(["organizations", "workflow-builder"], LAYOUT);
    const publisher = await s.user("publisher");
    const owner = await s.user("owner");
    const admin = await s.user("admin");
    const tenant = await s.organization(owner, { owner: publisher, admin });
    await s.service();
    await createWorkflowBuilder({
      transport: sqlTransport(s.sql),
      steps: STEPS,
    })
      .steps.sync()
      .orThrow();

    return { publisher, owner, admin, tenant };
  }

  it("refuses a publisher who lacks a permission a step needs", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { admin, tenant } = await setUp(s);
      await s.asRole(admin);
      const builder = createWorkflowBuilder({ transport: sqlTransport(s.sql) });

      const definition = await builder.definitions
        .save({ tenant, slug: "crm", name: "CRM" })
        .orThrow();

      const draft = await builder.versions
        .save(definition.id, CRM_GRAPH)
        .orThrow();

      const refused = await builder.versions.publish(draft.id);
      expect(!refused.ok && refused.error.hint).toBe(
        "WORKFLOW_PUBLISHER_FORBIDDEN",
      );
      expect(!refused.ok && refused.error.message).toContain("crm.read");
      expect(!refused.ok && refused.error).toMatchObject({
        kind: "forbidden",
        permissions: ["crm.read"],
      });
      expect(await builder.versions.get(draft.id).orThrow()).toMatchObject({
        status: "draft",
        publishedBy: undefined,
        permissions: [],
      });

      await builder.versions.save(definition.id, EMAIL_GRAPH).orThrow();
      expect(await builder.versions.publish(draft.id).orThrow()).toMatchObject({
        status: "published",
        publishedBy: admin.id,
        owner: "user",
        permissions: ["workflow.run"],
      });
    } finally {
      await s.close();
    }
  });

  it("fails a step once the publisher is demoted, removed or deleted, and writes nothing", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { publisher, tenant } = await setUp(s);
      await s.asRole(publisher);

      const asPublisher = createWorkflowBuilder({
        transport: sqlTransport(s.sql),
      });

      const definition = await asPublisher.definitions
        .save({ tenant, slug: "crm", name: "CRM" })
        .orThrow();

      const draft = await asPublisher.versions
        .save(definition.id, CRM_GRAPH)
        .orThrow();

      const version = await asPublisher.versions.publish(draft.id).orThrow();
      expect(version).toMatchObject({
        publishedBy: publisher.id,
        owner: "user",
        permissions: ["crm.read"],
      });

      await s.service();
      const refs: AutomationRef[] = [];

      const service = createWorkflowBuilder({
        transport: sqlTransport(s.sql),
        authorization: {
          automation: {
            runAs: (automation) => {
              refs.push(automation);

              return automation.publisher === null
                ? null
                : {
                    sub: automation.publisher,
                    role: "authenticated",
                    permissions: automation.permissions,
                  };
            },
          },
        },
      });

      const writes: string[] = [];

      const step = async () => {
        const claims = await service.versions.runAs(version.id).orThrow();
        writes.push(String(claims["sub"]));
        await service.nodeRuns
          .record({ run: "wrun_x", node: "lookup", status: "completed" })
          .orThrow();
      };

      expect(await service.versions.runAs(version.id).orThrow()).toEqual({
        sub: publisher.id,
        role: "authenticated",
        permissions: ["crm.read"],
      });
      expect(refs).toEqual([
        { publisher: publisher.id, tenant, permissions: ["crm.read"] },
      ]);

      await s.client.query(
        "update better_supabase.memberships set role = 'member' where organization_id = $1 and user_id = $2",
        [tenant, publisher.id],
      );
      const demoted = await service.versions.runAs(version.id);
      expect(!demoted.ok && demoted.error.hint).toBe(
        "WORKFLOW_PUBLISHER_REVOKED",
      );
      expect(!demoted.ok && demoted.error.message).toContain("crm.read");
      await expect(step()).rejects.toThrow("no longer holds");

      await s.client.query(
        "delete from better_supabase.memberships where organization_id = $1 and user_id = $2",
        [tenant, publisher.id],
      );
      await expect(step()).rejects.toThrow("no longer holds");

      await s.client.query("delete from auth.users where id = $1", [
        publisher.id,
      ]);
      await expect(step()).rejects.toThrow("no longer exists");

      expect(refs).toHaveLength(1);
      expect(writes).toEqual([]);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.workflow_node_runs)",
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });

  it("runs an organization-owned version only as the app's service principal", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { tenant } = await setUp(s);
      const plain = createWorkflowBuilder({ transport: sqlTransport(s.sql) });

      const definition = await plain.definitions
        .save({ tenant, slug: "nightly", name: "Nightly" })
        .orThrow();

      const draft = await plain.versions
        .save(definition.id, CRM_GRAPH)
        .orThrow();

      expect(await plain.versions.publish(draft.id).orThrow()).toMatchObject({
        publishedBy: undefined,
        owner: "organization",
        permissions: ["crm.read"],
      });

      const missing = await plain.versions.runAs(draft.id);
      expect(!missing.ok && missing.error.hint).toBe(
        "WORKFLOW_PUBLISHER_REVOKED",
      );
      let principal: Readonly<Record<string, unknown>> | null = null;

      const service = createWorkflowBuilder({
        transport: sqlTransport(s.sql),
        authorization: { automation: { runAs: () => principal } },
      });

      const refused = await service.versions.runAs(draft.id);
      expect(!refused.ok && refused.error.message).toContain(
        "no service principal",
      );
      principal = { sub: "svc_nightly", role: "authenticated" };
      expect(await service.versions.runAs(draft.id).orThrow()).toEqual(
        principal,
      );

      const next = await plain.versions
        .save(definition.id, EMAIL_GRAPH)
        .orThrow();

      const unpublished = await service.versions.runAs(next.id);
      expect(!unpublished.ok && unpublished.error.hint).toBe(
        "WORKFLOW_NOT_PUBLISHED",
      );
      await s.client.query(
        "update better_supabase.workflow_versions set owner_kind = null where id = $1",
        [draft.id],
      );
      const legacy = await service.versions.runAs(draft.id);
      expect(!legacy.ok && legacy.error.message).toContain("publish it again");
    } finally {
      await s.close();
    }
  });
});
