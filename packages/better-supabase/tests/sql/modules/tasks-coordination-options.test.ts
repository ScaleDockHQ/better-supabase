import { describe, expect, it } from "vitest";

import { renderBlocks } from "../app-columns.ts";

const render = (
  options: Record<string, unknown>,
  extra: readonly string[] = [],
): string =>
  renderBlocks(["tasks", ...extra], { modules: { tasks: { options } } })
    .filter((file) => file.module === "tasks")
    .map((file) => file.contents)
    .join("\n");

describe("tasks coordination options", () => {
  it("renders the claim lease and stages it is given", () => {
    const sql = render({
      claims: {
        lease: 120,
        maxLease: 600,
        startStage: "in_progress",
        expiredStage: "todo",
      },
      hold: { stage: "blocked" },
    });

    expect(sql).toContain("claim_task");
    expect(sql).toContain(
      "least(600, greatest(1, coalesce(claim_task.lease, 120)))",
    );
    expect(sql).toContain(
      "least(600, greatest(1, coalesce(renew_task_claim.lease, 120)))",
    );
    expect(sql).toContain("'in_progress'");
    expect(sql).toContain("'todo'");
    expect(sql).toContain("'blocked'");
  });

  it("counts prerequisites with the relations block", () => {
    const sql = render({ needs: { kind: "blocks", refuse: "started" } }, [
      "relations",
    ]);

    expect(sql).toContain("recount_task_needs");
    expect(render({ needs: false })).not.toContain("recount_task_needs");
  });

  it("refuses options it can't use", () => {
    const at = "blocks.tasks.options";

    expect(() => render({ claims: [] })).toThrow(
      `${at}.claims must be an object`,
    );
    expect(() => render({ claims: { ttl: 1 } })).toThrow(
      `${at}.claims has no key "ttl"`,
    );
    expect(() => render({ hold: { kind: "x" } })).toThrow(
      `${at}.hold has no key "kind"`,
    );
    expect(() => render({ claims: { lease: 0 } })).toThrow(
      `${at}.claims.lease and maxLease must be whole seconds`,
    );
    expect(() => render({ claims: { lease: 60, maxLease: 30 } })).toThrow(
      /maxLease/u,
    );
    expect(() => render({ claims: { lease: "60" } })).toThrow(/whole seconds/u);
    expect(() => render({ claims: { lease: 1.5 } })).toThrow(/whole seconds/u);
    expect(() => render({ claims: { startStage: "In Progress" } })).toThrow(
      `${at}.claims.startStage must be a stage key`,
    );
    expect(() => render({ hold: { stage: 3 } })).toThrow(
      `${at}.hold.stage must be a stage key`,
    );
    expect(() => render({ needs: { kind: "blocks", when: 1 } })).toThrow(
      `${at}.needs has no key "when"`,
    );
    expect(() => render({ needs: { kind: "parents" } })).toThrow(
      `${at}.needs.kind must be "blocks"`,
    );
    expect(() => render({ needs: { kind: "blocks", refuse: "all" } })).toThrow(
      `${at}.needs.refuse must be "claims", "started" or "none"`,
    );
    expect(() => render({ needs: { kind: "blocks" } })).toThrow(
      `${at}.needs needs the relations block`,
    );
    expect(() =>
      renderBlocks(["tasks", "relations"], {
        modules: {
          tasks: {
            options: { needs: { kind: "blocks" } },
            columns: { items: { waitingOn: null } },
          },
        },
      }),
    ).toThrow(`${at}.needs needs the waiting_on column`);
  });
});
