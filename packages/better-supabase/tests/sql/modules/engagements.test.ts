import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (
  options: Record<string, unknown> = {},
  extra: readonly string[] = [],
): string =>
  renderModules(["engagements", ...extra], {
    subjects: {
      deal: { table: "public.deals" },
      note: { table: "public.notes", tenant: false },
    },
    modules: { engagements: { options } },
  })
    .filter((file) => file.module === "engagements")
    .map((file) => file.contents)
    .join("\n");

describe("engagements module", () => {
  it("checks every subject's tenant and readability", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `when 'deal' then exists (select 1 from "public"."deals" s where s."id"::text = (v_item ->> 'id') and s."organization_id"::text = v_tenant::text)`,
    );
    expect(sql).not.toContain(`when 'note' then`);
    expect(sql).toContain("'{call,email,meeting,note,task}'::text[]");
    expect(sql).not.toContain("engagement.assigned");
  });

  it("notifies an assigned owner with notifications installed", () => {
    expect(sqlOf({}, ["notifications"])).toContain(
      "'type', 'engagement.assigned'",
    );
  });

  it("takes configured types and rejects bad ones", () => {
    expect(sqlOf({ types: ["call", "visit"] })).toContain(
      "'{call,visit}'::text[]",
    );
    expect(() => sqlOf({ types: ["Visit"] })).toThrow(/lowercase names/);
  });
});

describe("engagements module, layouts", () => {
  it("renders nothing in custom mode and refuses every subject without a registry", () => {
    expect(
      renderModules(["engagements"], {
        modules: { engagements: { mode: "custom" } },
      })
        .filter((file) => file.module === "engagements")
        .map((file) => file.contents)
        .join(""),
    ).not.toContain("log_engagement");

    const sql = renderModules(["engagements"], {})
      .filter((file) => file.module === "engagements")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("if not false then");
  });
});

describe("engagements module, bookings", () => {
  const withBookings = (
    options: Record<string, unknown>,
    extra: readonly string[] = ["bookings"],
    bookings: Record<string, unknown> = {},
  ): string =>
    renderModules(["engagements", ...extra], {
      modules: { engagements: { options }, bookings },
    })
      .filter((file) => file.module === "engagements")
      .map((file) => file.contents)
      .join("\n");

  it("logs no bookings unless the option is on", () => {
    expect(withBookings({})).not.toContain("bs_booking_engagement");
  });

  it("needs the bookings block and the meeting type", () => {
    expect(() => withBookings({ bookings: true }, [])).toThrow(
      /needs the bookings block/,
    );
    expect(() =>
      withBookings({ bookings: true, types: ["call", "note"] }),
    ).toThrow(/needs "meeting"/);
  });

  it("keeps a meeting per confirmed booking, without parties", () => {
    const sql = withBookings({ bookings: true }, ["bookings", "outbox"]);

    expect(sql).toContain(
      'after insert or update of "status", "during" on "better_supabase"."bookings"',
    );
    expect(sql).toContain("v_ref text := 'booking:' || new.\"id\"::text;");
    expect(sql).toContain('v_owner uuid := new."created_by";');
    expect(sql).toContain(
      "'meeting', coalesce(v_title, 'Booking'), new.\"notes\"",
    );
    expect(sql).toContain("engagement.completed");
    expect(sql).not.toContain('"company_people"');
  });

  it("links the booker's person and company with parties installed", () => {
    const sql = withBookings({ bookings: true }, ["bookings", "parties"]);

    expect(sql).toContain('from "better_supabase"."people" p');
    expect(sql).toContain(
      "values (v_tenant, v_id, 'person', v_person::text, 1)",
    );
    expect(sql).toContain(
      "select v_tenant, v_id, 'company', c.\"id\"::text, 2",
    );
  });

  it("falls back when bookings has no notes or author column", () => {
    const sql = withBookings({ bookings: true }, ["bookings"], {
      mode: "adopt",
      columns: { bookings: { notes: null, createdBy: null } },
    });

    expect(sql).toContain("v_owner uuid := null::uuid;");
    expect(sql).toContain("coalesce(v_title, 'Booking'), null::text");
  });
});
