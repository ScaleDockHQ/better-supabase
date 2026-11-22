import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it, vi } from "vitest";

import type { RequestContext } from "../../src/core/plugin.ts";
import type {
  EveApprovalContext,
  EveSessionAuth,
  EveToolContext,
} from "../../src/eve/index.ts";

import { dbError, DbException } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  eveContext,
  strictestApproval,
  supabaseTool,
  tenantToolApproval,
} from "../../src/eve/index.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const ORG = "22222222-2222-4222-8222-222222222222";

const user: EveSessionAuth = {
  authenticator: "supabase",
  principalType: "user",
  principalId: USER,
  attributes: { tenantId: ORG, roles: ["member"], isAnonymous: "false" },
};

const contact: EveSessionAuth = {
  authenticator: "inbox",
  principalType: "contact",
  principalId: "contact_1",
  attributes: { tenantId: ORG },
};

const app: EveSessionAuth = {
  authenticator: "app",
  principalType: "runtime",
  principalId: "eve:app",
  attributes: {},
};

const title: StandardSchemaV1<{ title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    // SAFETY: the tests only pass `{ title }` inputs.
    validate: (value) => ({ value: value as { title: string } }),
  },
};

const toolCtx = (auth: EveSessionAuth | null): EveToolContext => ({
  session: { id: "sess_1", auth: { current: auth, initiator: auth } },
  callId: "call_1",
  toolName: "create_task",
});

const approvalCtx = (auth: EveSessionAuth | null): EveApprovalContext => ({
  ...toolCtx(auth),
  toolInput: { title: "Ship it" },
});

const forbidden = (fn: () => unknown) => {
  try {
    fn();
  } catch (error) {
    return error;
  }

  return;
};

describe("eveContext", () => {
  it("runs a Supabase user as the user, with the agent as the act claim", () => {
    expect(
      eveContext(user, {
        agent: "planner",
        tools: ["create_task"],
        readOnly: false,
      }),
    ).toEqual({
      actor: { id: USER, kind: "user" },
      tenant: ORG,
      claims: {
        sub: USER,
        tenant_id: ORG,
        act: {
          kind: "agent",
          sub: "planner",
          tools: ["create_task"],
          read_only: false,
        },
      },
    });
  });

  it("lends the agent the scopes it names", () => {
    expect(
      eveContext(user, { agent: "planner", scopes: ["tasks.*"] }).claims,
    ).toEqual({
      sub: USER,
      tenant_id: ORG,
      scope: ["tasks.*"],
      act: { kind: "agent", sub: "planner" },
    });
  });

  it("derives the scope claim from permission and merges it with scopes", () => {
    expect(
      eveContext(user, { agent: "planner", permission: "tasks.write" }).claims,
    ).toMatchObject({ scope: ["tasks.write"] });

    expect(
      eveContext(user, {
        agent: "planner",
        scopes: ["tasks.*", "tasks.write"],
        permission: ["tasks.write", "files.read"],
      }).claims,
    ).toMatchObject({ scope: ["tasks.*", "tasks.write", "files.read"] });
  });

  it("refuses a contact, the app principal and a missing one", () => {
    for (const auth of [contact, app, null]) {
      const error = forbidden(() => eveContext(auth, { agent: "planner" }));

      expect(error).toBeInstanceOf(DbException);
      expect(error).toMatchObject({ kind: "forbidden", hint: "EVE_NO_USER" });
    }
  });

  it("refuses a user principal from another authenticator", () => {
    expect(() =>
      eveContext({ ...user, authenticator: "vercel" }, { agent: "planner" }),
    ).toThrow(DbException);

    expect(
      eveContext(
        { ...user, authenticator: "vercel" },
        { agent: "planner", authenticator: "vercel" },
      ).actor,
    ).toEqual({ id: USER, kind: "user" });
  });

  it("runs another principal as runAs", () => {
    expect(
      eveContext(app, {
        agent: "digest",
        runAs: { userId: USER, tenant: ORG },
      }),
    ).toMatchObject({ actor: { id: USER }, tenant: ORG });

    const runAs = vi.fn((auth: EveSessionAuth | null) =>
      auth?.principalType === "contact" ? undefined : { userId: USER },
    );

    expect(eveContext(app, { agent: "digest", runAs }).tenant).toBeUndefined();
    expect(() => eveContext(contact, { agent: "digest", runAs })).toThrow(
      DbException,
    );
  });
});

describe("supabaseTool", () => {
  const server = (result: AsyncResult<{ readonly tasks: string[] }>) => {
    const contexts: RequestContext[] = [];

    return {
      contexts,
      forContext: vi.fn(
        (
          context: RequestContext,
          _options?: { readonly permissions?: readonly string[] },
        ) => {
          contexts.push(context);

          return result;
        },
      ),
    };
  };

  it("runs execute with the user's repositories", async () => {
    const db = { tasks: [] as string[] };
    const runner = server(AsyncResult.ok(db));

    const tool = supabaseTool({
      server: runner,
      agent: "planner",
      description: "Creates a task",
      inputSchema: title,
      permissions: ["tasks.write"],
      execute: (input, call) => {
        call.db.tasks.push(input.title);

        return { created: input.title, tenant: call.context.tenant };
      },
    });

    expect(tool.approval).toBeUndefined();
    await expect(
      tool.execute({ title: "Ship it" }, toolCtx(user)),
    ).resolves.toEqual({ created: "Ship it", tenant: ORG });
    expect(db.tasks).toEqual(["Ship it"]);
    expect(runner.forContext).toHaveBeenCalledWith(
      expect.objectContaining({ actor: { id: USER, kind: "user" } }),
      { reason: "eve", permissions: ["tasks.write"] },
    );
  });

  it("throws a forContext error as a DbException at the tool boundary", async () => {
    const tool = supabaseTool({
      server: server(AsyncResult.err(dbError("forbidden", "suspended"))),
      agent: "planner",
      description: "Creates a task",
      inputSchema: title,
      execute: () => "never",
    });

    const call = tool.execute({ title: "x" }, toolCtx(user));

    await expect(call).rejects.toBeInstanceOf(DbException);
    await expect(call).rejects.toMatchObject({ kind: "forbidden" });
  });

  it("refuses a contact session before it reaches the database", async () => {
    const runner = server(AsyncResult.ok({ tasks: [] }));

    const tool = supabaseTool({
      server: runner,
      agent: "planner",
      description: "Creates a task",
      inputSchema: title,
      execute: () => "never",
    });

    await expect(
      tool.execute({ title: "x" }, toolCtx(contact)),
    ).rejects.toMatchObject({ kind: "forbidden" });
    expect(runner.forContext).not.toHaveBeenCalled();
  });

  it("applies the tenant's tool policies over the tool's approval", async () => {
    const policies = vi.fn(() =>
      AsyncResult.ok({
        create_task: "ask" as const,
        delete_task: "deny" as const,
      }),
    );

    const tool = supabaseTool({
      server: server(AsyncResult.ok({ tasks: [] })),
      agent: "planner",
      description: "Creates a task",
      inputSchema: title,
      policies: { policies },
      approval: { request: () => "not-applicable", prompt: () => "Create?" },
      execute: () => "ok",
    });

    const approval = tool.approval;

    if (approval === undefined || typeof approval === "function") {
      throw new TypeError("expected the object form");
    }

    expect(approval.prompt?.({ callId: "c", input: {}, toolName: "t" })).toBe(
      "Create?",
    );
    await expect(approval.request(approvalCtx(user))).resolves.toBe(
      "user-approval",
    );
    expect(policies).toHaveBeenCalledWith(ORG);
  });
});

describe("tenantToolApproval", () => {
  const source = (policies: Record<string, "auto" | "ask" | "deny">) => ({
    policies: () => AsyncResult.ok(policies),
  });

  it("denies a deny tool without asking the inner policy", async () => {
    const inner = vi.fn(() => "approved" as const);
    const policy = tenantToolApproval(source({ create_task: "deny" }), inner);

    await expect(policy(approvalCtx(user))).resolves.toMatchObject({
      type: "denied",
    });
    expect(inner).not.toHaveBeenCalled();
  });

  it("keeps the stricter of the tenant's and the inner status", async () => {
    const ask = tenantToolApproval(source({ create_task: "ask" }), () => true);

    const auto = tenantToolApproval(source({ create_task: "auto" }), () => ({
      type: "denied",
      reason: "over the limit",
    }));

    const approved = tenantToolApproval(
      source({ create_task: "ask" }),
      () => "approved",
    );

    await expect(ask(approvalCtx(user))).resolves.toBe(true);
    await expect(auto(approvalCtx(user))).resolves.toEqual({
      type: "denied",
      reason: "over the limit",
    });
    await expect(approved(approvalCtx(user))).resolves.toBe("user-approval");
  });

  it("leaves a session without a tenant to the inner policy", async () => {
    const policies = vi.fn(() => AsyncResult.ok({}));
    const policy = tenantToolApproval({ policies });

    await expect(policy(approvalCtx(app))).resolves.toBe("not-applicable");
    expect(policies).not.toHaveBeenCalled();
  });
});

describe("strictestApproval", () => {
  const response = (status: "allowed" | "rejected") => () =>
    status === "allowed"
      ? ({ status } as const)
      : ({ status, reason: "no" } as const);

  const responseCtx = {
    request: {
      callId: "call_1",
      interactionId: "i",
      principal: user,
      toolName: "t",
    },
    response: { decision: "approve", principal: user },
    session: { id: "sess_1" },
  } as const;

  it("keeps the strictest request status and stops at a denial", async () => {
    const later = vi.fn(() => true);

    const policy = strictestApproval(
      () => "approved",
      { request: () => ({ type: "denied", reason: "off" }) },
      later,
    );

    await expect(policy.request(approvalCtx(user))).resolves.toEqual({
      type: "denied",
      reason: "off",
    });
    expect(later).not.toHaveBeenCalled();

    const ask = strictestApproval(
      () => "approved",
      () => true,
      () => "not-applicable",
    );

    await expect(ask.request(approvalCtx(user))).resolves.toBe(true);
  });

  it("keeps the earlier answer on a tie", async () => {
    const policy = strictestApproval(
      () => ({ type: "approved", reason: "first" }),
      () => ({ type: "approved", reason: "second" }),
    );

    await expect(policy.request(approvalCtx(user))).resolves.toEqual({
      type: "approved",
      reason: "first",
    });
  });

  it("needs every response policy to allow and the first rejection wins", async () => {
    const allowed = strictestApproval(() => true, {
      request: () => true,
      response: response("allowed"),
    });

    const refused = strictestApproval(
      { request: () => true, response: response("allowed") },
      { request: () => true, response: response("rejected") },
    );

    await expect(allowed.response?.(responseCtx)).resolves.toEqual({
      status: "allowed",
    });
    await expect(refused.response?.(responseCtx)).resolves.toEqual({
      status: "rejected",
      reason: "no",
    });
  });

  it("uses the first prompt and fits a tool's approval", () => {
    const prompt = () => "Run it?";

    const policy = strictestApproval(() => true, {
      request: () => true,
      prompt,
    });

    const tool = supabaseTool({
      agent: "planner",
      server: { forContext: () => AsyncResult.ok({}) },
      description: "d",
      inputSchema: title,
      approval: policy,
      execute: () => null,
    });

    expect(policy.prompt).toBe(prompt);
    expect(tool.approval).toBeDefined();
  });
});
