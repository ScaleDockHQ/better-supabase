import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (module: string, modules: AnyBlocksConfig): string =>
  renderBlocks([module], { modules })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("extra columns on more tables", () => {
  it("writes calendar columns on create and returns them in the list", () => {
    const sql = sqlOf("calendar", {
      calendar: {
        options: { calendarExtraColumns: { region: "text not null" } },
      },
    });

    expect(sql).toContain('add column if not exists "region" text not null');
    expect(sql).toContain("owner_id text, fields jsonb default null)");
    expect(sql).toContain(
      `(jsonb_populate_record(null::"better_supabase"."calendars", jsonb_build_object('region', create_calendar.fields -> 'region')))."region"`,
    );
    expect(sql).toContain(
      "'fields', jsonb_build_object('region', k.\"region\")",
    );
  });

  it("writes private detail and contract columns from attrs.fields", () => {
    const sql = sqlOf("employees", {
      employees: {
        options: {
          privateDetailsExtraColumns: { tax_code: "text" },
          contractExtraColumns: { grade: "text not null" },
        },
      },
    });

    expect(sql).toContain(
      `(save_employee_private_details.attrs -> 'fields') ? 'tax_code'`,
    );
    expect(sql).toContain(
      `jsonb_build_object('grade', (add_employee_contract.attrs -> 'fields') -> 'grade')))."grade"`,
    );
  });

  it("writes a required saved-view column inside the insert", () => {
    expect(
      sqlOf("saved-views", {
        "saved-views": { options: { extraColumns: { area: "text not null" } } },
      }),
    ).toContain(
      `jsonb_build_object('area', save_view.fields -> 'area')))."area"`,
    );
  });
});
