import { describe, expect, it } from "vitest";

import { defineChecklist } from "../../../src/blocks/onboarding/index.ts";
import { renderModules } from "../../../src/sql/registry.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
): string =>
  renderModules(names, {
    modules: options ? { onboarding: { options } } : {},
  })
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
  it("writes the progress table, its policy and functions", () => {
    const sql = sqlOf(["onboarding"]);
    expect(sql).toMatch(/create table if not exists \S+onboarding_progress/);
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
    const files = renderModules(["onboarding"], {
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
