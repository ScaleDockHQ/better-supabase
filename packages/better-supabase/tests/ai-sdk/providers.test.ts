import type { Experimental_SandboxSession } from "ai";

import { describe, expect, it, vi } from "vitest";

import type { ResolvedProviderKey } from "../../src/blocks/ai-providers/index.ts";

import {
  byokOptions,
  tenantGatewayOptions,
  trackedSandbox,
} from "../../src/ai-sdk/index.ts";
import { AsyncResult } from "../../src/core/result.ts";

const key = (over: Partial<ResolvedProviderKey> = {}): ResolvedProviderKey => ({
  provider: "anthropic",
  name: "default",
  token: "sk-1",
  headers: {},
  settings: {},
  ...over,
});

describe("byokOptions", () => {
  it("groups keys by provider with their settings", () => {
    expect(
      byokOptions([
        key(),
        key({
          name: "backup",
          token: "sk-2",
          settings: { region: "eu", skip: undefined },
        }),
        key({
          provider: "bedrock",
          token: "AKIA",
          settings: { credentialField: "accessKeyId", region: "us-east-1" },
        }),
      ]),
    ).toEqual({
      byok: {
        anthropic: [{ apiKey: "sk-1" }, { region: "eu", apiKey: "sk-2" }],
        bedrock: [{ region: "us-east-1", accessKeyId: "AKIA" }],
      },
    });
    expect(byokOptions([])).toEqual({});
  });
});

describe("tenantGatewayOptions", () => {
  it("adds the tenant's keys to the gateway options", async () => {
    const resolve = vi.fn(() => AsyncResult.ok([key()]));
    const options = await tenantGatewayOptions(
      { keys: { resolve } as never },
      { organizationId: "o1", userId: "u1" },
      { order: ["anthropic"] },
      { providers: ["anthropic"] },
    ).orThrow();
    expect(resolve).toHaveBeenCalledWith("o1", { providers: ["anthropic"] });
    expect(options).toEqual({
      gateway: {
        order: ["anthropic"],
        byok: { anthropic: [{ apiKey: "sk-1" }] },
        user: "u1",
        tags: ["org:o1"],
      },
    });
  });
});

describe("trackedSandbox", () => {
  it("touches the registry row on use, at most every interval", async () => {
    let now = 0;
    const touch = vi.fn(() => AsyncResult.ok(true));
    class Session {
      readonly id = "sbx";
      run(command: string) {
        return Promise.resolve(`ran ${command} in ${this.id}`);
      }
    }
    const session = new Session() as unknown as Experimental_SandboxSession;
    const tracked = trackedSandbox(session, {
      sandboxes: { touch },
      id: "s1",
      every: 1000,
      now: () => now,
    }) as unknown as Session;
    expect(await tracked.run("ls")).toBe("ran ls in sbx");
    now = 500;
    await tracked.run("ls");
    now = 1500;
    await tracked.run("ls");
    expect(tracked.id).toBe("sbx");
    expect(touch).toHaveBeenCalledTimes(2);
    expect(touch).toHaveBeenCalledWith("s1");
  });
});
