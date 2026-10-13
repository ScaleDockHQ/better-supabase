import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (modules: ModulesConfig = {}): string =>
  renderModules(["state-machine"], { modules })
    .filter((file) => file.module === "state-machine")
    .map((file) => file.contents)
    .join("\n");

describe("state machine", () => {
  it("writes a stages timeline when a machine asks for one", () => {
    const sql = sqlOf({
      "state-machine": {
        options: {
          machines: {
            quote: {
              table: "public.quotes",
              column: "status",
              initial: "draft",
              stages: true,
              transitions: { draft: ["sent"], sent: ["accepted"] },
            },
          },
        },
      },
    });
    expect(sql).toContain("status_stages");
    expect(sql).toContain("cleared_at");
    expect(sql).toContain("STATE_TRANSITION_INVALID");
  });

  it("names the missing initial status", () => {
    expect(() =>
      sqlOf({
        "state-machine": {
          options: {
            machines: {
              quote: {
                table: "public.quotes",
                column: "status",
                transitions: { draft: ["sent"] },
              },
            },
          },
        },
      }),
    ).toThrow("machines.quote.initial must be a status");
  });
});
