import { describe, expect, it } from "vitest";

import type { BlocksConfig } from "../../../src/config/blocks.ts";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (
  modules: BlocksConfig = {},
  installed: readonly string[] = [],
): string =>
  renderModules([...installed, "state-machine"], { modules })
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

  it("runs transition as the caller and raises for a record it can't update", () => {
    const sql = sqlOf({
      "state-machine": { options: { machines: { quote } } },
    });
    const transition =
      /function "better_supabase"\."transition"\([\s\S]*?\$\$;/.exec(sql)?.[0];
    expect(transition).toContain("security invoker");
    expect(transition).not.toContain("security definer");
    expect(transition).toContain("STATE_SUBJECT_NOT_FOUND");
    expect(transition).toContain("v_found := found;");
    expect(sql).toMatch(/bs_transition_quote\(\)[\s\S]*?security definer/);
  });

  it("clears and numbers stages within the record's tenant and machine", () => {
    const sql = sqlOf({
      "state-machine": {
        options: { machines: { quote: { ...quote, stages: true } } },
      },
    });
    expect(sql).toContain(`where "tenant_id" = new."tenant_id"
    and "subject_type" = 'quote'`);
    expect(sql).toContain(
      `where s."tenant_id" = new."tenant_id" and s."subject_type" = 'quote' and s."subject_id" = new."id"::text`,
    );
  });

  it("lets a caller read history, stages and lifecycles of records they can see", () => {
    const sql = sqlOf({
      "state-machine": {
        options: { machines: { quote: { ...quote, idType: "uuid" } } },
      },
    });
    expect(sql).toContain("create policy status_history_read");
    expect(sql).toContain("create policy subject_lifecycles_read");
    expect(sql).toContain(
      `when 'quote' then exists (select 1 from "public"."quotes" s where s."id" = ("better_supabase"."status_history"."subject_id")::uuid)`,
    );
  });

  it("falls back to config.subjects for a machine without a table", () => {
    const sql = renderModules(["state-machine"], {
      subjects: {
        deal: { table: "crm.deals", idType: "uuid", tenant: "org_id" },
      },
      modules: {
        "state-machine": {
          options: {
            machines: {
              deal: {
                column: "stage",
                initial: "lead",
                transitions: { lead: ["won"] },
              },
            },
          },
        },
      },
    })
      .filter((file) => file.module === "state-machine")
      .map((file) => file.contents)
      .join("\n");
    expect(sql).toContain("create trigger bs_transition_deal");
    expect(sql).toContain(`on "crm"."deals"`);
    expect(sql).toContain(`new."org_id"`);
    expect(sql).toContain(`s."id" = (transition.subject_id)::uuid`);
  });

  it("keeps a lifecycle row with pause, flags, a pinned version and progress", () => {
    const sql = sqlOf(
      {
        "state-machine": {
          options: {
            machines: {
              quote: {
                ...quote,
                transitions: { draft: ["sent"], sent: ["accepted", "void"] },
                lifecycle: true,
                version: 3,
                order: ["draft", "sent", "accepted"],
                flags: ["urgent"],
              },
            },
          },
        },
      },
      ["outbox"],
    );
    expect(sql).toContain("subject_lifecycles");
    expect(sql).toContain("STATE_PAUSED");
    expect(sql).toContain("STATE_FLAG_UNKNOWN");
    expect(sql).toContain("'{urgent}'::text[]");
    expect(sql).toContain(`'quote', new."id"::text, 3)`);
    expect(sql).toContain(
      "array_position('{draft,sent,accepted}'::text[], v_status)",
    );
    expect(sql).toContain("round((v_step - 1)::numeric / 2, 4)");
    for (const type of ["status.paused", "status.resumed", "status.flagged"]) {
      expect(sql).toContain(type);
    }
    for (const fn of [
      "pause_lifecycle",
      "resume_lifecycle",
      "set_lifecycle_flag",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `function "better_supabase"\\."${fn}"\\([^)]*\\)\\s+returns boolean\\s+language plpgsql\\s+security invoker`,
        ),
      );
    }
  });

  it("refuses lifecycle calls on a machine without lifecycle", () => {
    const sql = sqlOf({
      "state-machine": { options: { machines: { quote } } },
    });
    expect(sql).toContain("STATE_LIFECYCLE_DISABLED");
    expect(sql).not.toContain("v_op jsonb");
  });

  it("reads custom history columns in history()", () => {
    const sql = sqlOf({
      "state-machine": {
        options: {
          machines: {
            quote: {
              ...quote,
              history: {
                table: "public.quote_history",
                createdAt: "at",
                subject: "quote_id",
              },
            },
          },
        },
      },
    });
    expect(sql).toContain(`from "public"."quote_history" h`);
    expect(sql).toContain(
      `h."quote_id"::text = list_status_history.subject_id`,
    );
    expect(sql).toContain(`order by h."at" desc`);
  });

  it("names a machine without the lifecycles table", () => {
    expect(() =>
      sqlOf({
        "state-machine": {
          tables: { lifecycles: null },
          options: { machines: { quote: { ...quote, lifecycle: true } } },
        },
      }),
    ).toThrow("machines.quote.lifecycle needs the lifecycles table");
  });

  it.each([
    [
      "version without lifecycle",
      { ...quote, version: 2 },
      "version and flags need lifecycle: true",
    ],
    [
      "flags without lifecycle",
      { ...quote, flags: ["urgent"] },
      "version and flags need lifecycle: true",
    ],
    [
      "a version that is not a positive integer",
      { ...quote, lifecycle: true, version: 0 },
      "version must be a positive integer",
    ],
    [
      "a lifecycle that is not a boolean",
      { ...quote, lifecycle: "yes" },
      "lifecycle must be true or false",
    ],
    [
      "an order with an unknown status",
      { ...quote, order: ["draft", "won"] },
      "order: won is not a status",
    ],
    [
      "an order with a duplicate",
      { ...quote, order: ["draft", "draft"] },
      "order must be a list of distinct statuses",
    ],
    [
      "an invalid flag name",
      { ...quote, lifecycle: true, flags: ["Urgent!"] },
      "flags: Urgent! must be lowercase",
    ],
    [
      "an invalid id type",
      { ...quote, idType: "uuid;" },
      "idType must be a type name",
    ],
  ])("rejects %s", (_name, entry, message) => {
    expect(() =>
      sqlOf({ "state-machine": { options: { machines: { quote: entry } } } }),
    ).toThrow(message);
  });

  it("rejects a registered subject without a tenant", () => {
    expect(() =>
      renderModules(["state-machine"], {
        subjects: { note: { table: "public.notes", tenant: false } },
        modules: {
          "state-machine": {
            options: {
              machines: {
                note: {
                  column: "status",
                  initial: "draft",
                  transitions: { draft: [] },
                },
              },
            },
          },
        },
      }),
    ).toThrow("config.subjects.note has no tenant column");
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
