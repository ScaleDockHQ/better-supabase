import { describe, expect, it } from "vitest";

import { mappingTagsOf, withMappingTags } from "../../src/sql/mapping-tags.ts";

const sql = `comment on table public.members is 'Seats. @bsb block-table=memberships.memberships';
comment on column public.members.org_id is '@bsb column=tenant';
comment on table other.skipped is '@bsb block-table=memberships.roles';`;

describe("mapping tags", () => {
  const tags = mappingTagsOf([sql], ["public"]);

  it("reads a table and its tagged columns", () => {
    expect(tags).toEqual({
      tables: { memberships: { memberships: "public.members" } },
      columns: { memberships: { memberships: { tenant: "org_id" } } },
    });
  });

  it("lets a config entry win and leaves other blocks alone", () => {
    const entry = { tables: { memberships: "x.y" }, columns: {} };
    const out = withMappingTags({ memberships: entry, tags: {} }, {}, tags);

    expect(out.modules).toMatchObject({
      memberships: { tables: { memberships: "x.y" } },
      tags: {},
    });
  });
});
