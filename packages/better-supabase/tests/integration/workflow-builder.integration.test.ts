import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { CredentialProvider } from "../../src/credentials/provider.ts";

import {
  type BuilderStartCall,
  createBuilder,
  sqlTransport,
  type WorkflowGraph,
} from "../../src/blocks/workflow-builder/index.ts";
import { createWorkflows } from "../../src/blocks/workflows/index.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const GRAPH: WorkflowGraph = {
  nodes: [
    { id: "start", kind: "trigger" },
    {
      id: "lookup",
      kind: "step",
      step: "crm.lookup",
      config: { field: "plan" },
    },
    {
      id: "isPro",
      kind: "condition",
      config: { path: "results.lookup.plan", op: "equals", value: "pro" },
    },
    { id: "welcome", kind: "step", step: "email.send" },
  ],
  edges: [
    { id: "e1", source: "start", target: "lookup" },
    { id: "e2", source: "lookup", target: "isPro" },
    { id: "e3", source: "isPro", target: "welcome", branch: "true" },
  ],
};

const STEPS = [
  { name: "crm.lookup", title: "Look up a contact", credentialKind: "crm" },
  { name: "email.send", title: "Send an email" },
];

describe.skipIf(!live)("workflow-builder module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("saves drafts, publishes validated versions and starts runs of them", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "workflow-builder"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });

      await s.service();
      const starts: BuilderStartCall[] = [];
      const service = createBuilder({
        transport: sqlTransport(s.sql),
        steps: STEPS,
        start: async (call) => {
          starts.push(call);
          return `wrun_${String(starts.length)}`;
        },
      });
      expect(await service.steps.sync().orThrow()).toBe(2);

      await s.asRole(member);
      const asMember = createBuilder({ transport: sqlTransport(s.sql) });
      expect(
        await asMember.definitions
          .save({ tenant, slug: "onboard", name: "Onboard" })
          .then((result) => !result.ok && result.error.hint),
      ).toBe("WORKFLOW_FORBIDDEN");

      await s.asRole(owner);
      const compiled: WorkflowGraph[] = [];
      const builder = createBuilder({
        transport: sqlTransport(s.sql),
        compile: (graph) => {
          compiled.push(graph);
          return { engine: "test", nodes: graph.nodes.length };
        },
        start: async (call) => {
          starts.push(call);
          return `wrun_${String(starts.length)}`;
        },
      });
      expect(
        (await builder.steps.list().orThrow()).map((step) => step.name),
      ).toEqual(["crm.lookup", "email.send"]);
      const definition = await builder.definitions
        .save({ tenant, slug: "onboard", name: "Onboard" })
        .orThrow();
      expect(definition).toMatchObject({
        tenant,
        slug: "onboard",
        createdBy: owner.id,
      });

      expect(
        await builder
          .run({ definition: definition.id })
          .then((result) => !result.ok && result.error.hint),
      ).toBe("WORKFLOW_NOT_PUBLISHED");

      const broken = await builder.versions
        .save(definition.id, {
          nodes: [
            { id: "start", kind: "trigger" },
            { id: "x", kind: "step", step: "nope" },
          ],
          edges: [{ id: "e", source: "start", target: "x" }],
        })
        .orThrow();
      expect(broken).toMatchObject({ version: 1, status: "draft" });
      const refused = await builder.versions.publish(broken.id);
      expect(!refused.ok && refused.error.hint).toBe("WORKFLOW_GRAPH_INVALID");
      expect(!refused.ok && refused.error.message).toContain(
        "not in the step library",
      );

      const draft = await builder.versions.save(definition.id, GRAPH).orThrow();
      expect(draft.id).toBe(broken.id);
      const v1 = await builder.versions.publish(draft.id).orThrow();
      expect(v1).toMatchObject({ version: 1, status: "published" });
      expect(v1).not.toHaveProperty("compiled");
      expect(compiled).toHaveLength(2);
      expect(
        await s.hint(
          `better_supabase.publish_workflow_version($1, '{"source": "x"}'::jsonb)`,
          [v1.id],
        ),
      ).toBe("WORKFLOW_COMPILED_FORBIDDEN");
      await s.service();
      expect(
        await s.value<{ compiled: unknown }>(
          `better_supabase.publish_workflow_version($1, '{"engine": "test"}'::jsonb)`,
          [v1.id],
        ),
      ).toMatchObject({ compiled: { engine: "test" } });
      await s.asRole(owner);

      const next = await builder.versions
        .save(definition.id, {
          ...GRAPH,
          nodes: [
            ...GRAPH.nodes,
            { id: "wait", kind: "sleep", config: { duration: "1h" } },
          ],
          edges: [
            ...GRAPH.edges,
            { id: "e4", source: "welcome", target: "wait" },
          ],
        })
        .orThrow();
      expect(next).toMatchObject({ version: 2, status: "draft" });
      expect(await builder.versions.diff(v1.id, next.id).orThrow()).toEqual({
        nodes: { added: ["wait"], removed: [], changed: [] },
        edges: { added: ["welcome->wait"], removed: [] },
      });
      await builder.versions.publish(next.id).orThrow();
      expect(
        (await builder.versions.list(definition.id).orThrow()).map((v) => [
          v.version,
          v.status,
        ]),
      ).toEqual([
        [2, "published"],
        [1, "archived"],
      ]);
      expect(await builder.definitions.list(tenant).orThrow()).toMatchObject([
        { slug: "onboard", published: 2, draft: false },
      ]);

      const runId = await builder
        .run({
          definition: definition.id,
          input: { email: "a@example.test" },
          idempotencyKey: "k1",
        })
        .orThrow();
      expect(runId).toBe("wrun_1");
      expect(starts[0]).toMatchObject({
        tenant,
        input: { email: "a@example.test" },
        idempotencyKey: "k1",
        version: { version: 2, status: "published" },
      });
      expect(starts[0]?.version.graph?.nodes).toHaveLength(5);

      await s.asRole(member);
      expect(await asMember.definitions.list(tenant).orThrow()).toEqual([]);
      await s.asRole(outsider);
      expect(
        await asMember.definitions.get(definition.id).orThrow(),
      ).toBeUndefined();
      expect(await asMember.versions.list(definition.id).orThrow()).toEqual([]);
    } finally {
      await s.close();
    }
  });

  it("runs webhook and event triggers, and syncs schedule triggers", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "workflow-builder"]);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner, {});
      await s.service();
      const starts: BuilderStartCall[] = [];
      const start = async (call: BuilderStartCall): Promise<string> => {
        starts.push(call);
        return `wrun_${String(starts.length)}`;
      };
      const service = createBuilder({
        transport: sqlTransport(s.sql),
        steps: STEPS,
        start,
      });
      await service.steps.sync().orThrow();

      await s.asRole(owner);
      const builder = createBuilder({ transport: sqlTransport(s.sql), start });
      const definition = await builder.definitions
        .save({ tenant, slug: "hooked", name: "Hooked" })
        .orThrow();
      const draft = await builder.versions.save(definition.id, GRAPH).orThrow();
      await builder.versions.publish(draft.id).orThrow();

      const webhook = await builder.triggers
        .save({ definition: definition.id, kind: "webhook" })
        .orThrow();
      const token = await builder.triggers.rotateToken(webhook.id).orThrow();
      expect(token).toMatch(/^wfh_[0-9a-f]{48}$/);
      const event = await builder.triggers
        .save({
          definition: definition.id,
          kind: "event",
          config: { type: "contact.created" },
        })
        .orThrow();
      const schedule = await builder.triggers
        .save({
          definition: definition.id,
          kind: "schedule",
          config: { cron: "@daily", input: { daily: true } },
        })
        .orThrow();
      expect(
        (await builder.triggers.list(definition.id).orThrow()).map(
          (t) => t.kind,
        ),
      ).toEqual(["webhook", "event", "schedule"]);
      const manual = await builder.triggers
        .save({ definition: definition.id, kind: "manual" })
        .orThrow();
      expect(
        await builder.triggers
          .rotateToken(manual.id)
          .then((result) => !result.ok && result.error.hint),
      ).toBe("WORKFLOW_TRIGGER_KIND");

      await s.service();
      const missing = await service.triggers.webhook(
        new Request("https://app.test/api/hooks/wfh_nope", { method: "POST" }),
      );
      expect(missing.status).toBe(404);
      const hooked = await service.triggers.webhook(
        new Request(`https://app.test/api/hooks/${token}`, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "idempotency-key": "abc",
          },
          body: JSON.stringify({ id: 7 }),
        }),
      );
      expect(hooked.status).toBe(202);
      expect(await hooked.json()).toEqual({ runId: "wrun_1" });
      expect(starts[0]).toMatchObject({
        input: { id: 7 },
        idempotencyKey: `webhook:${webhook.id}:abc`,
        trigger: { id: webhook.id },
      });
      const bearer = await service.triggers.webhook(
        new Request("https://app.test/api/hooks", {
          method: "POST",
          headers: { authorization: `Bearer ${token}` },
        }),
      );
      expect(bearer.status).toBe(202);
      expect(
        (
          await service.triggers.webhook(
            new Request(`https://app.test/${token}`),
          )
        ).status,
      ).toBe(405);

      expect(
        await service.triggers
          .onEvent({
            id: "evt_1",
            type: "contact.created",
            payload: { id: 1 },
            tenant,
          })
          .orThrow(),
      ).toEqual(["wrun_3"]);
      expect(starts[2]).toMatchObject({
        idempotencyKey: `event:${event.id}:evt_1`,
      });
      expect(
        await service.triggers
          .onEvent({ id: "evt_2", type: "other", tenant })
          .orThrow(),
      ).toEqual([]);

      const synced = await service.triggers
        .syncSchedule(schedule, tenant)
        .orThrow();
      expect(synced).toMatchObject({
        name: `builder-trigger:${schedule.id}`,
        workflow: `builder:${definition.id}`,
        cron: "@daily",
      });
      await s.client.query(
        "update better_supabase.workflow_schedules set next_run_at = now() - interval '1 minute' where id = $1",
        [synced.id],
      );
      const workflows = createWorkflows({ transport: sqlTransport(s.sql) });
      expect(
        await workflows.schedules
          .tick({ start: service.triggers.starter() })
          .orThrow(),
      ).toMatchObject({ started: 1, failed: [] });
      expect(starts[3]).toMatchObject({ input: { daily: true } });
      expect(starts[3]?.idempotencyKey).toMatch(
        new RegExp(`^schedule:${synced.id}:`),
      );

      await s.asRole(owner);
      expect(await builder.triggers.remove(webhook.id).orThrow()).toBe(true);
      await s.service();
      expect(
        (
          await service.triggers.webhook(
            new Request(`https://app.test/api/hooks/${token}`, {
              method: "POST",
            }),
          )
        ).status,
      ).toBe(404);
    } finally {
      await s.close();
    }
  });

  it("resolves and revokes credentials through their provider", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "workflow-builder"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });
      const secrets = new Map<string, string>();
      const revoked: string[] = [];
      const provider: CredentialProvider & {
        set(ref: { secret?: unknown }, value: string): AsyncResult<void>;
      } = {
        apiVersion: 1,
        name: "memory",
        capabilities: () => ({
          userSubjects: false,
          authorization: false,
          revoke: true,
          inbound: false,
        }),
        getToken: (ref, options) =>
          AsyncResult.ok({
            token: secrets.get(String(ref["secret"])) ?? "",
            headers: { "x-scopes": (options.scopes ?? []).join(" ") },
          }),
        revoke: (ref) => {
          revoked.push(String(ref["secret"]));
          return AsyncResult.ok(secrets.delete(String(ref["secret"])));
        },
        set: (ref, value) => {
          secrets.set(String(ref.secret), value);
          return AsyncResult.ok(undefined);
        },
      };

      await s.asRole(member);
      const asMember = createBuilder({
        transport: sqlTransport(s.sql),
        credentials: provider,
      });
      expect(
        await asMember.credentials
          .create({
            tenant,
            kind: "crm",
            name: "CRM",
            ref: { provider: "memory", secret: "crm", tenant },
          })
          .then((result) => !result.ok && result.error.hint),
      ).toBe("WORKFLOW_FORBIDDEN");

      await s.asRole(owner);
      const builder = createBuilder({
        transport: sqlTransport(s.sql),
        credentials: provider,
      });
      const credential = await builder.credentials
        .create({
          tenant,
          kind: "crm",
          name: "CRM",
          ref: { provider: "memory", secret: "crm", tenant },
          scopes: ["contacts.read"],
          secret: "s3cret",
        })
        .orThrow();
      expect(credential).toMatchObject({
        kind: "crm",
        scopes: ["contacts.read"],
        ref: { provider: "memory" },
      });
      expect(JSON.stringify(credential)).not.toContain("s3cret");
      expect(
        await builder.credentials
          .resolve(credential.id)
          .then((result) => !result.ok && result.error.kind),
      ).toBeTruthy();

      await s.service();
      const service = createBuilder({
        transport: sqlTransport(s.sql),
        credentials: provider,
      });
      expect(
        await service.credentials.resolve(credential.id).orThrow(),
      ).toMatchObject({
        token: "s3cret",
        headers: { "x-scopes": "contacts.read" },
      });
      expect(
        await service.credentials
          .authorize(credential.id, { redirectUri: "https://app.test/cb" })
          .then((result) => !result.ok && result.error.kind),
      ).toBe("unsupported");

      await s.asRole(member);
      expect(
        (await asMember.credentials.list(tenant).orThrow()).map((c) => c.name),
      ).toEqual([]);
      await s.asRole(owner);
      expect(
        (await builder.credentials.list(tenant).orThrow()).map((c) => c.name),
      ).toEqual(["CRM"]);
      expect(await builder.credentials.revoke(credential.id).orThrow()).toBe(
        true,
      );
      expect(revoked).toEqual(["crm"]);
      expect(secrets.size).toBe(0);
      expect(await builder.credentials.revoke(credential.id).orThrow()).toBe(
        false,
      );
    } finally {
      await s.close();
    }
  });

  it("records node runs on the run's topic and fires failed and slow alerts once", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "workflow-builder"]);
      const owner = await s.user("owner");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, {});
      await s.asRole(owner);
      const builder = createBuilder({ transport: sqlTransport(s.sql) });
      const definition = await builder.definitions
        .save({ tenant, slug: "alerted", name: "Alerted" })
        .orThrow();
      const failed = await builder.alerts
        .save({
          definition: definition.id,
          onEvent: "failed",
          channel: { type: "email", to: "ops@example.test" },
        })
        .orThrow();
      const slow = await builder.alerts
        .save({ definition: definition.id, onEvent: "slow", threshold: 60 })
        .orThrow();
      expect(slow.threshold).toBe(60);
      expect(
        (await builder.alerts.list(definition.id).orThrow()).map(
          (a) => a.onEvent,
        ),
      ).toEqual(["failed", "slow"]);

      await s.service();
      const workflows = createWorkflows({ transport: sqlTransport(s.sql) });
      const service = createBuilder({ transport: sqlTransport(s.sql) });
      const record = (externalId: string, status: "running" | "failed") =>
        workflows.runs
          .record({
            engine: "workflow-sdk",
            externalId,
            definition: "dynamic",
            status,
            tenant,
            attributes: { "bs.definition": definition.id, "bs.version": "1" },
          })
          .orThrow();
      const runId = await record("wrun_a", "running");
      expect(
        await service.nodeRuns
          .record({
            run: "wrun_a",
            node: "lookup",
            status: "running",
            attempt: 1,
          })
          .orThrow(),
      ).toBe(true);
      await service.nodeRuns
        .record({
          run: runId,
          node: "lookup",
          status: "completed",
          attempt: 1,
          output: { plan: "pro" },
        })
        .orThrow();
      await service.nodeRuns
        .record({
          run: "wrun_a",
          node: "welcome",
          status: "failed",
          attempt: 2,
          error: "SMTP down",
        })
        .orThrow();
      expect(
        await service.nodeRuns
          .record({ run: "wrun_missing", node: "x", status: "running" })
          .orThrow(),
      ).toBe(false);

      await s.asRole(owner);
      const nodes = await builder.nodeRuns.list("wrun_a").orThrow();
      expect(
        nodes.map((node) => [node.node, node.status, node.attempts]),
      ).toEqual([
        ["lookup", "completed", 1],
        ["welcome", "failed", 2],
      ]);
      expect(nodes[0]?.output).toEqual({ plan: "pro" });
      expect(nodes[0]?.endedAt).toBeDefined();
      await s.asRole(outsider);
      expect(await builder.nodeRuns.list("wrun_a").orThrow()).toEqual([]);

      await s.service();
      await record("wrun_a", "failed");
      await record("wrun_a", "failed");
      const alerts = await s.rows<{
        type: string;
        payload: { alertId: string; runId: string };
      }>(
        "select type, payload from better_supabase.outbox_events where type = 'workflow_alert.triggered'",
      );
      expect(alerts).toEqual([
        {
          type: "workflow_alert.triggered",
          payload: expect.objectContaining({ alertId: failed.id, runId }),
        },
      ]);

      await record("wrun_b", "running");
      expect(await service.alerts.check().orThrow()).toBe(0);
      await s.client.query(
        "update better_supabase.workflow_runs set created_at = now() - interval '2 minutes' where external_id = 'wrun_b'",
      );
      expect(await service.alerts.check().orThrow()).toBe(1);
      expect(await service.alerts.check().orThrow()).toBe(0);

      await s.asRole(owner);
      expect(await builder.alerts.remove(slow.id).orThrow()).toBe(true);
      expect(await builder.definitions.remove(definition.id).orThrow()).toBe(
        true,
      );
      expect(await builder.definitions.list(tenant).orThrow()).toEqual([]);
    } finally {
      await s.close();
    }
  });
});
