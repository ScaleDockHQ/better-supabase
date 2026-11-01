import { describe, expect, it } from "vitest";

import { defineChecklist } from "../../../src/blocks/onboarding/index.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
): string =>
  renderBlocks(names, { modules: options ? { onboarding: { options } } : {} })
    .filter((file) => file.contents.includes("onboarding_progress"))
    .map((file) => file.contents)
    .join("\n");

const team = defineChecklist({
  id: "team",
  scope: "organization",
  steps: [
    { id: "invite", events: ["organization.member_added"] },
    { id: "billing" },
  ],
});

const profile = defineChecklist({
  id: "profile",
  scope: "user",
  steps: [{ id: "avatar", events: ["profile.updated"] }],
});

describe("onboarding module", () => {
  it("runs its functions on enrollments", () => {
    const sql = sqlOf(["onboarding"]);
    expect(sql).not.toMatch(
      /create table if not exists \S+onboarding_progress/,
    );
    expect(sql).toContain("enrollment_ensure");
    expect(sql).toContain("enrollment_mark");
    expect(sql).toContain(
      "'onboarding:' || complete_onboarding_step.checklist",
    );
    expect(sql).toContain("'onboarding.read'");
    expect(sql).toContain("'onboarding.complete'");
    expect(sql).toContain("complete_onboarding_step");
    expect(sql).toContain(
      "select null::text as checklist, null::text as step, null::text as scope where false",
    );
    expect(sql).not.toContain("onboarding_from_event");
  });

  it("lists the configured steps and completes them from outbox events", () => {
    const sql = sqlOf(["outbox", "onboarding"], {
      checklists: [team, profile],
    });

    expect(sql).toContain(
      "values ('team', 'invite', 'organization'), ('team', 'billing', 'organization'), ('profile', 'avatar', 'user')",
    );
    expect(sql).toContain("onboarding_from_event");
    expect(sql).toContain(
      "in ('organization.member_added', 'profile.updated')",
    );
    expect(sql).toContain('new."actor_id"');
    expect(sqlOf(["outbox", "onboarding"], { checklists: { team } })).toContain(
      "('team', 'invite', 'organization')",
    );
  });

  it("completes a step from its completeOn event next to its events", () => {
    const sql = sqlOf(["outbox", "onboarding"], {
      checklists: [
        defineChecklist({
          id: "sales",
          scope: "organization",
          steps: [{ id: "send", completeOn: "invoice.sent" }],
        }),
      ],
    });

    expect(sql).toContain("in ('invoice.sent')");
  });

  it("snapshots each checklist's steps in order", () => {
    const sql = sqlOf(["outbox", "onboarding"], {
      checklists: [team, profile],
    });

    expect(sql).toContain(
      "values ('team', 'organization', array['invite', 'billing']::text[]), ('profile', 'user', array['avatar']::text[])",
    );
  });

  it("needs enrollments in managed mode", () => {
    expect(() =>
      renderBlocks(["onboarding"], {
        modules: { enrollments: { mode: "custom" } },
      }),
    ).toThrow("install enrollments in managed mode");
  });

  it("moves version 1 progress onto enrollments", () => {
    const [plan] = upgradePlan([{ module: "onboarding", version: 1 }], {
      modules: { onboarding: { options: { checklists: [team] } } },
    });

    const sql = plan?.steps[0]?.sql ?? "";

    expect(plan?.to).toBe(2);
    expect(sql).toMatch(/create table if not exists \S+enrollments/);
    expect(sql).toMatch(/to_regclass\('\w+\.onboarding_progress'\)/);
    expect(sql).toContain("array['invite', 'billing']::text[]");
    expect(sql).toMatch(/drop table \S+\.onboarding_progress;/);
  });

  it("has no upgrade in custom mode", () => {
    expect(
      upgradePlan([{ module: "onboarding", version: 1 }], {
        modules: { onboarding: { mode: "custom" } },
      }),
    ).toStrictEqual([]);
  });

  it("needs the outbox for event steps", () => {
    expect(() => sqlOf(["onboarding"], { checklists: [team] })).toThrow(
      "steps with events need the outbox module",
    );
  });

  it.each([
    [42, "pass an array of defineChecklist() results"],
    [[1], "not a checklist"],
    [[{ id: "Bad", scope: "user", steps: [] }], "use lowercase letters"],
    [
      [
        { id: "a", scope: "user", steps: [] },
        { id: "a", scope: "user", steps: [] },
      ],
      "is listed twice",
    ],
    [[{ id: "a", scope: "team", steps: [] }], 'use "user" or "organization"'],
    [[{ id: "a", scope: "user", steps: {} }], "steps: pass an array"],
    [[{ id: "a", scope: "user", steps: [1] }], "not a step"],
    [
      [{ id: "a", scope: "user", steps: [{ id: "x" }, { id: "x" }] }],
      "is listed twice",
    ],
    [
      [{ id: "a", scope: "user", steps: [{ id: "x", events: "e" }] }],
      "pass an array of outbox event types",
    ],
    [
      [{ id: "a", scope: "user", steps: [{ id: "x", events: ["Bad Event"] }] }],
      "not an event type",
    ],
  ])("rejects checklists %j", (checklists, message) => {
    expect(() => sqlOf(["outbox", "onboarding"], { checklists })).toThrow(
      message,
    );
  });

  it("writes nothing in custom mode", () => {
    const files = renderBlocks(["onboarding"], {
      modules: { onboarding: { mode: "custom" } },
    });

    expect(
      files.some((file) =>
        file.contents.includes(
          "create table if not exists better_supabase.onboarding_progress",
        ),
      ),
    ).toBe(false);
  });
});
