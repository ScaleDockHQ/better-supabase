import { describe, expect, it } from "vitest";

import type {
  DoctorContext,
  FindingInput,
  TextFile,
} from "../../../src/cli/doctor/rules.ts";

import { NAMING_RULES } from "../../../src/cli/doctor/naming.ts";

function check(
  blocks: Record<string, unknown>,
  sources: TextFile[] = [],
  code = "BS422",
): readonly FindingInput[] {
  const rule = NAMING_RULES.find((each) => each.code === code);
  // SAFETY: the naming rules read only `config.blocks` and `sources`.
  const context = { config: { blocks }, sources } as unknown as DoctorContext;
  const findings = rule?.check(context);

  if (!Array.isArray(findings)) {
    throw new TypeError(`${code} runs synchronously`);
  }

  return findings;
}

const events = (text: string): readonly FindingInput[] =>
  check({}, [{ path: "src/events.ts", text }], "BS424");

describe("BS422", () => {
  it("reports old keys in the roles and the overrides", () => {
    const findings = check({
      permissions: { roles: { sales: ["parties.read", "contacts.write"] } },
      deals: { permissions: { approve: "rules.publish" } },
    });

    expect(findings.map((each) => each.target)).toEqual([
      "blocks.permissions.roles.sales:parties.read",
      "blocks.deals.permissions.approve:rules.publish",
    ]);
    expect(findings[0]?.message).toContain("now `contacts.read`");
  });

  it("reports quoted old keys in the app sources", () => {
    const findings = check({}, [
      {
        path: "src/nav.ts",
        text: `const items = [\n  { href: "/ai", permission: "ai.read" },\n  { permission: "contacts.read" },\n];`,
      },
    ]);

    expect(findings).toEqual([
      expect.objectContaining({
        target: "src/nav.ts:ai.read",
        location: { file: "src/nav.ts", line: 2 },
      }),
    ]);
    expect(findings[0]?.message).toContain("`agents.read`, `connectors.read`");
  });

  it("skips blocks without string overrides", () => {
    expect(
      check({
        contacts: {},
        deals: undefined,
        tasks: { permissions: { approve: false } },
      }),
    ).toEqual([]);
  });

  it("leaves an old key that is now an event pattern", () => {
    expect(
      check({}, [{ path: "src/feed.ts", text: `onBlockEvent("activity.*")` }]),
    ).toEqual([]);
  });

  it("leaves keys that still exist", () => {
    expect(
      check({
        permissions: { roles: { admin: ["members.invite", "organization.*"] } },
      }),
    ).toEqual([]);
  });
});

describe("BS423", () => {
  it("reports old entity keys, by the block an entry installs", () => {
    const findings = check(
      {
        tasks: { entities: { work_item: "ticket", project: "initiative" } },
        support: { block: "tasks", entities: { work_item: "case" } },
        goals: { entities: { goal: "objective" } },
        contacts: {},
      },
      [],
      "BS423",
    );

    expect(findings.map((each) => each.target)).toEqual([
      "blocks.tasks.entities:work_item",
      "blocks.support.entities:work_item",
    ]);
    expect(findings[0]?.message).toContain("now `task`");
  });

  it("reports quoted old hint codes and leaves the ambiguous one", () => {
    const findings = check(
      {},
      [
        {
          path: "src/tasks.ts",
          text: `if (e.hint === "TASK_LOCKED") a();\nif (e.hint === "WORK_ITEM_LOCKED") b();\nif (e.hint === "ACTIVITY_FORBIDDEN") c();`,
        },
      ],
      "BS423",
    );

    expect(findings).toEqual([
      expect.objectContaining({
        target: "src/tasks.ts:WORK_ITEM_LOCKED",
        location: { file: "src/tasks.ts", line: 2 },
      }),
    ]);
    expect(findings[0]?.message).toContain("now `TASK_LOCKED`");
  });
});

describe("BS424", () => {
  it("reports renamed and split event types in the app sources", () => {
    const findings = events(
      `on("work_item.created", a);\non("agent.saved", b);\non("task.created", c);`,
    );

    expect(findings.map((each) => [each.target, each.location])).toEqual([
      ["src/events.ts:work_item.created", { file: "src/events.ts", line: 1 }],
      ["src/events.ts:agent.saved", { file: "src/events.ts", line: 2 }],
    ]);
    expect(findings[0]?.message).toContain("now `task.created`");
    expect(findings[1]?.message).toContain(
      "now `agent.created` or `agent.updated`",
    );
  });

  it("leaves strings that are also permission keys to BS422", () => {
    expect(
      events(`["support.*", "workflow.*", "leave.*", "waitlist.*", "drive.*"]`),
    ).toEqual([]);
  });
});
