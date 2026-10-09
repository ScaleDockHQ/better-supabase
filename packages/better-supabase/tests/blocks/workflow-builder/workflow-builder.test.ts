import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";
import type { CredentialProvider } from "../../../src/credentials/provider.ts";

import {
  type BuilderStartCall,
  createBuilder,
  credentialOf,
  definitionOf,
  nodeRunOf,
  triggerOf,
  versionOf,
} from "../../../src/blocks/workflow-builder/workflow-builder.ts";
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
const ALERT = {
  id: "a1",
  definition: "d1",
  onEvent: "slow",
  threshold: 60,
  channel: { type: "email" },
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
      if (reply === undefined) throw new Error(`unexpected ${fn}`);
      return reply(args);
    }),
  };
  return { transport, calls };
}

const published = { ...VERSION, status: "published", publishedAt: AT };
const target = () => ({ definition: DEFINITION, version: published });

function provider(overrides: Partial<CredentialProvider> = {}) {
  const revoke = vi.fn(() => AsyncResult.ok(true));
  const set = vi.fn(() => AsyncResult.ok(undefined));
  const memory: CredentialProvider & { set: typeof set } = {
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
    revoke,
    set,
    ...overrides,
  };
  return { memory, revoke, set };
}

describe("row mappers", () => {
  it("reads rows and rejects unknown values", () => {
    expect(
      definitionOf({ ...DEFINITION, published: 2, draft: true }),
    ).toMatchObject({
      published: 2,
      draft: true,
      description: undefined,
    });
    expect(definitionOf({ ...DEFINITION, published: null })).toMatchObject({
      published: undefined,
    });
    expect(() => definitionOf({ ...DEFINITION, createdAt: null })).toThrow(
      "createdAt is missing",
    );
    expect(versionOf(VERSION).graph?.nodes).toHaveLength(8);
    expect(versionOf(VERSION)).not.toHaveProperty("compiled");
    expect(versionOf({ ...VERSION, compiled: { x: 1 } }).compiled).toEqual({
      x: 1,
    });
    expect(() => versionOf({ ...VERSION, status: "gone" })).toThrow(
      'unknown version status "gone"',
    );
    expect(
      triggerOf({ ...TRIGGER, config: null, enabled: null }),
    ).toMatchObject({
      config: {},
      enabled: true,
    });
    expect(credentialOf({ ...CREDENTIAL, scopes: null }).scopes).toEqual([]);
    expect(() => credentialOf({ ...CREDENTIAL, ref: {} })).toThrow(
      "has no provider",
    );
    expect(
      nodeRunOf({
        run: "r",
        node: "n",
        status: "waiting",
        attempts: null,
        output: null,
      }),
    ).toMatchObject({ attempts: 0, output: undefined });
  });
});

describe("createBuilder", () => {
  it("passes definitions, versions, triggers, steps, node runs and alerts through", async () => {
    const { transport, calls } = fake({
      save_workflow_definition: () => DEFINITION,
      workflow_definitions_list: () => [DEFINITION],
      workflow_definition_get: () => null,
      remove_workflow_definition: () => true,
      save_workflow_draft: () => VERSION,
      workflow_versions_list: () => [VERSION],
      save_workflow_trigger: () => TRIGGER,
      workflow_triggers_list: () => [TRIGGER],
      remove_workflow_trigger: () => true,
      rotate_workflow_webhook_token: () => "wfh_abc",
      sync_workflow_steps: () => 1,
      workflow_steps_list: () => [{ name: "s", title: "S", inputSchema: null }],
      record_workflow_node_run: () => true,
      workflow_node_runs_list: () => [
        { run: "r", node: "n", status: "completed", attempts: 1 },
      ],
      save_workflow_alert: () => ALERT,
      workflow_alerts_list: () => [ALERT],
      remove_workflow_alert: () => true,
      check_workflow_alerts: () => 2,
    });
    const builder = createBuilder({
      transport,
      steps: [{ name: "s", title: "S", credentialKind: "crm" }],
    });
    await builder.definitions
      .save({ tenant: "t1", slug: "onboard", name: "Onboard" })
      .orThrow();
    expect(await builder.definitions.list("t1").orThrow()).toHaveLength(1);
    expect(await builder.definitions.get("d1").orThrow()).toBeUndefined();
    expect(await builder.definitions.remove("d1").orThrow()).toBe(true);
    expect((await builder.versions.save("d1", GRAPH).orThrow()).version).toBe(
      1,
    );
    expect(await builder.versions.list("d1").orThrow()).toHaveLength(1);
    await builder.triggers
      .save({ definition: "d1", kind: "webhook" })
      .orThrow();
    expect(await builder.triggers.list("d1").orThrow()).toHaveLength(1);
    expect(await builder.triggers.remove("tr1").orThrow()).toBe(true);
    expect(await builder.triggers.rotateToken("tr1").orThrow()).toBe("wfh_abc");
    expect(await builder.steps.sync().orThrow()).toBe(1);
    expect(await builder.steps.list().orThrow()).toEqual([
      {
        name: "s",
        title: "S",
        description: undefined,
        inputSchema: {},
        outputSchema: {},
        credentialKind: undefined,
      },
    ]);
    expect(
      await builder.nodeRuns
        .record({ run: "r", node: "n", status: "running" })
        .orThrow(),
    ).toBe(true);
    expect(await builder.nodeRuns.list("r").orThrow()).toHaveLength(1);
    expect(
      (
        await builder.alerts
          .save({ definition: "d1", onEvent: "slow", threshold: 60 })
          .orThrow()
      ).threshold,
    ).toBe(60);
    await builder.alerts
      .save({ definition: "d1", onEvent: "failed" })
      .orThrow();
    expect((await builder.alerts.list("d1").orThrow())[0]?.onEvent).toBe(
      "slow",
    );
    expect(await builder.alerts.remove("a1").orThrow()).toBe(true);
    expect(await builder.alerts.check({ batch: 5 }).orThrow()).toBe(2);

    const args = (fn: string) =>
      calls.filter((c) => c.fn === fn).map((c) => c.args);
    expect(args("sync_workflow_steps")[0]).toEqual({
      steps: {
        s: {
          title: "S",
          description: undefined,
          inputSchema: {},
          outputSchema: {},
          credentialKind: "crm",
        },
      },
    });
    expect(args("save_workflow_trigger")[0]).toEqual({
      definition: "d1",
      kind: "webhook",
      config: {},
      enabled: true,
      trigger: undefined,
    });
    expect(args("save_workflow_alert").map((a) => a["threshold"])).toEqual([
      "60 seconds",
      undefined,
    ]);
  });

  it("compiles on publish, unless the version is already published", async () => {
    let status = "draft";
    const { transport, calls } = fake({
      workflow_version_get: () => ({ ...VERSION, status }),
      publish_workflow_version: (args) => ({
        ...published,
        compiled: args["compiled"],
      }),
    });
    const service = fake({
      publish_workflow_version: (args) => ({
        ...published,
        compiled: args["compiled"],
      }),
    });
    const compile = vi.fn(() => ({ compiled: true }));
    const builder = createBuilder({
      transport,
      service: service.transport,
      compile,
    });
    expect((await builder.versions.publish("v1").orThrow()).compiled).toEqual({
      compiled: true,
    });
    expect(calls.at(-1)?.args).toEqual({ version: "v1", compiled: null });
    expect(service.calls.map((c) => c.args)).toEqual([
      { version: "v1", compiled: { compiled: true } },
    ]);
    status = "published";
    await builder.versions.publish("v1").orThrow();
    expect(compile).toHaveBeenCalledTimes(1);
    expect(calls.at(-1)?.args).toEqual({ version: "v1", compiled: null });
    expect(service.calls).toHaveLength(1);

    status = "draft";
    const userOnly = createBuilder({ transport, compile });
    expect(
      (await userOnly.versions.publish("v1").orThrow()).compiled,
    ).toBeUndefined();
    expect(calls.at(-1)?.args).toEqual({ version: "v1", compiled: null });
    expect(service.calls).toHaveLength(1);

    const failing = createBuilder({
      transport,
      compile: () => {
        throw new Error("too big");
      },
    });
    status = "draft";
    const result = await failing.versions.publish("v1");
    expect(!result.ok && [result.error.kind, result.error.message]).toEqual([
      "invalid_input",
      "too big",
    ]);
    const plain = createBuilder({
      transport,
      compile: () => {
        // oxlint-disable-next-line typescript/only-throw-error -- a compiler may throw a non-Error.
        throw "nope";
      },
    });
    const thrown = await plain.versions.publish("v1");
    expect(!thrown.ok && thrown.error.message).toBe("nope");
  });

  it("reports missing versions on publish and diff, and diffs two versions", async () => {
    const { transport } = fake({
      workflow_version_get: (args) =>
        args["version"] === "missing"
          ? null
          : {
              ...VERSION,
              id: String(args["version"]),
              graph:
                args["version"] === "v2"
                  ? {
                      ...GRAPH,
                      nodes: GRAPH.nodes.slice(0, 2),
                      edges: GRAPH.edges.slice(0, 1),
                    }
                  : GRAPH,
            },
    });
    const builder = createBuilder({ transport });
    const missing = await builder.versions.publish("missing");
    expect(!missing.ok && missing.error.kind).toBe("not_found");
    const noDiff = await builder.versions.diff("v1", "missing");
    expect(!noDiff.ok && noDiff.error.kind).toBe("not_found");
    const diff = await builder.versions.diff("v1", "v2").orThrow();
    expect(diff.nodes.added).toEqual([]);
    expect(diff.nodes.removed).toHaveLength(6);
    expect(await builder.versions.get("v1").orThrow()).toMatchObject({
      id: "v1",
    });
  });

  it("starts runs of the published version", async () => {
    const { transport } = fake({ workflow_start_target: target });
    const starts: BuilderStartCall[] = [];
    const builder = createBuilder({
      transport,
      start: async (call) => {
        starts.push(call);
        return "wrun_1";
      },
    });
    expect(await builder.run({ definition: "d1", actor: "u1" }).orThrow()).toBe(
      "wrun_1",
    );
    expect(starts[0]).toMatchObject({ input: {}, tenant: "t1", actor: "u1" });
    expect(starts[0]?.idempotencyKey).toMatch(/^run:/);
    const without = await createBuilder({ transport }).run({
      definition: "d1",
    });
    expect(!without.ok && without.error.message).toContain("Pass `start`");
  });

  it("answers webhooks", async () => {
    let found = true;
    const { transport } = fake({
      workflow_webhook_target: () => (found ? { trigger: TRIGGER } : null),
      workflow_start_target: target,
    });
    const starts: BuilderStartCall[] = [];
    const builder = createBuilder({
      transport,
      start: async (call) => {
        starts.push(call);
        return "wrun_1";
      },
    });
    const post = (url: string, init: RequestInit = {}) =>
      builder.triggers.webhook(new Request(url, { method: "POST", ...init }));

    expect(
      (
        await builder.triggers.webhook(new Request("https://a.test/wfh_x"))
      ).headers.get("allow"),
    ).toBe("POST");
    expect((await post("https://a.test/hooks")).status).toBe(404);
    expect(
      (
        await post("https://a.test/hooks", {
          headers: { authorization: "Bearer " },
        })
      ).status,
    ).toBe(404);
    const text = await post("https://a.test/hooks/wfh_x", { body: "plain" });
    expect(text.status).toBe(202);
    expect(starts[0]?.input).toEqual({ body: "plain" });
    expect(starts[0]?.idempotencyKey).toMatch(/^webhook:tr1:/);
    await post("https://a.test/hooks/wfh_x", {
      headers: { "idempotency-key": "" },
    });
    expect(starts[1]?.input).toEqual({});
    found = false;
    expect((await post("https://a.test/hooks/wfh_x")).status).toBe(404);

    const failing = createBuilder({
      transport: {
        call: async () => {
          throw new Error("down");
        },
      },
    });
    expect(
      (
        await failing.triggers.webhook(
          new Request("https://a.test/wfh_x", { method: "POST" }),
        )
      ).status,
    ).toBe(500);
    const { transport: unpublished } = fake({
      workflow_webhook_target: () => ({ trigger: TRIGGER }),
      workflow_start_target: () => {
        throw Object.assign(new Error("not published"), {
          code: "P0001",
          hint: "WORKFLOW_NOT_PUBLISHED",
        });
      },
    });
    const refused = await createBuilder({
      transport: unpublished,
      start: async () => "x",
    }).triggers.webhook(
      new Request("https://a.test/wfh_x", { method: "POST" }),
    );
    expect(refused.status).toBeGreaterThanOrEqual(400);
  });

  it("starts event triggers and stops at the first failure", async () => {
    const { transport } = fake({
      workflow_event_targets: () => [
        { trigger: { ...TRIGGER, id: "a", kind: "event" } },
        { trigger: { ...TRIGGER, id: "b", kind: "event" } },
      ],
      workflow_start_target: target,
    });
    let n = 0;
    const builder = createBuilder({
      transport,
      start: async () => `wrun_${String(++n)}`,
    });
    expect(
      await builder.triggers
        .onEvent({ id: "e1", type: "x", tenant: "t1" })
        .orThrow(),
    ).toEqual(["wrun_1", "wrun_2"]);
    const failing = await createBuilder({ transport }).triggers.onEvent({
      id: "e1",
      type: "x",
    });
    expect(failing.ok).toBe(false);
  });

  it("syncs schedule triggers and routes scheduled builder starts", async () => {
    const { transport, calls } = fake({
      create_workflow_schedule: (args) => ({
        id: "s1",
        tenant: args["tenant"] ?? null,
        name: args["name"],
        workflow: args["workflow"],
        input: args["input"],
        cron: args["cron"],
        timezone: args["timezone"] ?? "UTC",
        nextRunAt: AT,
        lastRunAt: null,
        paused: false,
        createdBy: null,
        createdAt: AT,
      }),
      workflow_start_target: target,
    });
    const builder = createBuilder({ transport, start: async () => "wrun_1" });
    const bad = await builder.triggers.syncSchedule(triggerOf(TRIGGER));
    expect(!bad.ok && bad.error.kind).toBe("invalid_input");
    const schedule = triggerOf({
      ...TRIGGER,
      kind: "schedule",
      config: { cron: "@daily", timezone: "Europe/Amsterdam" },
    });
    expect(
      await builder.triggers.syncSchedule(schedule, "t1").orThrow(),
    ).toMatchObject({
      name: "builder-trigger:tr1",
      workflow: "builder:d1",
      tenant: "t1",
    });
    await builder.triggers
      .syncSchedule({ ...schedule, config: { cron: "@daily" } })
      .orThrow();
    expect(
      calls.filter((c) => c.fn === "create_workflow_schedule"),
    ).toHaveLength(2);

    const fallback = vi.fn(async () => "other");
    const starter = builder.triggers.starter(fallback);
    const scheduled = {
      workflow: "builder:d1",
      input: { a: 1 },
      idempotencyKey: "k",
      tenant: "t1",
      actor: undefined,
    };
    expect(await starter({ ...scheduled, actor: "u1" })).toBe("wrun_1");
    expect(await starter(scheduled)).toBe("wrun_1");
    expect(await starter({ ...scheduled, workflow: "report" })).toBe("other");
    await expect(
      builder.triggers.starter()({ ...scheduled, workflow: "report" }),
    ).rejects.toThrow('no starter for workflow "report"');
  });

  it("stores, authorizes, resolves and revokes credentials through providers", async () => {
    let row: unknown = CREDENTIAL;
    const { transport } = fake({
      save_workflow_credential: (args) => ({ ...CREDENTIAL, ref: args["ref"] }),
      workflow_credentials_list: () => [CREDENTIAL],
      workflow_credential_get: () => row,
      remove_workflow_credential: () => row,
    });
    const { memory, revoke, set } = provider();
    const builder = createBuilder({ transport, credentials: [memory] });
    expect(await builder.credentials.list("t1").orThrow()).toHaveLength(1);
    await builder.credentials
      .create({
        kind: "crm",
        name: "CRM",
        ref: { provider: "memory", secret: "crm" },
        secret: "s",
      })
      .orThrow();
    expect(set).toHaveBeenCalledWith(
      { provider: "memory", secret: "crm" },
      "s",
      { subject: { type: "app" } },
    );
    await builder.credentials
      .create({ kind: "crm", name: "CRM", ref: { provider: "memory" } })
      .orThrow();
    const unknown = await builder.credentials.create({
      kind: "x",
      name: "X",
      ref: { provider: "vault" },
      secret: "s",
    });
    expect(!unknown.ok && unknown.error.message).toContain(
      'No credential provider named "vault"',
    );

    expect(
      await builder.credentials
        .authorize("c1", { redirectUri: "https://a.test/cb", state: "s" })
        .orThrow(),
    ).toBe("https://auth.test/go");
    expect(await builder.credentials.resolve("c1").orThrow()).toMatchObject({
      token: "tok",
    });
    expect(await builder.credentials.revoke("c1").orThrow()).toBe(true);
    expect(revoke).toHaveBeenCalledOnce();

    row = null;
    for (const result of [
      await builder.credentials.authorize("c1", { redirectUri: "x" }),
      await builder.credentials.resolve("c1"),
    ]) {
      expect(!result.ok && result.error.kind).toBe("not_found");
    }
    expect(await builder.credentials.revoke("c1").orThrow()).toBe(false);

    const foreignRef = { provider: "memory", secret: "crm", tenant: "t2" };
    const foreign = await builder.credentials.create({
      tenant: "t1",
      kind: "crm",
      name: "CRM",
      ref: foreignRef,
      secret: "s",
    });
    expect(!foreign.ok && foreign.error.hint).toBe("CREDENTIAL_REF_FOREIGN");
    row = { ...CREDENTIAL, ref: foreignRef };
    const stolen = await builder.credentials.resolve("c1");
    expect(!stolen.ok && stolen.error.hint).toBe("CREDENTIAL_REF_FOREIGN");
    expect(await builder.credentials.revoke("c1").orThrow()).toBe(true);
    expect(revoke).toHaveBeenCalledOnce();

    row = { ...CREDENTIAL, ref: { provider: "vault", tenant: "t1" } };
    for (const result of [
      await builder.credentials.authorize("c1", { redirectUri: "x" }),
      await builder.credentials.resolve("c1"),
      await builder.credentials.revoke("c1"),
    ]) {
      expect(!result.ok && result.error.kind).toBe("invalid_request");
    }
  });

  it("refuses what a provider can't do", async () => {
    const { transport } = fake({
      workflow_credential_get: () => CREDENTIAL,
      remove_workflow_credential: () => CREDENTIAL,
    });
    const { memory: limited, revoke } = provider({
      capabilities: () => ({
        userSubjects: false,
        authorization: false,
        revoke: false,
        inbound: false,
      }),
    });
    const { set: _set, ...noStore } = limited;
    const builder = createBuilder({ transport, credentials: noStore });
    const authorize = await builder.credentials.authorize("c1", {
      redirectUri: "x",
    });
    expect(!authorize.ok && authorize.error.kind).toBe("unsupported");
    expect(await builder.credentials.revoke("c1").orThrow()).toBe(true);
    expect(revoke).not.toHaveBeenCalled();
    const store = await builder.credentials.create({
      tenant: "t1",
      kind: "crm",
      name: "CRM",
      ref: CREDENTIAL.ref,
      secret: "s",
    });
    expect(!store.ok && store.error.message).toContain("can't store secrets");

    const brokenProvider: CredentialProvider = {
      ...limited,
      ...{ set: () => "nope" },
    };
    const broken = createBuilder({ transport, credentials: brokenProvider });
    const result = await broken.credentials.create({
      tenant: "t1",
      kind: "crm",
      name: "CRM",
      ref: CREDENTIAL.ref,
      secret: "s",
    });
    expect(!result.ok && result.error.message).toContain("returned no result");
    const notFnProvider: CredentialProvider = { ...noStore, ...{ set: 1 } };
    const notFn = createBuilder({ transport, credentials: notFnProvider });
    const notFnResult = await notFn.credentials.create({
      tenant: "t1",
      kind: "crm",
      name: "CRM",
      ref: CREDENTIAL.ref,
      secret: "s",
    });
    expect(!notFnResult.ok && notFnResult.error.message).toContain(
      "can't store secrets",
    );
  });
});
