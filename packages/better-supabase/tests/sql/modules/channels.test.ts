import { describe, expect, it } from "vitest";

import { moduleBody, renderModules } from "../../../src/sql/render.ts";

describe("channels module", () => {
  it("builds the table and its functions on the messaging core", () => {
    const sql = moduleBody("channels", { modules: {} })!;

    expect(sql).toContain("create table if not exists");
    expect(sql).toContain("open_conversation");
    expect(sql).toContain("channels_for_record");
  });

  it("links a channel only to a record in its own tenant", () => {
    const sql = renderModules(["channels"], {
      modules: {},
      subjects: {
        deal: { table: "deals", idType: "uuid" },
        note: { table: "notes", tenant: false },
      },
    })
      .filter((file) => file.module === "channels")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `when 'deal' then (select s."organization_id"::text from "public"."deals" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)`,
    );
    expect(sql).not.toContain(`when 'note' then (select`);
    expect(sql).toContain(
      `<> create_channel.tenant::text, false) then
    raise exception 'no such record in this organization'`,
    );
  });

  it("renders nothing for a custom implementation", () => {
    expect(
      moduleBody("channels", { modules: { channels: { mode: "custom" } } }),
    ).toBeFalsy();
  });
});
