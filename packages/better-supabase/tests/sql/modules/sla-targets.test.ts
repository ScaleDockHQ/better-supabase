import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const body = (
  module: string,
  layout: Parameters<typeof renderModules>[1] = {},
  extra: readonly string[] = [],
): string =>
  renderModules([module, ...extra], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const SUBJECTS = {
  ticket: { table: "public.tickets", idType: "uuid" },
  note: { table: "public.notes", tenant: false as const },
};

describe("sla module", () => {
  it("counts business hours in the configured zone", () => {
    const sql = body("sla", {
      modules: {
        sla: {
          options: {
            businessHours: {
              timeZone: "Europe/Amsterdam",
              start: "08:30",
              end: "17:30",
              days: [1, 2, 3, 4],
            },
          },
        },
      },
    });

    expect(sql).toContain("at time zone 'Europe/Amsterdam'");
    expect(sql).toContain("'08:30'::time");
    expect(sql).toContain("'{1,2,3,4}'::integer[]");
  });

  it("binds a record's status and priority to its clocks", () => {
    const sql = body("sla", {
      subjects: SUBJECTS,
      modules: {
        sla: {
          options: {
            subjects: {
              ticket: {
                status: "status",
                priority: "priority",
                pause: ["waiting"],
                resolve: ["solved"],
              },
            },
          },
        },
      },
    });

    expect(sql).toContain(
      'create trigger bsb_sla_ticket after insert or update of "status", "priority" on "public"."tickets"',
    );
    expect(sql).toContain("'{\"waiting\"}'::text[]");

    const plain = body("sla", {
      subjects: SUBJECTS,
      modules: {
        sla: { options: { subjects: { ticket: { status: "state" } } } },
      },
    });

    expect(plain).toContain('after insert or update of "state" on');
    expect(plain).not.toContain('new."priority"');
  });

  it("notifies watchers on breaches with notifications installed", () => {
    expect(body("sla", {}, ["notifications"])).toContain(
      "'type', 'sla.breached'",
    );
    expect(body("sla")).not.toContain("'type', 'sla.breached'");
  });

  it.each([
    [{ businessHours: { timeZone: "Not a zone!" } }, /IANA/],
    [{ businessHours: { start: "18:00", end: "09:00" } }, /end after start/],
    [{ businessHours: { days: [0] } }, /ISO weekdays/],
    [{ businessHours: "always" }, /must be an object/],
    [{ subjects: { ghost: { status: "s" } } }, /register "ghost"/],
    [{ subjects: { note: { status: "s" } } }, /register "note"/],
    [
      { subjects: { ticket: { status: "Bad Column" } } },
      /status must be a column/,
    ],
    [
      { subjects: { ticket: { status: "s", priority: 3 } } },
      /priority must be a column/,
    ],
    [
      { subjects: { ticket: { status: "s", pause: "waiting" } } },
      /pause must be a list/,
    ],
    [{ subjects: { ticket: "x" } }, /must be an object/],
    [{ subjects: [] }, /subjects must be an object/],
  ])("rejects %j", (options, message) => {
    expect(() =>
      body("sla", { subjects: SUBJECTS, modules: { sla: { options } } }),
    ).toThrow(message);
  });

  it("renders nothing in custom mode", () => {
    expect(body("sla", { modules: { sla: { mode: "custom" } } })).not.toContain(
      "sla_due_at",
    );
  });
});

describe("targets module", () => {
  it("computes the metrics of installed blocks only", () => {
    expect(body("targets")).toContain("Built-in metrics: none installed");
    const all = body("targets", {}, ["deals", "work-items", "invoices"]);

    for (const metric of [
      "deals.won_amount",
      "deals.won_count",
      "work_items.completed",
      "invoices.paid_amount",
    ]) {
      expect(all).toContain(`when '${metric}' then`);
    }
  });

  it("renders nothing in custom mode", () => {
    expect(
      body("targets", { modules: { targets: { mode: "custom" } } }),
    ).not.toContain("save_target");
  });
});
