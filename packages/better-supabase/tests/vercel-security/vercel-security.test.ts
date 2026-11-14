import { describe, expect, it, vi } from "vitest";

import type {
  BotIdConfig,
  BotIdVerdict,
  CheckRateLimit,
  FirewallRateLimitResult,
  VercelGuard,
} from "../../src/vercel-security/vercel-security.ts";

import {
  botIdCheck,
  botIdGuard,
  firewallRateLimit,
  combineGuards,
  withGuards,
} from "../../src/vercel-security/vercel-security.ts";

const HUMAN: BotIdVerdict = {
  isHuman: true,
  isBot: false,
  isVerifiedBot: false,
  bypassed: false,
};

const BOT: BotIdVerdict = {
  isHuman: false,
  isBot: true,
  isVerifiedBot: false,
  bypassed: false,
};

const VERIFIED_BOT: BotIdVerdict = {
  ...BOT,
  isVerifiedBot: true,
  verifiedBotName: "googlebot",
};

const request = (headers: Record<string, string> = {}) =>
  new Request("https://app.test/auth/sign-up", {
    method: "POST",
    headers: { "user-agent": "test", ...headers },
  });

const answering = (verdict: BotIdVerdict) =>
  vi.fn(async (_config?: BotIdConfig) => verdict);

const limiting = (result: FirewallRateLimitResult) =>
  vi.fn<CheckRateLimit>(async () => result);

async function bodyOf(response: Response | undefined) {
  return (await response?.json()) as Record<string, unknown>;
}

describe("botIdGuard", () => {
  it("lets a human through and passes the request headers to BotID", async () => {
    const checkBotId = answering(HUMAN);

    expect(await botIdGuard({ checkBotId })(request())).toBeUndefined();
    expect(checkBotId).toHaveBeenCalledWith({
      advancedOptions: {
        headers: expect.objectContaining({ "user-agent": "test" }),
      },
    });
  });

  it("refuses a bot with a problem+json 403 and the hint BOT_DETECTED", async () => {
    const response = await botIdGuard({ checkBotId: answering(BOT) })(
      request(),
    );

    expect(response?.status).toBe(403);
    expect(response?.headers.get("content-type")).toBe(
      "application/problem+json",
    );
    expect(await bodyOf(response)).toMatchObject({
      status: 403,
      kind: "forbidden",
      hint: "BOT_DETECTED",
      instance: "/auth/sign-up",
    });
  });

  it("lets a verified bot through only with allowVerifiedBots", async () => {
    const checkBotId = answering(VERIFIED_BOT);

    expect((await botIdGuard({ checkBotId })(request()))?.status).toBe(403);
    expect(
      await botIdGuard({ checkBotId, allowVerifiedBots: true })(request()),
    ).toBeUndefined();
  });

  it("passes config through and keeps headers the app set", async () => {
    const checkBotId = answering(HUMAN);

    const config: BotIdConfig = {
      developmentOptions: { bypass: "HUMAN" },
      advancedOptions: { checkLevel: "basic", headers: { host: "x.test" } },
    };

    await botIdGuard({ checkBotId, config })(request());
    expect(checkBotId).toHaveBeenCalledWith(config);

    await botIdGuard({
      checkBotId,
      config: { advancedOptions: { checkLevel: "deepAnalysis" } },
    })(request());

    expect(checkBotId).toHaveBeenLastCalledWith({
      advancedOptions: {
        checkLevel: "deepAnalysis",
        headers: expect.objectContaining({ "user-agent": "test" }),
      },
    });
  });

  it("refuses with a 503 when BotID throws, unless onError is allow", async () => {
    const checkBotId = vi.fn(async () => {
      throw new Error("BotID is down");
    });

    const denied = await botIdGuard({ checkBotId })(request());
    expect(denied?.status).toBe(503);
    expect(await bodyOf(denied)).toMatchObject({
      kind: "network",
      hint: "BOT_CHECK_FAILED",
    });

    expect(
      await botIdGuard({ checkBotId, onError: "allow" })(request()),
    ).toBeUndefined();
  });

  it("formats the body with problem", async () => {
    const response = await botIdGuard({
      checkBotId: answering(BOT),
      problem: (problem, error) => ({ code: error.hint, at: problem.status }),
    })(request());

    expect(response?.status).toBe(403);
    expect(await bodyOf(response)).toEqual({ code: "BOT_DETECTED", at: 403 });
  });
});

describe("botIdCheck", () => {
  it("resolves to the DbError for a bot and undefined for a human", async () => {
    expect(
      await botIdCheck({ checkBotId: answering(HUMAN) })(),
    ).toBeUndefined();
    expect(await botIdCheck({ checkBotId: answering(BOT) })()).toMatchObject({
      kind: "forbidden",
      status: 403,
      hint: "BOT_DETECTED",
    });
  });

  it("calls BotID without headers, which reads the request context", async () => {
    const checkBotId = answering(HUMAN);

    await botIdCheck({ checkBotId })();
    expect(checkBotId).toHaveBeenCalledWith(undefined);
  });

  it("returns the 503 error when BotID throws", async () => {
    const check = botIdCheck({
      checkBotId: () => Promise.reject(new Error("down")),
    });

    expect(await check()).toMatchObject({
      kind: "network",
      hint: "BOT_CHECK_FAILED",
    });
  });
});

describe("firewallRateLimit", () => {
  it("lets a request under the limit through", async () => {
    const checkRateLimit = limiting({ rateLimited: false });
    const incoming = request();

    expect(
      await firewallRateLimit({ checkRateLimit, id: "sign-up" })(incoming),
    ).toBeUndefined();
    expect(checkRateLimit).toHaveBeenCalledWith("sign-up", {
      request: incoming,
    });
  });

  it("passes the key and the timeout", async () => {
    const checkRateLimit = limiting({ rateLimited: false });
    const incoming = request({ "x-email": "a@b.test" });

    await firewallRateLimit({
      checkRateLimit,
      id: "otp",
      key: (req) => req.headers.get("x-email") ?? undefined,
      timeout: 1000,
    })(incoming);

    expect(checkRateLimit).toHaveBeenCalledWith("otp", {
      request: incoming,
      rateLimitKey: "a@b.test",
      timeout: 1000,
    });
  });

  it("refuses a limited request with a 429 and Retry-After", async () => {
    const checkRateLimit = limiting({ rateLimited: true });

    const response = await firewallRateLimit({ checkRateLimit, id: "otp" })(
      request(),
    );

    expect(response?.status).toBe(429);
    expect(response?.headers.get("retry-after")).toBe("60");
    expect(await bodyOf(response)).toMatchObject({
      kind: "rate_limited",
      retryAfter: 60,
      instance: "/auth/sign-up",
    });

    const custom = await firewallRateLimit({
      checkRateLimit,
      id: "otp",
      retryAfter: 9.2,
    })(request());

    expect(custom?.headers.get("retry-after")).toBe("10");
  });

  it("refuses a request the Firewall blocked with a 403", async () => {
    const response = await firewallRateLimit({
      checkRateLimit: limiting({ rateLimited: false, error: "blocked" }),
      id: "otp",
    })(request());

    expect(response?.status).toBe(403);
    expect(await bodyOf(response)).toMatchObject({ hint: "FIREWALL_BLOCKED" });
  });

  it("lets a request through when the rule is missing, unless onError is deny", async () => {
    const checkRateLimit = limiting({ rateLimited: false, error: "not-found" });

    expect(
      await firewallRateLimit({ checkRateLimit, id: "missing" })(request()),
    ).toBeUndefined();

    const denied = await firewallRateLimit({
      checkRateLimit,
      id: "missing",
      onError: "deny",
    })(request());

    expect(denied?.status).toBe(503);
    expect(await bodyOf(denied)).toMatchObject({
      hint: "FIREWALL_RULE_NOT_FOUND",
    });
  });

  it("follows onError when the check throws", async () => {
    const checkRateLimit = vi.fn<CheckRateLimit>(async () => {
      throw new Error("TimeoutError");
    });

    expect(
      await firewallRateLimit({ checkRateLimit, id: "otp" })(request()),
    ).toBeUndefined();

    const denied = await firewallRateLimit({
      checkRateLimit,
      id: "otp",
      onError: "deny",
    })(request());

    expect(denied?.status).toBe(503);
    expect(await bodyOf(denied)).toMatchObject({
      hint: "FIREWALL_UNAVAILABLE",
    });
  });

  it("follows onError when the key function throws", async () => {
    const guarded = firewallRateLimit({
      checkRateLimit: limiting({ rateLimited: false }),
      id: "otp",
      key: () => {
        throw new Error("bad body");
      },
    });

    expect(await guarded(request())).toBeUndefined();
  });

  it("formats the body with problem", async () => {
    const response = await firewallRateLimit({
      checkRateLimit: limiting({ rateLimited: true }),
      id: "otp",
      problem: (_, error) => ({ error: error.kind }),
    })(request());

    expect(response?.headers.get("retry-after")).toBe("60");
    expect(await bodyOf(response)).toEqual({ error: "rate_limited" });
  });
});

describe("combineGuards and withGuards", () => {
  const pass: VercelGuard = async () => undefined;

  const refuse =
    (status: number): VercelGuard =>
    async () =>
      new Response(null, { status });

  it("runs guards in order and stops at the first refusal", async () => {
    const after = vi.fn(pass);
    const combined = combineGuards(pass, refuse(429), after, refuse(403));

    expect((await combined(request()))?.status).toBe(429);
    expect(after).not.toHaveBeenCalled();
    expect(await combineGuards(pass, pass)(request())).toBeUndefined();
    expect(await combineGuards()(request())).toBeUndefined();
  });

  it("answers the refusal instead of calling the handler", async () => {
    const handler = vi.fn(async () => new Response("created", { status: 201 }));

    const refused = await withGuards(handler, pass, refuse(429))(request());
    expect(refused.status).toBe(429);
    expect(handler).not.toHaveBeenCalled();

    const allowed = await withGuards(handler, pass)(request());
    expect(allowed.status).toBe(201);
  });

  it("passes the route context through to the handler", async () => {
    const handler = vi.fn(
      (_request: Request, _context: { params: Promise<{ id: string }> }) =>
        new Response(null, { status: 204 }),
    );

    const context = { params: Promise.resolve({ id: "1" }) };
    const incoming = request();

    await withGuards(handler, pass)(incoming, context);
    expect(handler).toHaveBeenCalledWith(incoming, context);
  });

  it("composes the BotID and Firewall guards on a route", async () => {
    const checkBotId = answering(HUMAN);
    const checkRateLimit = limiting({ rateLimited: true });

    const route = withGuards(
      async () => new Response("ok"),
      botIdGuard({ checkBotId }),
      firewallRateLimit({ checkRateLimit, id: "sign-up" }),
    );

    expect((await route(request())).status).toBe(429);
    expect(checkBotId).toHaveBeenCalledOnce();
  });
});
