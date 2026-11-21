import type { SkillScopeResolver } from "eve/experimental/extensions/custom-skills";

import { describe, expect, it, vi } from "vitest";

import type {
  EveSessionAuth,
  EveSkillScopeContext,
} from "../../src/eve/index.ts";

import { supabaseSkillScopes } from "../../src/eve/index.ts";

const user = (
  attributes: Record<string, string | readonly string[]> = {},
): EveSessionAuth => ({
  authenticator: "supabase",
  principalType: "user",
  principalId: "u1",
  attributes: { isAnonymous: "false", ...attributes },
});

const context = (
  current: EveSessionAuth | null,
  extra: Partial<EveSkillScopeContext> = {},
): EveSkillScopeContext => ({
  session: { id: "s1", auth: { current, initiator: current } },
  ...extra,
});

describe("supabaseSkillScopes", () => {
  it("partitions the personal scope by tenant and adds a read-only organization", async () => {
    const scopes = await supabaseSkillScopes()(
      context(user({ tenantId: "t1", roles: ["member"] })),
    );

    expect(scopes).toEqual([
      {
        name: "personal",
        key: "tenant:t1:user:u1",
        label: "you",
        shared: false,
        metadata: { tenantId: "t1" },
      },
      {
        name: "organization",
        key: "tenant:t1",
        label: "everyone in the organization",
        shared: true,
        readOnly: true,
        loadPrefix: "org",
        metadata: { tenantId: "t1" },
      },
    ]);
  });

  it("lets the roles in writableBy change the organization's skills", async () => {
    const resolve = supabaseSkillScopes({
      organization: { writableBy: ["owner", "admin"] },
    });

    const scopes = await resolve(
      context(user({ tenantId: "t1", roles: ["admin"] })),
    );

    expect(
      scopes.find((scope) => scope.name === "organization"),
    ).not.toHaveProperty("readOnly");
  });

  it("keeps an anonymous caller to the shared scopes, read-only", async () => {
    const scopes = await supabaseSkillScopes({
      organization: { writableBy: ["owner"] },
    })(
      context(user({ tenantId: "t1", roles: ["owner"], isAnonymous: "true" }), {
        conversation: { space: { id: "slack:T1:C1" } },
      }),
    );

    expect(
      scopes.map((scope) => [scope.name, scope.key, scope.readOnly]),
    ).toEqual([
      ["channel", "tenant:t1:space:slack:T1:C1", undefined],
      ["organization", "tenant:t1", true],
    ]);
  });

  it("keys scopes as eve does when the caller has no tenant", async () => {
    const scopes = await supabaseSkillScopes()(
      context(user(), { conversation: { space: { id: "slack:T1:C1" } } }),
    );

    expect(scopes.map((scope) => scope.key)).toEqual([
      "user:u1",
      "space:slack:T1:C1",
    ]);
  });

  it("asks for the turn's persona with the turn and the parent session", async () => {
    const persona = vi.fn(() => "support");

    const scopes = await supabaseSkillScopes({ persona, channel: false })(
      context(user({ tenantId: "t1" }), {
        session: {
          id: "child",
          auth: { current: user({ tenantId: "t1" }) },
          parent: { sessionId: "parent", rootSessionId: "root" },
        },
        turn: { id: "turn-2" },
      }),
    );

    expect(persona).toHaveBeenCalledWith({
      tenantId: "t1",
      principalId: "u1",
      sessionId: "child",
      turnId: "turn-2",
      parent: { sessionId: "parent", rootSessionId: "root" },
    });
    expect(scopes.map((scope) => scope.name)).toEqual([
      "personal",
      "persona",
      "organization",
    ]);
    expect(scopes[1]).toMatchObject({
      key: "tenant:t1:persona:support",
      readOnly: true,
      loadPrefix: "persona",
    });
  });

  it("leaves out the persona scope when the callback returns none", async () => {
    const scopes = await supabaseSkillScopes({
      persona: () => undefined,
      organization: false,
    })(context(user({ tenantId: "t1" })));

    expect(scopes.map((scope) => scope.name)).toEqual(["personal"]);
  });

  it("is a resolver eve's custom skills extension accepts", () => {
    const resolver: SkillScopeResolver = supabaseSkillScopes();

    expect(resolver).toBeTypeOf("function");
  });
});
