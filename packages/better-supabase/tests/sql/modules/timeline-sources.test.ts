import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const registry = {
  quote: { table: "sales.quotes", permissions: { read: "quotes.read" } },
  note: { table: "notes" },
};

const quote = {
  table: "sales.quotes",
  column: "status",
  initial: "draft",
  transitions: { draft: ["sent"] },
};

const render = (
  names: readonly string[],
  machines?: Readonly<Record<string, unknown>>,
): string =>
  renderBlocks(names, {
    subjects: registry,
    modules: {
      "state-machine": { options: { machines: machines ?? { quote } } },
    },
  })
    .filter((file) => file.module === "timeline")
    .map((file) => file.contents)
    .join("\n");

describe("timeline transition and message sources", () => {
  it("reads the subject's status changes from status_history", () => {
    const sql = render(["state-machine", "timeline", "subjects"]);

    expect(sql).toContain(`from "better_supabase"."status_history" h`);
    expect(sql).toContain(`'type', 'status.changed'`);
    expect(sql).toContain(`'from', h."from_status"::text`);
    expect(sql).toContain(
      `list_activity.subject_type = any ('{quote}'::text[])`,
    );
    expect(sql).toContain(
      `(list_activity.sources is null or 'transition' = any (list_activity.sources))`,
    );
    expect(sql).toContain(`'source', 'transition'`);
    expect(sql).toContain("transition for a state-machine status change");
  });

  it("skips machines that keep their own history table", () => {
    const sql = render(["state-machine", "timeline", "subjects"], {
      quote: {
        ...quote,
        history: {
          table: "sales.quote_history",
          from: "from_status",
          to: "to_status",
        },
      },
    });

    expect(sql).not.toContain("'source', 'transition'");
  });

  it("skips the transition source without machines or subjects", () => {
    expect(render(["state-machine", "timeline", "subjects"], {})).not.toContain(
      "status_history",
    );
    expect(render(["state-machine", "timeline"])).not.toContain(
      "status_history",
    );
  });

  it("reads the sent messages of the subject's conversation", () => {
    const sql = render(["messaging", "timeline", "subjects"], {});

    expect(sql).toContain(`from "better_supabase"."messages" m`);
    expect(sql).toContain(
      `join "better_supabase"."conversations" c on c."id" = m."conversation_id"`,
    );
    expect(sql).toContain(`and m."sent_at" is not null`);
    expect(sql).toContain(`and m."deleted_at" is null`);
    expect(sql).toContain(`'type', 'message.sent'`);
    expect(sql).toContain(`'source', 'message'`);
  });

  it("lists both modules as integrations", () => {
    const sql = render(["state-machine", "messaging", "timeline", "subjects"]);

    expect(sql).toContain("'source', 'transition'");
    expect(sql).toContain("'source', 'message'");
  });
});
