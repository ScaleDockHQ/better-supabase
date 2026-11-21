import { describe, expect, it, vi } from "vitest";

import type { BotIdVerdict } from "../../src/vercel-security/vercel-security.ts";

import {
  botIdCheck,
  botIdGuard,
  firewallRateLimit,
  firewallRateLimiter,
} from "../../src/vercel-security/vercel-security.ts";

const BOT: BotIdVerdict = {
  isHuman: false,
  isBot: true,
  isVerifiedBot: false,
  bypassed: false,
};

const HUMAN: BotIdVerdict = { ...BOT, isHuman: true, isBot: false };
const request = () => new Request("https://app.test/auth/sign-up");

describe("onVerdict", () => {
  it("reports BotID outcomes without changing them", async () => {
    const onVerdict = vi.fn(() => {
      throw new Error("sink down");
    });

    const refused = botIdGuard({ checkBotId: async () => BOT, onVerdict });
    expect((await refused(request()))?.status).toBe(403);
    expect(onVerdict).toHaveBeenLastCalledWith(
      expect.objectContaining({ outcome: "refused", hint: "BOT_DETECTED" }),
    );

    const allowed = botIdGuard({ checkBotId: async () => HUMAN, onVerdict });
    expect(await allowed(request())).toBeUndefined();
    expect(onVerdict).toHaveBeenLastCalledWith(
      expect.objectContaining({ outcome: "allowed", verdict: HUMAN }),
    );
  });

  it("ignores a rejecting handler and reports a failed check", async () => {
    const onVerdict = vi.fn(async () => {
      throw new Error("sink down");
    });

    const error = await botIdCheck({
      checkBotId: async () => {
        throw new Error("down");
      },
      onVerdict,
    })();

    expect(error?.hint).toBe("BOT_CHECK_FAILED");
    expect(onVerdict).toHaveBeenCalledWith(
      expect.objectContaining({ outcome: "error", request: undefined }),
    );
  });

  it("reports Firewall outcomes", async () => {
    const onVerdict = vi.fn();

    const guard = firewallRateLimit({
      id: "signup",
      checkRateLimit: async () => ({ rateLimited: true }),
      onVerdict,
    });

    expect((await guard(request()))?.status).toBe(429);
    expect(onVerdict).toHaveBeenCalledWith(
      expect.objectContaining({ outcome: "refused", hint: "RATE_LIMITED" }),
    );
  });
});

describe("firewallRateLimiter", () => {
  it("passes the scope as the rule id and the key as the rate limit key", async () => {
    const checkRateLimit = vi.fn(async () => ({ rateLimited: false }));
    const limiter = firewallRateLimiter({ checkRateLimit, timeout: 500 });

    const checked = await limiter.check("login", "ada@x.test");

    expect(checkRateLimit).toHaveBeenCalledWith("login", {
      rateLimitKey: "ada@x.test",
      timeout: 500,
    });
    expect(checked).toMatchObject({
      ok: true,
      data: { allowed: true, remaining: 1, retryAfter: 0 },
    });
  });

  it("refuses a limited key with the retry delay", async () => {
    const limiter = firewallRateLimiter({
      checkRateLimit: async () => ({ rateLimited: true }),
      retryAfter: 30,
    });

    expect(await limiter.check("login", "k")).toMatchObject({
      ok: true,
      data: { allowed: false, remaining: 0, retryAfter: 30 },
    });
  });

  it("returns an error for a blocked request, an unknown rule and an outage", async () => {
    const answer = (result: "blocked" | "not-found" | "throw") =>
      firewallRateLimiter({
        checkRateLimit: async () => {
          if (result === "throw") {
            throw new Error("down");
          }

          return { rateLimited: false, error: result };
        },
      }).check("login", "k");

    expect(await answer("blocked")).toMatchObject({
      ok: false,
      error: { hint: "FIREWALL_BLOCKED" },
    });
    expect(await answer("not-found")).toMatchObject({
      ok: false,
      error: { hint: "FIREWALL_RULE_NOT_FOUND" },
    });
    expect(await answer("throw")).toMatchObject({
      ok: false,
      error: { hint: "FIREWALL_UNAVAILABLE" },
    });
  });
});
