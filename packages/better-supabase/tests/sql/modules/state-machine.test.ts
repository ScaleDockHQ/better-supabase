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

  const quote = {
    table: "public.quotes",
    column: "status",
    initial: "draft",
    transitions: { draft: ["sent"] },
  };

  it.each([
    ["machines that are not an object", [], "machines must be an object"],
    [
      "a machine with an invalid name",
      { "bad name": quote },
      "has an invalid name",
    ],
    [
      "a machine that is not an object",
      { quote: "draft" },
      "quote must be an object",
    ],
    [
      "a machine without a table",
      { quote: { ...quote, table: 1 } },
      "needs table and column",
    ],
    [
      "an invalid column",
      { quote: { ...quote, column: "status;" } },
      "column must be a column name",
    ],
    [
      "transitions that are not an object",
      { quote: { ...quote, transitions: ["draft"] } },
      "transitions must be an object of status to statuses",
    ],
    [
      "a transition that is not a list",
      { quote: { ...quote, transitions: { draft: "sent" } } },
      "transitions.draft must be a list of statuses",
    ],
    [
      "a history that is not an object",
      { quote: { ...quote, history: true } },
      "history must be an object",
    ],
    [
      "a history without a table",
      { quote: { ...quote, history: {} } },
      "history.table is required",
    ],
    [
      "an invalid history column",
      {
        quote: {
          ...quote,
          history: { table: "public.quote_history", from: 1 },
        },
      },
      "history.from must be a column name",
    ],
  ])("rejects %s", (_name, machines, message) => {
    expect(() => sqlOf({ "state-machine": { options: { machines } } })).toThrow(
      message,
    );
  });

  it("reads custom id, tenant and history columns", () => {
    const sql = sqlOf({
      "state-machine": {
        options: {
          machines: {
            quote: {
              ...quote,
              id: "quote_id",
              tenant: "org_id",
              history: { table: "public.quote_history", from: "was" },
            },
          },
        },
      },
    });
    expect(sql).toContain(`"quote_id"`);
    expect(sql).toContain(`"org_id"`);
    expect(sql).toContain(`"quote_history"`);
    expect(sql).toContain(`"was"`);
  });
});
