import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../../src/credentials/provider.ts";

import { createAiProviders } from "../../../src/blocks/ai-providers/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const AT = "2026-01-01T00:00:00Z";
const REF = { provider: "vault", name: "ai:o1:anthropic" };
const OLD_REF = { provider: "vault", name: "ai:o1:anthropic:old" };
const job = undefined as never;
const signal = new AbortController().signal;

const keyRow = (overrides: Record<string, unknown> = {}) => ({
  id: "k1",
  organization_id: "o1",
  provider: "anthropic",
  name: "default",
  credential_ref: REF,
  settings: { region: "eu" },
  enabled: true,
  created_by: "u1",
  created_at: AT,
  updated_at: AT,
  ...overrides,
});

const batchRow = (overrides: Record<string, unknown> = {}) => ({
  id: "b1",
  organization_id: "o1",
  user_id: "u1",
  provider: "openai",
  reference: { version: 2, id: "batch_1", provider: "openai" },
  status: "pending",
  raw_status: "in_progress",
  item_count: 2,
  counts: { total: 2, pending: 2, bogus: "x" },
  error: null,
  metadata: {},
  results_saved: false,
  polls: 0,
  next_poll_at: AT,
  expires_at: null,
  completed_at: null,
  created_at: AT,
  updated_at: AT,
  ...overrides,
});

const sandboxRow = (overrides: Record<string, unknown> = {}) => ({
  id: "s1",
  organization_id: "o1",
  user_id: null,
  chat_id: "c1",
  provider: "vercel",
  sandbox_id: "sbx_1",
  container_id: null,
  status: "running",
  metadata: {},
  idle_seconds: 600,
  error: null,
  last_used_at: AT,
  expires_at: null,
  stopped_at: null,
  created_at: AT,
  ...overrides,
});

type Handler = (args: Record<string, unknown>) => unknown;

function fakeTransport(handlers: Record<string, Handler>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];
      if (!handler) return Promise.reject(new Error(`unexpected ${fn}`));
      return Promise.resolve(handler(args));
    },
  };
  return { transport, calls };
}

function fakeCredentials(tokens: Record<string, string> = {}) {
  const revoked: CredentialRef[] = [];
  const credentials: CredentialProvider = {
    apiVersion: 1,
    name: "fake",
    getToken: (ref) => {
      const token = tokens[String(ref["name"])];
      return token === undefined
        ? AsyncResult.err(dbError("not_found", "no credential"))
        : AsyncResult.ok({
            token,
            headers: { authorization: `Bearer ${token}` },
          });
    },
    capabilities: () => ({
      userSubjects: false,
      authorization: false,
      revoke: true,
      inbound: false,
    }),
    revoke: (ref, options) => {
      expect(options.subject).toEqual({ type: "app" });
      revoked.push(ref);
      return AsyncResult.ok(true);
    },
  };
  return { credentials, revoked };
}

describe("createAiProviders keys", () => {
  it("lists keys and refuses a row without a ref", async () => {
    const { transport } = fakeTransport({
      list_ai_provider_keys: () => [
        keyRow(),
        keyRow({ id: "k2", settings: null, enabled: false, created_by: null }),
      ],
    });
    const keys = await createAiProviders({ transport })
      .keys.list("o1")
      .orThrow();
    expect(keys.map((key) => [key.id, key.enabled, key.settings])).toEqual([
      ["k1", true, { region: "eu" }],
      ["k2", false, {}],
    ]);
    const bad = fakeTransport({
      list_ai_provider_keys: () => [keyRow({ credential_ref: "x" })],
    });
    const result = await createAiProviders({
      transport: bad.transport,
    }).keys.list("o1");
    expect(result.ok).toBe(false);
  });

  it("revokes the credential a save replaces, but not the same one", async () => {
    const { credentials, revoked } = fakeCredentials();
    let replaced: unknown = OLD_REF;
    const { transport, calls } = fakeTransport({
      save_ai_provider_key: () => ({ key: keyRow(), replaced }),
    });
    const providers = createAiProviders({ transport, credentials });
    await providers.keys
      .save("o1", { provider: "anthropic", credentialRef: REF })
      .orThrow();
    expect(calls[0]?.args).toMatchObject({
      tenant: "o1",
      provider: "anthropic",
      credential_ref: REF,
    });
    expect(revoked).toEqual([OLD_REF]);
    replaced = REF;
    await providers.keys
      .save("o1", { provider: "anthropic", credentialRef: REF })
      .orThrow();
    replaced = null;
    await providers.keys
      .save("o1", { provider: "anthropic", credentialRef: REF })
      .orThrow();
    expect(revoked).toEqual([OLD_REF]);
  });

  it("revokes on remove and on removeAll", async () => {
    const { credentials, revoked } = fakeCredentials();
    const { transport } = fakeTransport({
      delete_ai_provider_key: (args) => (args["id"] === "k1" ? keyRow() : null),
      delete_ai_provider_keys: () => [
        keyRow(),
        keyRow({ id: "k2", credential_ref: OLD_REF }),
      ],
    });
    const providers = createAiProviders({ transport, credentials });
    expect(await providers.keys.remove("k1").orThrow()).toBe(true);
    expect(await providers.keys.remove("gone").orThrow()).toBe(false);
    expect(await providers.keys.removeAll("o1").orThrow()).toBe(2);
    expect(revoked).toEqual([REF, REF, OLD_REF]);
  });

  it("removes without revoking when no credentials are configured", async () => {
    const { transport } = fakeTransport({
      delete_ai_provider_key: () => keyRow(),
    });
    expect(
      await createAiProviders({ transport }).keys.remove("k1").orThrow(),
    ).toBe(true);
  });

  it("resolves enabled keys through the service transport", async () => {
    const { credentials } = fakeCredentials({ "ai:o1:anthropic": "sk-1" });
    const user = fakeTransport({});
    const service = fakeTransport({ ai_provider_keys_for: () => [keyRow()] });
    const providers = createAiProviders({
      transport: user.transport,
      service: service.transport,
      credentials,
    });
    const keys = await providers.keys
      .resolve("o1", { providers: ["anthropic"], signal })
      .orThrow();
    expect(keys).toEqual([
      {
        provider: "anthropic",
        name: "default",
        token: "sk-1",
        headers: { authorization: "Bearer sk-1" },
        settings: { region: "eu" },
      },
    ]);
    expect(service.calls[0]?.args).toEqual({
      tenant: "o1",
      providers: ["anthropic"],
    });
    expect(user.calls).toEqual([]);
  });

  it("fails to resolve without credentials or a stored secret", async () => {
    const { transport } = fakeTransport({
      ai_provider_keys_for: () => [keyRow()],
    });
    const none = await createAiProviders({ transport }).keys.resolve("o1");
    expect(!none.ok && none.error.hint).toBe("AI_PROVIDER_KEY_UNRESOLVED");
    const missing = await createAiProviders({
      transport,
      credentials: fakeCredentials().credentials,
    }).keys.resolve("o1");
    expect(!missing.ok && missing.error.kind).toBe("not_found");
    const empty = fakeTransport({ ai_provider_keys_for: () => [] });
    expect(
      await createAiProviders({ transport: empty.transport })
        .keys.resolve("o1")
        .orThrow(),
    ).toEqual([]);
  });
});

describe("createAiProviders batches", () => {
  it("records, reads, lists and pages a batch", async () => {
    const { transport, calls } = fakeTransport({
      record_ai_batch: () => batchRow(),
      get_ai_batch: (args) =>
        args["id"] === "b1" ? batchRow({ status: "bogus" }) : null,
      list_ai_batches: () => [batchRow({ results_saved: true, counts: null })],
      list_ai_batch_items: () => [
        {
          batch_id: "b1",
          request_id: "r1",
          organization_id: "o1",
          status: "succeeded",
          output: { text: "a" },
          usage: null,
          error: null,
          created_at: AT,
        },
        {
          batch_id: "b1",
          request_id: "r2",
          organization_id: "o1",
          status: "bogus",
          output: null,
          usage: null,
          error: "boom",
          created_at: AT,
        },
      ],
    });
    const { batches } = createAiProviders({ transport });
    const recorded = await batches
      .record("o1", {
        provider: "openai",
        reference: { version: 2, id: "batch_1", provider: "openai" },
        itemCount: 2,
        userId: "u1",
        metadata: { job: "nightly" },
        status: "pending",
        rawStatus: "in_progress",
        counts: { total: 2 },
        expiresAt: Temporal.Instant.from("2026-01-02T00:00:00Z"),
      })
      .orThrow();
    expect(recorded.counts).toEqual({ total: 2, pending: 2 });
    expect(calls[0]?.args["fields"]).toEqual({
      user_id: "u1",
      item_count: 2,
      metadata: { job: "nightly" },
      status: "pending",
      raw_status: "in_progress",
      counts: { total: 2 },
      expires_at: "2026-01-02T00:00:00Z",
    });
    await batches.record("o1", { provider: "openai", reference: {} }).orThrow();
    expect(calls[1]?.args["fields"]).toEqual({});
    expect((await batches.get("b1").orThrow())?.status).toBe("failed");
    expect(await batches.get("b2").orThrow()).toBeUndefined();
    const listed = await batches
      .list("o1", { status: "completed", limit: 5 })
      .orThrow();
    expect(listed[0]).toMatchObject({ resultsSaved: true, counts: {} });
    const items = await batches
      .items("b1", { after: "r0", limit: 2 })
      .orThrow();
    expect(items.map((item) => [item.status, item.output, item.error])).toEqual(
      [
        ["succeeded", { text: "a" }, undefined],
        ["failed", undefined, "boom"],
      ],
    );
  });

  it("claims, updates and saves items as the service role", async () => {
    const service = fakeTransport({
      due_ai_batches: () => [batchRow()],
      update_ai_batch: () => batchRow({ status: "completed" }),
      save_ai_batch_items: () => 1,
    });
    const { batches } = createAiProviders({
      transport: fakeTransport({}).transport,
      service: service.transport,
    });
    expect(
      await batches.due({ batch: 5, leaseSeconds: 30 }).orThrow(),
    ).toHaveLength(1);
    await batches
      .update("b1", {
        status: "completed",
        rawStatus: "done",
        counts: { total: 2, completed: 2 },
        error: null,
        expiresAt: Temporal.Instant.from(AT),
        resultsSaved: true,
        nextPollAt: null,
      })
      .orThrow();
    expect(service.calls[1]?.args).toEqual({
      id: "b1",
      fields: {
        status: "completed",
        raw_status: "done",
        counts: { total: 2, completed: 2 },
        error: null,
        expires_at: AT,
        results_saved: true,
        next_poll_at: null,
      },
    });
    await batches.update("b1", {}).orThrow();
    expect(service.calls[2]?.args).toEqual({ id: "b1", fields: {} });
    expect(
      await batches
        .saveItems("b1", [
          { requestId: "r1", status: "succeeded", output: { text: "a" } },
        ])
        .orThrow(),
    ).toBe(1);
    expect(service.calls[3]?.args["items"]).toEqual({
      items: [
        {
          request_id: "r1",
          status: "succeeded",
          output: { text: "a" },
          usage: null,
          error: null,
        },
      ],
    });
  });
});

describe("createAiProviders sandboxes", () => {
  it("registers, touches, finds and lists sandboxes", async () => {
    const { transport, calls } = fakeTransport({
      register_ai_sandbox: () => sandboxRow(),
      touch_ai_sandbox: () => true,
      ai_sandbox_for: (args) =>
        args["chat_id"] === "c1" ? sandboxRow({ status: "bogus" }) : null,
      list_ai_sandboxes: () => [
        sandboxRow({ stopped_at: AT, status: "stopped" }),
      ],
    });
    const { sandboxes } = createAiProviders({ transport });
    await sandboxes
      .register("o1", {
        provider: "vercel",
        sandboxId: "sbx_1",
        userId: "u1",
        chatId: "c1",
        containerId: "ctr",
        metadata: { runtime: "node24" },
        idleSeconds: 299.6,
        expiresAt: Temporal.Instant.from(AT),
      })
      .orThrow();
    expect(calls[0]?.args).toEqual({
      tenant: "o1",
      provider: "vercel",
      sandbox_id: "sbx_1",
      fields: {
        user_id: "u1",
        chat_id: "c1",
        container_id: "ctr",
        metadata: { runtime: "node24" },
        idle_seconds: 300,
        expires_at: AT,
      },
    });
    await sandboxes
      .register("o1", { provider: "vercel", sandboxId: "sbx_2" })
      .orThrow();
    expect(calls[1]?.args["fields"]).toEqual({});
    expect(await sandboxes.touch("s1").orThrow()).toBe(true);
    expect((await sandboxes.forChat("c1", "vercel").orThrow())?.status).toBe(
      "stopped",
    );
    expect(await sandboxes.forChat("c2", "vercel").orThrow()).toBeUndefined();
    const listed = await sandboxes.list("o1", { chatId: "c1" }).orThrow();
    expect(listed[0]?.stoppedAt?.toString()).toBe(AT);
  });

  it("stops idle sandboxes and records failures", async () => {
    const finished: unknown[] = [];
    const { transport } = fakeTransport({
      idle_ai_sandboxes: () => [
        sandboxRow(),
        sandboxRow({ id: "s2", sandbox_id: "sbx_2" }),
      ],
      finish_ai_sandbox_stop: (args) => {
        finished.push(args);
        return true;
      },
    });
    const { sandboxes } = createAiProviders({ transport });
    const stopped = await sandboxes.idleStopJob(async (sandbox) => {
      if (sandbox.id === "s2") throw new Error("busy");
    })(undefined, job, signal);
    expect(stopped).toBe(1);
    expect(finished).toEqual([
      { id: "s1", stopped: true, error: undefined },
      { id: "s2", stopped: false, error: "busy" },
    ]);
  });

  it("stops when recording a stop fails", async () => {
    const { transport } = fakeTransport({
      idle_ai_sandboxes: () => [sandboxRow()],
      finish_ai_sandbox_stop: () => Promise.reject(new Error("db down")),
    });
    const result = await createAiProviders({ transport }).sandboxes.stopIdle(
      async () => {},
    );
    expect(result.ok).toBe(false);
  });
});
