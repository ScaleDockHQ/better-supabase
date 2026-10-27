import type { Experimental_SandboxSession } from "ai";

import { describe, expect, it } from "vitest";

import type {
  AiSandbox,
  NewAiSandbox,
} from "../../src/blocks/ai-chat/index.ts";
import type { CredentialProvider } from "../../src/credentials/index.ts";
import type {
  VercelSandboxInstance,
  VercelSandboxModule,
} from "../../src/vercel-sandbox/index.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  AI_GATEWAY_HOST,
  brokered,
  gatewayOnly,
  mergeSandboxOptions,
  untrusted,
  vercelSandboxes,
} from "../../src/vercel-sandbox/index.ts";

function apiError(status: number): Error {
  return Object.assign(new Error(`HTTP ${status}`), {
    response: new Response(null, { status }),
  });
}

function row(over: Partial<AiSandbox> = {}): AiSandbox {
  const at = Temporal.Instant.fromEpochMilliseconds(0);

  return {
    id: "row_1",
    organizationId: "org_1",
    userId: undefined,
    chatId: "chat_1",
    harnessId: undefined,
    provider: "vercel",
    sandboxId: "chat-chat_1",
    containerId: undefined,
    status: "running",
    metadata: {},
    idleSeconds: 600,
    error: undefined,
    lastUsedAt: at,
    expiresAt: undefined,
    stoppedAt: undefined,
    createdAt: at,
    ...over,
  };
}

function fakeRegistry(): {
  sandboxes: {
    register: (org: string, input: NewAiSandbox) => AsyncResult<AiSandbox>;
    touch: (id: string) => AsyncResult<boolean>;
  };
  registered: [string, NewAiSandbox][];
  touched: string[];
} {
  const registered: [string, NewAiSandbox][] = [];
  const touched: string[] = [];

  return {
    registered,
    touched,
    sandboxes: {
      register: (org, input) => {
        registered.push([org, input]);

        return AsyncResult.ok(row({ sandboxId: input.sandboxId }));
      },
      touch: (id) => {
        touched.push(id);

        return AsyncResult.ok(true);
      },
    },
  };
}

interface FakeSdk {
  module: VercelSandboxModule;
  calls: unknown[][];
}

function fakeSdk(
  options: { exists?: boolean; fail?: Error; getFail?: Error } = {},
): FakeSdk {
  const calls: unknown[][] = [];

  const instance = (name: string): VercelSandboxInstance => ({
    name,
    stop: async () => {
      calls.push(["stop", name]);
    },
    update: async (params) => {
      calls.push(["update", name, params]);
    },
  });

  return {
    calls,
    module: {
      Sandbox: {
        getOrCreate: async (params) => {
          calls.push(["getOrCreate", params]);

          if (options.fail) {
            throw options.fail;
          }

          if (!options.exists && typeof params["onCreate"] === "function") {
            await (params["onCreate"] as () => Promise<void>)();
          }

          return instance(String(params["name"]));
        },
        get: async ({ name }) => {
          calls.push(["get", name]);

          if (options.getFail) {
            throw options.getFail;
          }

          return instance(name);
        },
      },
    },
  };
}

class FakeSession {
  readonly description = "fake";
  readonly sandbox: VercelSandboxInstance;

  constructor(sandbox: VercelSandboxInstance) {
    this.sandbox = sandbox;
  }

  run(): Promise<{ exitCode: number; stdout: string; stderr: string }> {
    return Promise.resolve({ exitCode: 0, stdout: "", stderr: "" });
  }
}

const sessions = {
  createVercelNetworkSandboxSessionFromNativeSandbox: (
    sandbox: VercelSandboxInstance,
  ) =>
    // SAFETY: the tests only call run on the fake session.
    new FakeSession(sandbox) as unknown as Experimental_SandboxSession,
};

describe("vercelSandboxes", () => {
  it("creates the chat's sandbox, registers it and tracks the session", async () => {
    const registry = fakeRegistry();
    const sdk = fakeSdk();

    const adapter = vercelSandboxes({
      sandboxes: registry.sandboxes,
      defaults: untrusted,
      load: async () => sdk.module,
      loadSession: async () => sessions,
    });

    const result = await adapter.forChat("org_1", "chat_1", {
      userId: "user_1",
      idleSeconds: 120,
      create: { timeout: 60_000 },
    });

    expect(result.ok).toBe(true);
    expect(registry.registered).toEqual([
      [
        "org_1",
        {
          provider: "vercel",
          sandboxId: "chat-chat_1",
          chatId: "chat_1",
          userId: "user_1",
          idleSeconds: 120,
        },
      ],
    ]);
    expect(sdk.calls[0]?.[1]).toMatchObject({
      name: "chat-chat_1",
      networkPolicy: "deny-all",
      persistent: false,
      timeout: 60_000,
    });
    expect(sdk.calls.some(([call]) => call === "update")).toBe(false);

    await result.data?.session.run({ command: "true" });
    expect(registry.touched).toEqual(["row_1"]);
  });

  it("reuses an existing sandbox and refreshes its network policy", async () => {
    const registry = fakeRegistry();
    const sdk = fakeSdk({ exists: true });

    const adapter = vercelSandboxes({
      sandboxes: registry.sandboxes,
      load: async () => sdk.module,
      loadSession: async () => sessions,
    });

    const networkPolicy = gatewayOnly("vck_1");

    const result = await adapter.forChat("org_1", "chat_1", {
      create: { networkPolicy },
    });

    expect(result.ok).toBe(true);
    expect(sdk.calls).toContainEqual([
      "update",
      "chat-chat_1",
      { networkPolicy },
    ]);
  });

  it("returns the sandbox error as a DbError", async () => {
    const adapter = vercelSandboxes({
      sandboxes: fakeRegistry().sandboxes,
      load: async () => fakeSdk({ fail: apiError(429) }).module,
      loadSession: async () => sessions,
    });

    const result = await adapter.forChat("org_1", "chat_1");

    expect(result.error).toMatchObject({
      kind: "rate_limited",
      hint: "AI_SANDBOX_LIMIT",
    });
  });

  it("stops before creating when the registry refuses the chat", async () => {
    const sdk = fakeSdk();

    const adapter = vercelSandboxes({
      sandboxes: {
        ...fakeRegistry().sandboxes,
        register: () =>
          AsyncResult.err(
            dbError("forbidden", "other tenant", {
              hint: "AI_SANDBOX_FORBIDDEN",
            }),
          ),
      },
      load: async () => sdk.module,
      loadSession: async () => sessions,
    });

    const result = await adapter.forChat("org_1", "chat_1");

    expect(result.error?.hint).toBe("AI_SANDBOX_FORBIDDEN");
    expect(sdk.calls).toEqual([]);
  });

  it("says what to install when a peer is missing", async () => {
    const adapter = vercelSandboxes({
      sandboxes: fakeRegistry().sandboxes,
      load: async () => ({}),
      loadSession: async () => sessions,
    });

    const result = await adapter.forChat("org_1", "chat_1");

    expect(result.error).toMatchObject({
      kind: "unsupported",
      hint: "AI_SANDBOX_UNAVAILABLE",
    });
    expect(result.error?.message).toContain("pnpm add @vercel/sandbox");

    const noSessions = vercelSandboxes({
      sandboxes: fakeRegistry().sandboxes,
      load: async () => fakeSdk().module,
      loadSession: async () => undefined,
    });

    expect(
      (await noSessions.forChat("org_1", "chat_1")).error?.message,
    ).toContain("@ai-sdk/sandbox-vercel");
  });

  it("wraps a sandbox the app created as a tracked session", async () => {
    const registry = fakeRegistry();

    const adapter = vercelSandboxes({
      sandboxes: registry.sandboxes,
      loadSession: async () => sessions,
    });

    const sandbox: VercelSandboxInstance = {
      name: "harness-1",
      stop: async () => {},
      update: async () => {},
    };

    const session = await adapter.session(sandbox, { id: "row_9" }).orThrow();
    await session.run({ command: "true" });

    expect(registry.touched).toEqual(["row_9"]);
  });

  it("stops a sandbox by name and treats one Vercel lost as stopped", async () => {
    const sdk = fakeSdk();

    const adapter = vercelSandboxes({
      sandboxes: fakeRegistry().sandboxes,
      load: async () => sdk.module,
    });

    await adapter.stop(row());
    expect(sdk.calls).toEqual([
      ["get", "chat-chat_1"],
      ["stop", "chat-chat_1"],
    ]);

    const gone = vercelSandboxes({
      sandboxes: fakeRegistry().sandboxes,
      load: async () => fakeSdk({ getFail: apiError(404) }).module,
    });

    await expect(gone.stop(row())).resolves.toBeUndefined();

    const down = vercelSandboxes({
      sandboxes: fakeRegistry().sandboxes,
      load: async () => fakeSdk({ getFail: apiError(503) }).module,
    });

    await expect(down.stop(row())).rejects.toThrow("HTTP 503");
  });
});

describe("network presets", () => {
  it("gatewayOnly reaches only the gateway, with the token added at the firewall", () => {
    expect(gatewayOnly("vck_1")).toEqual({
      allow: {
        [AI_GATEWAY_HOST]: [
          { transform: [{ headers: { authorization: "Bearer vck_1" } }] },
        ],
      },
    });
  });

  it("mergeSandboxOptions keeps the shortest timeout", () => {
    expect(
      mergeSandboxOptions(untrusted, { timeout: 900_000, vcpus: 2 }),
    ).toMatchObject({ timeout: 300_000, vcpus: 2, networkPolicy: "deny-all" });
    expect(mergeSandboxOptions(untrusted, { timeout: 1000 }).timeout).toBe(
      1000,
    );
  });

  it("brokered allows one domain and ends before the token expires", async () => {
    const asked: unknown[] = [];

    const credentials: Pick<CredentialProvider, "getToken"> = {
      getToken: (ref, options) => {
        asked.push([ref, options]);

        return AsyncResult.ok({
          token: "gho_1",
          headers: { authorization: "Bearer gho_1" },
          expiresAt: Temporal.Instant.fromEpochMilliseconds(600_000),
        });
      },
    };

    const ref = { provider: "vercel-connect", connector: "github" };
    const subject = { type: "user", id: "user_1" } as const;

    const options = await brokered(credentials, ref, {
      domain: "api.github.com",
      subject,
      now: () => 0,
    }).orThrow();

    expect(options).toEqual({
      networkPolicy: {
        allow: {
          "api.github.com": [
            { transform: [{ headers: { authorization: "Bearer gho_1" } }] },
          ],
        },
      },
      timeout: 540_000,
    });
    expect(asked).toEqual([[ref, { subject }]]);
  });

  it("brokered passes the provider's error through", async () => {
    const result = await brokered(
      {
        getToken: () =>
          AsyncResult.err(dbError("unauthorized", "not connected")),
      },
      { provider: "vercel-connect", connector: "github" },
      { domain: "api.github.com", subject: { type: "user", id: "user_1" } },
    );

    expect(result.error?.kind).toBe("unauthorized");
  });
});
