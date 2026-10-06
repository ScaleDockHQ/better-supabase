import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/blocks/onboarding/index.ts";

import { defineChecklist } from "../../../src/blocks/onboarding/index.ts";

const steps = [
  { id: "invite", title: "Invite a teammate", href: "/team" },
  { id: "billing" },
  { id: "project" },
] as const;

describe("defineChecklist", () => {
  it("rejects bad or repeated ids", () => {
    expect(() =>
      defineChecklist({ id: "Bad", scope: "user", steps: [] }),
    ).toThrow('"Bad" is not a checklist id');
    expect(() =>
      defineChecklist({
        id: "team",
        scope: "user",
        steps: [{ id: "a" }, { id: "a" }],
      }),
    ).toThrow('step "a" is not a unique step id');
  });

  it("reads progress in step order and completes steps for a tenant", async () => {
    const call = vi.fn(
      async (_schema: string, fn: string, _args: Record<string, unknown>) =>
        fn === "onboarding_progress"
          ? [
              {
                step: "project",
                completedAt: "2026-01-02T00:00:00Z",
                completedBy: null,
              },
              {
                step: "invite",
                completedAt: "2026-01-01T00:00:00Z",
                completedBy: "u1",
              },
              { step: "retired", completedAt: "2026-01-01T00:00:00Z" },
            ]
          : fn === "complete_onboarding_step",
    );
    const transport: BlockTransport = { call };
    const team = defineChecklist({ id: "team", scope: "organization", steps });
    const client = team.connect({ transport, schema: "app" });

    const progress = await client.progress("org").orThrow();
    expect(call).toHaveBeenCalledWith("app", "onboarding_progress", {
      checklist: "team",
      tenant: "org",
    });
    expect(progress.steps.map((s) => [s.id, s.completed])).toEqual([
      ["invite", true],
      ["billing", false],
      ["project", true],
    ]);
    expect(progress.steps[0]).toMatchObject({
      title: "Invite a teammate",
      href: "/team",
      completedBy: "u1",
    });
    expect(progress.steps[2]?.completedBy).toBeUndefined();
    expect(progress).toMatchObject({ completed: 2, total: 3, done: false });
    expect(progress.next?.id).toBe("billing");

    expect(await client.complete("billing", "org").orThrow()).toBe(true);
    expect(await client.reset("billing", "org").orThrow()).toBe(false);
    expect(call.mock.calls[2]?.[2]).toEqual({
      checklist: "team",
      step: "billing",
      tenant: "org",
    });
  });

  it("calls user checklists without a tenant and reports done", async () => {
    const call = vi.fn(async () => [{ step: "a" }]);
    const profile = defineChecklist({
      id: "profile",
      scope: "user",
      steps: [{ id: "a" }],
    });
    const progress = await profile
      .connect({ transport: { call } })
      .progress()
      .orThrow();
    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "onboarding_progress",
      {
        checklist: "profile",
        tenant: null,
      },
    );
    expect(progress).toMatchObject({ done: true, next: undefined });
  });
});
