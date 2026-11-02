import { describe, expect, it, vi } from "vitest";

import type { BuilderStartCall } from "../../../src/blocks/workflow-editor/workflow-editor.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";
import type { CredentialProvider } from "../../../src/credentials/provider.ts";

import { triggerOf } from "../../../src/blocks/workflow-editor/rows.ts";
import { createWorkflowEditor } from "../../../src/blocks/workflow-editor/workflow-editor.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { GRAPH } from "./fixture.ts";

const AT = "2026-01-01T00:00:00Z";

const DEFINITION = {
  id: "d1",
  tenant: "t1",
  slug: "onboard",
  name: "Onboard",
  description: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const VERSION = {
  id: "v1",
  definition: "d1",
  version: 1,
  status: "draft",
  createdBy: "u1",
  createdAt: AT,
  publishedAt: null,
  graph: GRAPH,
  compiled: null,
};

const BARE_VERSION = {
  id: "v2",
  definition: "d1",
  version: 2,
  status: "draft",
  createdBy: "u1",
  createdAt: AT,
  publishedAt: null,
};

const TRIGGER = {
  id: "tr1",
  definition: "d1",
  kind: "webhook",
  config: {},
  enabled: true,
  createdAt: AT,
  updatedAt: AT,
};

const CREDENTIAL = {
  id: "c1",
  tenant: "t1",
  kind: "crm",
  name: "CRM",
  ref: { provider: "memory", secret: "crm", tenant: "t1" },
  scopes: ["read"],
  createdBy: "u1",
  createdAt: AT,
};

type Reply = (args: Readonly<Record<string, unknown>>) => unknown;

function fake(replies: Record<string, Reply>) {
  const calls: { fn: string; args: Readonly<Record<string, unknown>> }[] = [];

  const transport: BlockTransport = {
    call: vi.fn(async (_schema, fn, args) => {
      calls.push({ fn, args });
      const reply = replies[fn];

      if (reply === undefined) {
        throw new Error(`unexpected ${fn}`);
      }

      return reply(args);
    }),
  };

  return { transport, calls };
}

const published = { ...VERSION, status: "published", publishedAt: AT };
const target = () => ({ definition: DEFINITION, version: published });

function recordingStarter() {
  const starts: BuilderStartCall[] = [];

  return {
    starts,
    start: async (call: BuilderStartCall) => {
      starts.push(call);

      return "wrun_1";
    },
  };
}

describe("workflow editor definitions and versions", () => {
  it("returns nothing for a definition that does not exist", async () => {
    const { transport } = fake({ workflow_definition_get: () => null });
    const builder = createWorkflowEditor({ transport });

    expect(await builder.definitions.get("nope").orThrow()).toBeUndefined();
  });

  it("saves a draft with an input schema", async () => {
    const { transport, calls } = fake({ save_workflow_draft: () => VERSION });
    const builder = createWorkflowEditor({ transport });

    await builder.versions
      .upsert({
        definition: "d1",
        graph: GRAPH,
        inputSchema: { type: "object" },
      })
      .orThrow();
    await builder.versions.upsert({ definition: "d1", graph: GRAPH }).orThrow();

    expect(calls[0]?.args["input_schema"]).toEqual({ type: "object" });
    expect(calls[1]?.args).not.toHaveProperty("input_schema");
  });

  it("compiles an empty graph for a version saved without one", async () => {
    const { transport } = fake({
      workflow_version_get: () => BARE_VERSION,
      publish_workflow_version: () => ({
        ...BARE_VERSION,
        status: "published",
      }),
    });

    const compile = vi.fn(async () => ({ ok: true }));
    const builder = createWorkflowEditor({ transport, compile });

    await builder.versions.publish({ version: "v2" }).orThrow();
    expect(compile).toHaveBeenCalledWith({ nodes: [], edges: [] });
  });

  it("compiles to nothing when the compiler answers undefined", async () => {
    const { transport, calls } = fake({
      workflow_version_get: () => VERSION,
      publish_workflow_version: () => published,
    });

    const builder = createWorkflowEditor({
      transport,
      service: transport,
      compile: async () => undefined,
    });

    await builder.versions.publish({ version: "v1" }).orThrow();
    expect(
      calls.filter((c) => c.fn === "publish_workflow_version"),
    ).toHaveLength(1);
  });

  it("reports a compile failure that is not an Error", async () => {
    const { transport } = fake({ workflow_version_get: () => VERSION });

    const builder = createWorkflowEditor({
      transport,
      compile: () => Promise.reject("bad graph"),
    });

    const result = await builder.versions.publish({ version: "v1" });

    expect(!result.ok && result.error.message).toBe("bad graph");
  });

  it("diffs versions without graphs and stops when the second lookup fails", async () => {
    const { transport } = fake({
      workflow_version_get: (args) => {
        if (args["version"] === "boom") {
          throw new Error("down");
        }

        return BARE_VERSION;
      },
    });

    const builder = createWorkflowEditor({ transport });

    const diff = await builder.versions
      .diff({ from: "v2", to: "v2" })
      .orThrow();

    expect(diff).toEqual(expect.objectContaining({ nodes: expect.anything() }));

    const failed = await builder.versions.diff({ from: "v2", to: "boom" });

    expect(failed.ok).toBe(false);
  });
});

describe("workflow editor runs", () => {
  it("starts a webhook trigger's node and takes the idempotency key header", async () => {
    const { transport } = fake({
      workflow_webhook_target: () => ({
        trigger: { ...TRIGGER, config: { node: "start" } },
      }),
      workflow_start_target: target,
    });

    const { start, starts } = recordingStarter();
    const builder = createWorkflowEditor({ transport, start });

    const res = await builder.triggers.webhook(
      new Request("https://a.test/hooks", {
        method: "POST",
        headers: {
          authorization: "bearer wfh_secret",
          "idempotency-key": "abc",
          "content-type": "application/json",
        },
        body: JSON.stringify({ a: 1 }),
      }),
    );

    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ runId: "wrun_1" });
    expect(starts[0]).toMatchObject({
      triggerNode: "start",
      input: { a: 1 },
      idempotencyKey: "webhook:tr1:abc",
    });
  });

  it("decodes a token path segment", async () => {
    const { transport, calls } = fake({
      workflow_webhook_target: () => ({ trigger: TRIGGER }),
      workflow_start_target: target,
    });

    const builder = createWorkflowEditor({
      transport,
      start: recordingStarter().start,
    });

    await builder.triggers.webhook(
      new Request("https://a.test/hooks/wfh_a%2Fb", { method: "POST" }),
    );
    expect(calls[0]?.args).toEqual({ token: "wfh_a/b" });
  });

  it("starts a test run with a bare version, no stubs and no steps", async () => {
    const { transport } = fake({
      start_test_run: () => ({
        definition: DEFINITION,
        version: BARE_VERSION,
        input: undefined,
        stubs: "nope",
      }),
    });

    const { start, starts } = recordingStarter();
    const builder = createWorkflowEditor({ transport, start });

    await builder.test({ definition: "d1" }).orThrow();
    expect(starts[0]).toMatchObject({ input: {}, stubs: {}, mode: "test" });
    expect(starts[0]).not.toHaveProperty("triggerNode");
    expect(starts[0]).not.toHaveProperty("subject");
  });

  it("builds no stub for a step without an example or a default", async () => {
    const { transport } = fake({
      start_test_run: () => ({
        definition: DEFINITION,
        version: published,
        stubs: {},
      }),
    });

    const { start, starts } = recordingStarter();

    const builder = createWorkflowEditor({
      transport,
      start,
      steps: [
        {
          name: "crm.lookup",
          title: "Lookup",
          outputSchema: { type: "object" },
        },
        { name: "email.send", title: "Email", outputSchema: { examples: [] } },
        { name: "slack.post", title: "Slack" },
      ],
    });

    await builder.test({ definition: "d1" }).orThrow();
    expect(starts[0]?.stubs).toEqual({});
  });

  it("routes scheduled starts without a tenant and with a subject", async () => {
    const { transport } = fake({
      workflow_start_target: target,
      workflow_subject_start_target: (args) => ({
        ...target(),
        subject: { type: args["subject_type"], id: args["subject_id"] },
      }),
    });

    const { start, starts } = recordingStarter();
    const builder = createWorkflowEditor({ transport, start });
    const starter = builder.triggers.starter();

    await starter({
      source: "schedule",
      workflow: "builder:d1",
      input: {},
      idempotencyKey: "k",
      tenant: undefined,
      actor: undefined,
    });
    await starter({
      source: "schedule",
      workflow: "builder:d1",
      input: {},
      idempotencyKey: "k2",
      tenant: undefined,
      actor: undefined,
      subject: { type: "deal", id: "x" },
    });

    expect(starts[0]?.tenant).toBe("t1");
    expect(starts[1]?.subject).toEqual({ type: "deal", id: "x" });
  });
});

describe("workflow editor credentials", () => {
  const providerWith = (
    overrides: Partial<CredentialProvider> = {},
  ): CredentialProvider => ({
    apiVersion: 1,
    name: "memory",
    capabilities: () => ({
      userSubjects: false,
      authorization: true,
      revoke: true,
      inbound: false,
    }),
    getToken: () => AsyncResult.ok({ token: "tok", headers: {} }),
    startAuthorization: () => AsyncResult.ok({ url: "https://auth.test/go" }),
    revoke: () => AsyncResult.ok(true),
    ...overrides,
  });

  it("passes the state through authorization", async () => {
    const { transport } = fake({ workflow_credential_get: () => CREDENTIAL });

    const startAuthorization = vi.fn((_ref: unknown, _options: unknown) =>
      AsyncResult.ok({ url: "https://auth.test/go" }),
    );

    const builder = createWorkflowEditor({
      transport,
      credentials: providerWith({ startAuthorization }),
    });

    await builder.credentials
      .authorize({
        id: "c1",
        options: { redirectUri: "https://app.test/cb", state: "s1" },
      })
      .orThrow();
    await builder.credentials
      .authorize({ id: "c1", options: { redirectUri: "https://app.test/cb" } })
      .orThrow();

    expect(startAuthorization.mock.calls[0]?.[1]).toMatchObject({
      state: "s1",
      redirectUri: "https://app.test/cb",
    });
    expect(startAuthorization.mock.calls[1]?.[1]).not.toHaveProperty("state");
  });

  it("returns the error when the provider fails to revoke", async () => {
    const { transport } = fake({
      remove_workflow_credential: () => CREDENTIAL,
    });

    const builder = createWorkflowEditor({
      transport,
      credentials: providerWith({
        revoke: () => AsyncResult.err(dbError("unexpected", "provider down")),
      }),
    });

    const result = await builder.credentials.revoke("c1");

    expect(!result.ok && result.error.message).toBe("provider down");
  });
});

describe("workflow editor sync defaults and hooks", () => {
  it("syncs the steps and node kinds the editor was created with", async () => {
    const { transport, calls } = fake({
      sync_workflow_steps: () => 1,
      sync_workflow_node_kinds: () => 0,
    });

    const configured = createWorkflowEditor({
      transport,
      steps: [{ name: "crm.lookup", title: "Lookup" }],
      nodes: [],
    });

    expect(await configured.steps.sync().orThrow()).toBe(1);
    expect(await configured.nodeKinds.sync().orThrow()).toBe(0);

    const bare = createWorkflowEditor({ transport });

    await bare.steps.sync().orThrow();
    await bare.nodeKinds.sync().orThrow();

    expect(Object.keys(calls[0]?.args["steps"] as object)).toEqual([
      "crm.lookup",
    ]);
    expect(calls[2]?.args["steps"]).toEqual({});
    expect(calls[3]?.args["kinds"]).toEqual({});
  });

  it("runs hooks around run, test and each group", async () => {
    const { transport } = fake({
      workflow_start_target: target,
      start_test_run: () => ({ definition: DEFINITION, version: published }),
      workflow_definitions_list: () => [DEFINITION],
    });

    const before = vi.fn(() => undefined);
    const { start } = recordingStarter();

    const hooked = createWorkflowEditor({
      transport,
      start,
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      hooks: {
        run: { before },
        test: { before },
        definitions: { list: { before } },
      },
    });

    await hooked.run({ definition: "d1" }).orThrow();
    await hooked.test({ definition: "d1" }).orThrow();
    await hooked.definitions.list().orThrow();
    expect(before).toHaveBeenCalledTimes(3);

    const onlyRun = createWorkflowEditor({
      transport,
      start,
      hooks: { run: { before } },
    });

    await onlyRun.test({ definition: "d1" }).orThrow();
    await onlyRun.run({ definition: "d1" }).orThrow();
    expect(before).toHaveBeenCalledTimes(4);

    const onlyTest = createWorkflowEditor({
      transport,
      start,
      hooks: { test: { before } },
    });

    await onlyTest.run({ definition: "d1" }).orThrow();
    await onlyTest.test({ definition: "d1" }).orThrow();
    expect(before).toHaveBeenCalledTimes(5);
  });

  it("keeps trigger rows readable through a hooked editor", () => {
    expect(triggerOf(TRIGGER).kind).toBe("webhook");
  });
});
