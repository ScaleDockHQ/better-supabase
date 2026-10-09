import { SPEC_VERSION_MAX_SUPPORTED } from "@workflow/world";
import { readdir, readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { describe, expect, it, vi } from "vitest";

import type { AiChat } from "../../src/blocks/ai-chat/ai-chat.ts";
import type { Inbox } from "../../src/blocks/inbox/inbox.ts";
import type { Knowledge } from "../../src/blocks/knowledge/knowledge.ts";
import type { Memory } from "../../src/blocks/memory/memory.ts";
import type { CredentialProvider } from "../../src/credentials/provider.ts";

import { dbError, DbException } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  chatIdOf,
  ConnectionAuthorizationFailedError,
  ConnectionAuthorizationRequiredError,
  credentialAuth,
  EveAuthRejection,
  type EveChatMessage,
  type EveChatThread,
  type EveConnectionPrincipal,
  type EveMemoryContext,
  type EveSessionAuth,
  type EveSessionContext,
  MemoryDocumentConflictError,
  persistSessions,
  principalOf,
  routeInbox,
  stableUuid,
  supabaseAuth,
  supabaseDocumentBackend,
  supabaseMemory,
} from "../../src/eve/index.ts";
import { testEveDocumentBackend } from "../../src/testing/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";
const ORG = "22222222-2222-4222-8222-222222222222";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const signer = await createTestSigner();

const user: EveSessionAuth = {
  authenticator: "supabase",
  principalType: "user",
  principalId: USER,
  issuer: `${PROJECT_URL}/auth/v1`,
  attributes: { tenantId: ORG, roles: ["admin"], isAnonymous: "false" },
};

function session(
  auth: EveSessionAuth | null,
  id = "sess_1",
): EveSessionContext {
  return { session: { id, auth: { current: auth, initiator: auth } } };
}

const bearer = (token: string): Request =>
  new Request("https://app.test/eve/v1/session", {
    headers: { authorization: `Bearer ${token}` },
  });

describe("supabaseAuth", () => {
  const options = () => ({ env, jwks: { keys: [...signer.jwks.keys] } });

  it("maps a verified user to a principal with tenant and roles", async () => {
    const token = await signer.sign({
      sub: USER,
      app_metadata: { tenant_id: ORG },
      memberships: [
        { id: ORG, roles: ["admin", "member", 3] },
        { id: "other", roles: ["owner"] },
      ],
    });
    const principal = await supabaseAuth({
      ...options(),
      attributes: (claims) => ({ email: String(claims["email"] ?? "none") }),
    })(bearer(token));
    expect(principal).toMatchObject({
      authenticator: "supabase",
      principalType: "user",
      principalId: USER,
      subject: USER,
      attributes: {
        tenantId: ORG,
        roles: ["admin", "member"],
        isAnonymous: "false",
        email: "none",
      },
    });
  });

  it("reads roles from a membership map and marks anonymous users", async () => {
    const token = await signer.sign({
      sub: USER,
      is_anonymous: true,
      tenant_id: ORG,
      memberships: { [ORG]: ["viewer"] },
    });
    const principal = await supabaseAuth({
      ...options(),
      tenantClaim: "tenant_id",
    })(bearer(token));
    expect(principal?.attributes).toMatchObject({
      tenantId: ORG,
      roles: ["viewer"],
      isAnonymous: "true",
    });
  });

  it("returns null without a session and rejects an invalid token", async () => {
    const auth = supabaseAuth(options());
    expect(await auth(new Request("https://app.test/"))).toBeNull();
    const rejected = await auth(bearer("not.a.token")).catch(
      (error: unknown) => error,
    );
    expect(rejected).toBeInstanceOf(EveAuthRejection);
    expect((rejected as EveAuthRejection).response.status).toBe(401);
  });

  it("reads roles from the configured memberships claim", () => {
    const auth = {
      kind: "user",
      claims: {
        sub: USER,
        role: "authenticated",
        tenant_id: ORG,
        held: { [ORG]: ["editor"] },
      },
    } as unknown as Parameters<typeof principalOf>[0];
    expect(principalOf(auth)?.attributes["roles"]).toEqual([]);
    expect(
      principalOf(auth, { membershipsClaim: "held" })?.attributes["roles"],
    ).toEqual(["editor"]);
  });

  it("gives a user without a tenant no roles", () => {
    expect(
      principalOf({
        kind: "user",
        claims: { sub: USER, role: "authenticated" },
      } as Parameters<typeof principalOf>[0])?.attributes,
    ).toEqual({ roles: [], isAnonymous: "false" });
    expect(
      principalOf({ kind: "anon" } as Parameters<typeof principalOf>[0]),
    ).toBeNull();
  });
});

function token(value: string, expiresAt?: Temporal.Instant) {
  return AsyncResult.ok({
    token: value,
    headers: { authorization: `Bearer ${value}` },
    ...(expiresAt === undefined ? {} : { expiresAt }),
  });
}

function provider(
  overrides: Partial<CredentialProvider> = {},
): CredentialProvider & {
  readonly getToken: ReturnType<typeof vi.fn>;
} {
  return {
    apiVersion: 1,
    name: "test",
    getToken: vi.fn(() => token("t1")),
    capabilities: () => ({
      userSubjects: true,
      authorization: true,
      revoke: true,
      inbound: false,
    }),
    revoke: () => AsyncResult.ok(true),
    ...overrides,
  } as CredentialProvider & { readonly getToken: ReturnType<typeof vi.fn> };
}

describe("credentialAuth", () => {
  const ref = { provider: "vault", secret: "linear" };
  const connected = {
    type: "user",
    id: USER,
    issuer: `${PROJECT_URL}/auth/v1`,
  } satisfies EveConnectionPrincipal;
  const app = { type: "app" } satisfies EveConnectionPrincipal;
  const request = (principal: EveConnectionPrincipal = app) => ({
    principal,
    connection: { url: "https://mcp.linear.app/mcp" },
  });

  it("uses the app's credential for owner app", async () => {
    const at = Temporal.Instant.from("2026-10-08T12:00:00Z");
    const p = provider({ getToken: vi.fn(() => token("app", at)) });
    const auth = credentialAuth({
      provider: p,
      ref,
      owner: "app",
      scopes: ["read"],
    });
    expect("startAuthorization" in auth).toBe(false);
    expect(await auth.getToken(request())).toEqual({
      token: "app",
      expiresAt: at.epochMilliseconds,
    });
    expect(p.getToken).toHaveBeenCalledWith(ref, {
      subject: { type: "app" },
      scopes: ["read"],
    });
  });

  it("uses the user's credential and asks a non-user to authorize", async () => {
    const p = provider();
    const auth = credentialAuth({
      provider: p,
      ref,
      owner: "user",
      interactive: false,
    });
    expect(auth).toMatchObject({ credentialOwner: "user" });
    expect("principalType" in auth).toBe(false);
    expect(await auth.getToken(request(connected))).toEqual({ token: "t1" });
    expect(p.getToken).toHaveBeenCalledWith(ref, {
      subject: { type: "user", id: USER, issuer: user.issuer },
    });
    await expect(auth.getToken(request())).rejects.toBeInstanceOf(
      ConnectionAuthorizationRequiredError,
    );
  });

  it("maps provider errors to eve's connection errors", async () => {
    const failing = (error: Parameters<typeof AsyncResult.err>[0]) =>
      credentialAuth({
        provider: provider({ getToken: vi.fn(() => AsyncResult.err(error)) }),
        ref,
        owner: "app",
        connection: "linear",
      }).getToken(request());
    await expect(failing(dbError("not_found", "none"))).rejects.toBeInstanceOf(
      ConnectionAuthorizationRequiredError,
    );
    await expect(
      failing(
        dbError("raised", "connect", {
          hint: "CREDENTIAL_AUTHORIZATION_REQUIRED",
        }),
      ),
    ).rejects.toMatchObject({
      name: "ConnectionAuthorizationRequiredError",
      connectionName: "linear",
    });
    await expect(
      failing(dbError("forbidden", "no", { hint: "CREDENTIAL_FORBIDDEN" })),
    ).rejects.toMatchObject({
      name: "ConnectionAuthorizationFailedError",
      reason: "CREDENTIAL_FORBIDDEN",
      retryable: false,
    });
    const invalid = await failing(dbError("invalid_input", "bad ref")).catch(
      (error: unknown) => error,
    );
    expect(invalid).toBeInstanceOf(ConnectionAuthorizationFailedError);
    expect((invalid as ConnectionAuthorizationFailedError).reason).toBe(
      "invalid_input",
    );
    await expect(failing(dbError("network", "down"))).rejects.toBeInstanceOf(
      DbException,
    );
  });

  it("runs eve's authorization flow through the provider", async () => {
    const start = vi.fn(() =>
      AsyncResult.ok({ url: "https://linear.app/oauth" }),
    );
    const complete = vi.fn(() => AsyncResult.ok(undefined));
    const p = provider({
      startAuthorization: start,
      completeAuthorization: complete,
    });
    const auth = credentialAuth({
      provider: p,
      ref,
      owner: "user",
      scopes: ["read"],
    });
    expect(auth).toMatchObject({ principalType: "user" });
    const callbackUrl = "https://app.test/eve/v1/connections/linear/callback";
    expect(
      await auth.startAuthorization?.({ ...request(connected), callbackUrl }),
    ).toEqual({
      challenge: { url: "https://linear.app/oauth" },
    });
    expect(start).toHaveBeenCalledWith(ref, {
      subject: { type: "user", id: USER, issuer: user.issuer },
      redirectUri: callbackUrl,
      scopes: ["read"],
    });
    expect(
      await auth.completeAuthorization?.({
        ...request(connected),
        callbackUrl,
        callback: { params: { code: "c1", state: "s1" }, method: "GET" },
      }),
    ).toEqual({ token: "t1" });
    const [, options] = complete.mock.calls[0] as unknown as [
      unknown,
      { callback: URL },
    ];
    expect(options.callback.searchParams.get("code")).toBe("c1");
    expect(options.callback.searchParams.get("state")).toBe("s1");

    const denied = credentialAuth({
      provider: provider({
        startAuthorization: () => AsyncResult.err(dbError("forbidden", "no")),
        completeAuthorization: () =>
          AsyncResult.err(dbError("forbidden", "no")),
      }),
      ref,
      owner: "user",
    });
    await expect(
      denied.startAuthorization?.({ ...request(connected), callbackUrl }),
    ).rejects.toBeInstanceOf(ConnectionAuthorizationFailedError);
    await expect(
      denied.completeAuthorization?.({
        ...request(connected),
        callbackUrl,
        callback: { params: {}, method: "GET" },
      }),
    ).rejects.toBeInstanceOf(ConnectionAuthorizationFailedError);
  });
});

/** An in-memory `memory.documents` with the SQL module's version rules. */
function documentStore() {
  const rows = new Map<string, { content: string; version: number }>();
  const documents: Memory["documents"] = {
    read: (scope, path) => {
      const row = rows.get(`${scope}|${path}`);
      return AsyncResult.ok(
        row
          ? { content: row.content, version: String(row.version) }
          : undefined,
      );
    },
    write: (scope, path, content, { expectedVersion }) => {
      const key = `${scope}|${path}`;
      const row = rows.get(key);
      const current = row ? String(row.version) : null;
      if (current !== expectedVersion)
        return AsyncResult.err(
          dbError("serialization", "conflict", {
            hint: "MEMORY_DOCUMENT_CONFLICT",
          }),
        );
      const version = (row?.version ?? 0) + 1;
      rows.set(key, { content, version });
      return AsyncResult.ok({ content, version: String(version) });
    },
    purge: () => AsyncResult.ok(0),
  };
  return { rows, documents };
}

describe("supabaseDocumentBackend", () => {
  it("reads, writes and turns a stale write into eve's conflict", async () => {
    const { rows, documents } = documentStore();
    const backend = supabaseDocumentBackend({
      memory: { documents } as unknown as Memory,
    });
    expect(await backend.read({ key: "notes.md" })).toBeNull();
    const first = await backend.write({
      key: "notes.md",
      content: "a",
      expectedVersion: null,
    });
    expect(first).toEqual({ content: "a", version: "1" });
    expect(rows.has("eve|notes.md")).toBe(true);
    await expect(
      backend.write({ key: "notes.md", content: "b", expectedVersion: null }),
    ).rejects.toBeInstanceOf(MemoryDocumentConflictError);
    expect(await backend.read({ key: "notes.md" })).toEqual(first);
  });

  it("passes the EveDocumentBackend kit", async () => {
    const { documents } = documentStore();
    const backend = supabaseDocumentBackend({
      memory: { documents } as unknown as Memory,
    });
    const report = await testEveDocumentBackend(backend);
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("throws other errors as DbException", async () => {
    const failing = {
      read: () => AsyncResult.err(dbError("network", "down")),
      write: () => AsyncResult.err(dbError("network", "down")),
    };
    const backend = supabaseDocumentBackend({
      memory: { documents: failing } as unknown as Memory,
      scope: "app",
    });
    await expect(backend.read({ key: "a" })).rejects.toBeInstanceOf(
      DbException,
    );
    await expect(
      backend.write({ key: "a", content: "", expectedVersion: "1" }),
    ).rejects.toBeInstanceOf(DbException);
  });
});

function fakeMemory() {
  const { rows, documents } = documentStore();
  const saved: string[] = [];
  const forgotten: string[] = [];
  const memory = {
    documents,
    render: vi.fn(() => AsyncResult.ok("# Core\nprefers metric units")),
    archival: {
      search: vi.fn(() =>
        AsyncResult.ok([{ id: "m1", content: "likes tea", score: 0.9 }]),
      ),
      save: vi.fn((_org: string, content: string) => {
        saved.push(content);
        return AsyncResult.ok({ id: "m2", content });
      }),
      list: vi.fn(() => AsyncResult.ok([{ id: "m1", content: "likes tea" }])),
      forget: vi.fn((id: string) => {
        forgotten.push(id);
        return AsyncResult.ok(true);
      }),
    },
    saveExtracted: vi.fn(() => AsyncResult.ok([])),
  };
  return { memory, rows, saved, forgotten };
}

function memoryCtx(
  auth: EveSessionAuth | null,
  operationId: string,
  text = "what do I like?",
): EveMemoryContext {
  return {
    ...session(auth),
    memory: { scope: { key: "agent:main" } },
    operationId,
    turn: {
      id: "turn_1",
      input: [
        { role: "user", content: [{ type: "text", text }, { type: "image" }] },
        { role: "assistant", content: "ignored" },
      ],
    },
    messages: [{ role: "user", content: text }],
  };
}

describe("supabaseMemory", () => {
  const knowledgeSearch = vi.fn(() =>
    AsyncResult.ok([
      { documentId: "d1", index: 0, title: "Handbook", content: "tea policy" },
      { documentId: "d2", index: 3, title: null, content: "coffee" },
    ]),
  );
  const knowledge = { search: knowledgeSearch } as unknown as Knowledge;

  it("recalls core, archival and knowledge once per operation", async () => {
    const { memory } = fakeMemory();
    const provider = supabaseMemory({
      memory: memory as unknown as Memory,
      knowledge,
      tools: false,
    });
    expect("tools" in provider).toBe(false);
    const first = await provider.recall["turn.started"](memoryCtx(user, "op1"));
    expect(first?.messages.map((message) => message.id)).toEqual([
      "core",
      "memory:m1",
      "knowledge:d1:0",
      "knowledge:d2:3",
    ]);
    expect(first?.messages[2]?.content).toBe("Handbook\ntea policy");
    const replay = await provider.recall["turn.started"](
      memoryCtx(user, "op1"),
    );
    expect(replay).toEqual(first);
    expect(memory.render).toHaveBeenCalledTimes(1);
    expect(memory.archival.search).toHaveBeenCalledWith(
      ORG,
      "what do I like?",
      {
        scope: "agent",
        agentId: await stableUuid("eve-memory:agent:main"),
        ownerId: USER,
      },
      { k: 5 },
    );
    expect(knowledgeSearch).toHaveBeenCalledWith(ORG, "what do I like?", {
      k: 5,
      scopes: [{ scope: "organization" }],
    });
  });

  it("returns the stored recall when a concurrent replay wins", async () => {
    const { memory } = fakeMemory();
    const stored = { messages: [{ id: "core", content: "from the winner" }] };
    let reads = 0;
    memory.documents = {
      ...memory.documents,
      read: () =>
        AsyncResult.ok(
          reads++ === 0
            ? undefined
            : { content: JSON.stringify(stored), version: "1" },
        ),
      write: () =>
        AsyncResult.err(
          dbError("serialization", "conflict", {
            hint: "MEMORY_DOCUMENT_CONFLICT",
          }),
        ),
    };
    const provider = supabaseMemory({ memory: memory as unknown as Memory });
    expect(
      await provider.recall["turn.started"](memoryCtx(user, "race")),
    ).toEqual(stored);

    memory.documents = {
      ...memory.documents,
      read: () => AsyncResult.ok(undefined),
      write: () => AsyncResult.err(dbError("network", "down")),
    };
    await expect(
      provider.recall["turn.started"](memoryCtx(user, "down")),
    ).rejects.toBeInstanceOf(DbException);
  });

  it("recalls nothing without a user or a tenant", async () => {
    const { memory } = fakeMemory();
    const provider = supabaseMemory({ memory: memory as unknown as Memory });
    expect(
      await provider.recall["turn.started"](memoryCtx(null, "op2")),
    ).toBeNull();
    const noTenant = { ...user, attributes: {} };
    expect(
      await provider.recall["turn.started"](memoryCtx(noTenant, "op3")),
    ).toBeNull();
    expect(await provider.tools?.(memoryCtx(null, "op4"))).toBeNull();
    expect(memory.render).not.toHaveBeenCalled();
  });

  it("skips search for an empty turn", async () => {
    const { memory } = fakeMemory();
    const provider = supabaseMemory({
      memory: memory as unknown as Memory,
      knowledge,
    });
    const ctx = { ...memoryCtx(user, "op5"), turn: null };
    expect(await provider.recall["turn.started"](ctx)).toEqual({
      messages: [{ id: "core", content: "# Core\nprefers metric units" }],
    });
    expect(memory.archival.search).not.toHaveBeenCalled();
  });

  it("captures extracted facts once per operation", async () => {
    const { memory } = fakeMemory();
    const extract = vi.fn(() => Promise.resolve(["drinks tea"]));
    const provider = supabaseMemory({
      memory: memory as unknown as Memory,
      extract,
      tools: false,
    });
    const capture = provider.capture?.["turn.completed"];
    await capture?.(memoryCtx(user, "op6"));
    await capture?.(memoryCtx(user, "op6"));
    await capture?.(memoryCtx(null, "op7"));
    expect(extract).toHaveBeenCalledTimes(1);
    expect(memory.saveExtracted).toHaveBeenCalledWith(
      ORG,
      ["drinks tea"],
      expect.objectContaining({ ownerId: USER }),
      { sourceMessageId: "op6" },
    );
  });

  it("builds remember and forget tools scoped to the user", async () => {
    const { memory, saved, forgotten } = fakeMemory();
    const defineTool = vi.fn(
      (definition: Record<string, unknown>) => definition,
    );
    const provider = supabaseMemory({
      memory: memory as unknown as Memory,
      load: () => Promise.resolve({ defineTool }),
    });
    type Tool = { execute(input: Record<string, unknown>): Promise<unknown> };
    const tools = (await provider.tools?.(
      memoryCtx(user, "op8"),
    )) as unknown as Record<string, Tool>;
    expect(Object.keys(tools)).toEqual(["remember", "forget"]);
    expect(await tools["remember"]?.execute({ fact: "has a cat" })).toEqual({
      id: "m2",
    });
    expect(saved).toEqual(["has a cat"]);
    expect(await tools["forget"]?.execute({ id: "memory:m1" })).toEqual({
      deleted: true,
    });
    expect(await tools["forget"]?.execute({ id: "m9" })).toEqual({
      deleted: false,
    });
    expect(forgotten).toEqual(["m1"]);
  });

  it("asks for eve when eve/tools is missing", async () => {
    const { memory } = fakeMemory();
    const provider = supabaseMemory({
      memory: memory as unknown as Memory,
      load: () => Promise.resolve(undefined),
    });
    await expect(provider.tools?.(memoryCtx(user, "op9"))).rejects.toThrow(
      "pnpm add eve",
    );
  });

  it("loads eve/tools from the installed package", async () => {
    const { memory } = fakeMemory();
    const provider = supabaseMemory({ memory: memory as unknown as Memory });
    const tools = await provider.tools?.(memoryCtx(user, "op10"));
    expect(Object.keys(tools ?? {})).toEqual(["remember", "forget"]);
  });
});

function fakeChats(leaf: string | null = "m0") {
  const leafId = leaf ?? undefined;
  const calls: { fn: string; args: unknown[] }[] = [];
  const record =
    <T>(fn: string, value: T) =>
    (...args: unknown[]) => {
      calls.push({ fn, args });
      return AsyncResult.ok(value);
    };
  const chats = {
    chats: {
      create: record("create", { id: "c" }),
      get: record("get", { id: "c", leafId, activeRunId: "run_1" }),
    },
    messages: {
      appendUser: record("appendUser", {}),
      saveAssistant: record("saveAssistant", {}),
    },
    runs: {
      claim: record("claim", {}),
      release: record("release", true),
    },
  };
  return { chats: chats as unknown as AiChat, calls };
}

describe("persistSessions", () => {
  const event = <T>(data: T) => ({ data });

  it("copies a turn into the chat tables", async () => {
    const { chats, calls } = fakeChats();
    const hooks = persistSessions({ chats, agentId: "a1", title: "Support" });
    const ctx = session(user);
    const chatId = await chatIdOf("sess_1");
    await hooks["session.started"](event({}), ctx);
    await hooks["turn.started"](event({ turnId: "t1", sequence: 0 }), ctx);
    await hooks["message.received"](
      event({ turnId: "t1", sequence: 1, message: "hello" }),
      ctx,
    );
    await hooks["message.completed"](
      event({
        turnId: "t1",
        sequence: 2,
        stepIndex: 0,
        message: "calling a tool",
        finishReason: "tool-calls",
      }),
      ctx,
    );
    await hooks["message.completed"](
      event({
        turnId: "t1",
        sequence: 3,
        stepIndex: 1,
        message: "hi",
        finishReason: "stop",
      }),
      ctx,
    );
    await hooks["turn.completed"](event({ turnId: "t1", sequence: 4 }), ctx);

    expect(calls[0]).toEqual({
      fn: "create",
      args: [
        ORG,
        { id: chatId, ownerId: USER, title: "Support", agentId: "a1" },
      ],
    });
    expect(calls.find((call) => call.fn === "claim")?.args).toEqual([
      chatId,
      "eve:sess_1:t1",
      { engine: "eve" },
    ]);
    expect(calls.find((call) => call.fn === "appendUser")?.args).toEqual([
      chatId,
      { id: "t1:1", role: "user", parts: [{ type: "text", text: "hello" }] },
    ]);
    const saved = calls.filter((call) => call.fn === "saveAssistant");
    expect(saved.map((call) => call.args[1])).toEqual([
      {
        id: "t1:0:2",
        role: "assistant",
        parts: [{ type: "text", text: "calling a tool" }],
        metadata: { interim: true },
      },
      {
        id: "t1:1:3",
        role: "assistant",
        parts: [{ type: "text", text: "hi" }],
      },
    ]);
    expect(saved[0]?.args[2]).toMatchObject({
      parentId: "m0",
      status: "complete",
      format: "eve",
      runId: "run_1",
    });
    expect(calls.at(-1)).toEqual({
      fn: "release",
      args: [chatId, "eve:sess_1:t1", { status: "done" }],
    });
  });

  it("releases failed and cancelled turns", async () => {
    const { chats, calls } = fakeChats();
    const hooks = persistSessions({ chats });
    const ctx = session(user);
    await hooks["turn.failed"](
      event({
        turnId: "t2",
        sequence: 0,
        code: "MODEL_ERROR",
        message: "boom",
      }),
      ctx,
    );
    await hooks["turn.cancelled"](event({ turnId: "t3", sequence: 0 }), ctx);
    expect(calls.map((call) => call.args[2])).toEqual([
      { status: "error", error: "MODEL_ERROR: boom" },
      { status: "stopped" },
    ]);
  });

  it("skips sessions without a user, empty messages and chats without a leaf", async () => {
    const { chats, calls } = fakeChats(null);
    const hooks = persistSessions({ chats });
    const anonymous = session(null);
    await hooks["session.started"](event({}), anonymous);
    await hooks["turn.started"](event({ turnId: "t", sequence: 0 }), anonymous);
    await hooks["message.received"](
      event({ turnId: "t", sequence: 1, message: "x" }),
      anonymous,
    );
    await hooks["message.completed"](
      event({
        turnId: "t",
        sequence: 2,
        stepIndex: 0,
        message: "y",
        finishReason: "stop",
      }),
      anonymous,
    );
    await hooks["turn.completed"](
      event({ turnId: "t", sequence: 3 }),
      anonymous,
    );
    expect(calls).toEqual([]);

    const ctx = session(user);
    await hooks["message.received"](
      event({ turnId: "t", sequence: 1, message: "" }),
      ctx,
    );
    await hooks["message.completed"](
      event({
        turnId: "t",
        sequence: 2,
        stepIndex: 0,
        message: "y",
        finishReason: "stop",
      }),
      ctx,
    );
    expect(calls.map((call) => call.fn)).toEqual(["create", "get"]);
  });
});

describe("routeInbox", () => {
  function bridge() {
    const handlers: {
      mention?: (
        thread: EveChatThread,
        message: EveChatMessage,
      ) => Promise<void>;
      subscribed?: (
        thread: EveChatThread,
        message: EveChatMessage,
      ) => Promise<void>;
    } = {};
    const send = vi.fn(() => Promise.resolve(undefined));
    return {
      handlers,
      send,
      value: {
        bot: {
          onNewMention: (handler: NonNullable<typeof handlers.mention>) => {
            handlers.mention = handler;
          },
          onSubscribedMessage: (
            handler: NonNullable<typeof handlers.subscribed>,
          ) => {
            handlers.subscribed = handler;
          },
        },
        send,
      },
    };
  }

  const conversation = (botMode: string) =>
    vi.fn(() =>
      AsyncResult.ok({
        id: "conv_1",
        tenant: ORG,
        contactId: "contact_1",
        subject: "Billing",
        botMode,
      }),
    );
  const inbox = (get: ReturnType<typeof conversation>) =>
    ({ conversations: { get } }) as unknown as Inbox;

  it("sends bot-mode conversations to eve as the contact", async () => {
    const b = bridge();
    routeInbox(b.value, { inbox: inbox(conversation("bot")) });
    const subscribe = vi.fn(() => Promise.resolve());
    const thread = { id: "inbox:conv_1", subscribe };
    await b.handlers.mention?.(thread, { text: "hi" });
    expect(subscribe).toHaveBeenCalled();
    expect(b.send).toHaveBeenCalledWith("hi", {
      thread,
      auth: {
        authenticator: "inbox",
        principalType: "contact",
        principalId: "contact_1",
        attributes: { tenantId: ORG, conversationId: "conv_1" },
      },
      title: "Billing",
    });
  });

  it("leaves human-mode conversations and other threads alone", async () => {
    const b = bridge();
    const get = conversation("human");
    routeInbox(b.value, { inbox: inbox(get), title: "Support" });
    const subscribe = () => Promise.resolve();
    await b.handlers.subscribed?.(
      { id: "inbox:conv_1", subscribe },
      { text: "hi" },
    );
    await b.handlers.subscribed?.(
      { id: "slack:C1:1", subscribe },
      { text: "hi" },
    );
    expect(b.send).not.toHaveBeenCalled();
    expect(get).toHaveBeenCalledTimes(1);
  });
});

describe("stableUuid", () => {
  it("returns the same version 8 UUID for the same input", async () => {
    const id = await stableUuid("a");
    expect(id).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
    expect(await stableUuid("a")).toBe(id);
    expect(await stableUuid("b")).not.toBe(id);
    expect(await chatIdOf("s")).toBe(await stableUuid("eve-session:s"));
  });
});

describe("eve on the Supabase World", () => {
  it("runs a Workflow spec version the World supports", async () => {
    const require = createRequire(import.meta.url);
    const root = dirname(require.resolve("eve/package.json"));
    const chunks = join(root, "dist/src/compiled/_chunks/workflow");
    const versions = new Set<number>();
    for (const file of await readdir(chunks)) {
      if (!file.endsWith(".js")) continue;
      const source = await readFile(join(chunks, file), "utf8");
      for (const match of source.matchAll(
        /SPEC_VERSION_MAX_SUPPORTED:\(\)=>(\d+)/g,
      ))
        versions.add(Number(match[1]));
    }
    expect([...versions]).toEqual([Number(SPEC_VERSION_MAX_SUPPORTED)]);
  });
});
