import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import {
  createTemplates,
  defineTemplateType,
  sqlTransport,
  type TemplateApplyCall,
} from "../../src/blocks/templates/index.ts";
import {
  type BuilderStartCall,
  createWorkflowBuilder,
  type WorkflowGraph,
} from "../../src/blocks/workflow-builder/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "outbox", "workflow-builder", "templates"];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const GRAPH: WorkflowGraph = {
  nodes: [
    { id: "start", kind: "trigger" },
    { id: "welcome", kind: "step", step: "email.send" },
  ],
  edges: [{ id: "e1", source: "start", target: "welcome" }],
};

describe.skipIf(!live)("templates module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("syncs starters, forks them, applies a fork and starts its workflows on the record", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(MODULES, {});
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });

      await s.service();
      const service = createTemplates({ transport: sqlTransport(s.sql) });
      const starter = {
        key: "launch",
        type: "project",
        name: "Launch",
        body: { tasks: ["Kickoff"] },
      };
      expect(await service.sync([starter]).orThrow()).toBe(1);
      expect(await service.sync([starter]).orThrow()).toBe(0);
      await createWorkflowBuilder({
        transport: sqlTransport(s.sql),
        steps: [{ name: "email.send", title: "Send an email" }],
      })
        .steps.sync()
        .orThrow();

      await s.asRole(owner);
      const created: TemplateApplyCall[] = [];
      const starts: BuilderStartCall[] = [];
      const builder = createWorkflowBuilder({
        transport: sqlTransport(s.sql),
        start: async (call) => {
          starts.push(call);
          return `wrun_${String(starts.length)}`;
        },
      });
      const templates = createTemplates({
        transport: sqlTransport(s.sql),
        workflows: builder,
        types: {
          project: defineTemplateType({
            apply: (call) => {
              created.push(call);
              return {
                subject: { type: "project", id: `p${String(created.length)}` },
              };
            },
          }),
        },
      });

      const [system] = await templates.list(null).orThrow();
      expect(system).toMatchObject({
        scope: "system",
        key: "launch",
        organizationId: undefined,
        publishedVersion: 1,
      });
      expect(
        await templates
          .save({ organizationId: null, type: "project", name: "Nope" })
          .then(hint),
      ).toBe("TEMPLATE_FORBIDDEN");

      const fork = await templates.fork(system!.id, tenant).orThrow();
      expect(fork).toMatchObject({
        scope: "tenant",
        organizationId: tenant,
        forkedFrom: system!.id,
        forkedFromVersion: 1,
        publishedVersion: 1,
        behind: false,
      });

      await s.service();
      expect(
        await service
          .sync([{ ...starter, body: { tasks: ["Kickoff", "Retro"] } }])
          .orThrow(),
      ).toBe(1);
      await s.asRole(owner);
      expect((await templates.get(fork.id).orThrow())?.behind).toBe(true);

      const draft = await templates.versions
        .save(fork.id, { tasks: ["Kickoff", "Plan"] })
        .orThrow();
      expect(draft).toMatchObject({ version: 2, publishedAt: undefined });
      expect(await templates.versions.publish(fork.id).orThrow()).toMatchObject(
        {
          version: 2,
        },
      );
      expect(await templates.versions.publish(fork.id).then(hint)).toBe(
        "TEMPLATE_NO_DRAFT",
      );
      expect(await templates.setDefault(fork.id).orThrow()).toBe(true);

      const definition = await builder.definitions
        .save({
          tenant,
          slug: "kickoff",
          name: "Kickoff",
          subjectTypes: ["project"],
        })
        .orThrow();
      const version = await builder.versions
        .save(definition.id, GRAPH, {
          inputSchema: {
            type: "object",
            required: ["owner"],
            properties: { owner: { type: "string" } },
          },
        })
        .orThrow();
      expect(version.inputSchema).toMatchObject({ required: ["owner"] });
      await builder.versions.publish(version.id).orThrow();
      expect(
        await templates.workflows
          .attach({ template: fork.id, definition: definition.id })
          .then(hint),
      ).toBe("TEMPLATE_WORKFLOW_INPUT_INVALID");
      await templates.workflows
        .attach({
          template: fork.id,
          definition: definition.id,
          inputs: { owner: owner.id },
        })
        .orThrow();

      await s.asRole(outsider);
      expect(await templates.apply(fork.id, { into: tenant }).then(hint)).toBe(
        "TEMPLATE_FORBIDDEN",
      );

      await s.asRole(member);
      expect(
        await templates
          .save({
            id: fork.id,
            organizationId: tenant,
            type: "project",
            name: "Mine",
          })
          .then(hint),
      ).toBe("TEMPLATE_FORBIDDEN");
      const applied = await templates
        .apply(fork.id, { into: tenant })
        .orThrow();
      expect(created[0]?.body).toEqual({ tasks: ["Kickoff", "Plan"] });
      expect(applied.subject).toEqual({ type: "project", id: "p1" });
      expect(applied.runs).toMatchObject([
        { definition: definition.id, error: { hint: "WORKFLOW_NOT_FOUND" } },
      ]);
      expect(starts).toHaveLength(0);

      await s.asRole(owner);
      const second = await templates.apply(fork.id, { into: tenant }).orThrow();
      expect(second.subject).toEqual({ type: "project", id: "p2" });
      expect(second.runs).toEqual([
        { definition: definition.id, runId: "wrun_1" },
      ]);
      expect(starts[0]).toMatchObject({
        input: { owner: owner.id },
        tenant,
        subject: { type: "project", id: "p2" },
        idempotencyKey: `template-application:${second.application.id}:${definition.id}`,
      });
      expect(
        await templates.applications
          .list(tenant, { subject: { type: "project", id: "p1" } })
          .orThrow(),
      ).toMatchObject([{ id: applied.application.id, appliedBy: member.id }]);

      await s.service();
      expect(
        await s.rows<{ type: string }>(
          "select type from better_supabase.outbox_events where type like '%template.%' order by position",
        ),
      ).toEqual(
        expect.arrayContaining([
          { type: expect.stringMatching(/template\.published$/) },
          { type: expect.stringMatching(/template\.applied$/) },
        ]),
      );
    } finally {
      await s.close();
    }
  });

  it("checks workflow inputs against the whole input schema with jsonb-schemas", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install([...MODULES, "jsonb-schemas"], {});
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      await s.service();
      await createWorkflowBuilder({
        transport: sqlTransport(s.sql),
        steps: [{ name: "email.send", title: "Send an email" }],
      })
        .steps.sync()
        .orThrow();

      await s.asRole(owner);
      const builder = createWorkflowBuilder({ transport: sqlTransport(s.sql) });
      const templates = createTemplates({ transport: sqlTransport(s.sql) });
      const template = await templates
        .save({ organizationId: tenant, type: "project", name: "Launch" })
        .orThrow();
      const definition = await builder.definitions
        .save({ tenant, slug: "kickoff", name: "Kickoff" })
        .orThrow();
      const version = await builder.versions
        .save(definition.id, GRAPH, {
          inputSchema: {
            type: "object",
            required: ["owner"],
            properties: { owner: { type: "string" } },
          },
        })
        .orThrow();
      await builder.versions.publish(version.id).orThrow();
      const attach = (inputs: Record<string, unknown>) =>
        templates.workflows.attach({
          template: template.id,
          definition: definition.id,
          inputs,
        });
      expect(await attach({ owner: 3 }).then(hint)).toBe(
        "TEMPLATE_WORKFLOW_INPUT_INVALID",
      );
      expect(await attach({ owner: "ada" }).then(hint)).toBe("ok");
      expect(
        await templates.workflows.list(template.id).orThrow(),
      ).toMatchObject([
        { definition: definition.id, inputs: { owner: "ada" } },
      ]);
      expect(
        await templates.workflows.detach(template.id, definition.id).orThrow(),
      ).toBe(true);
    } finally {
      await s.close();
    }
  });
});
