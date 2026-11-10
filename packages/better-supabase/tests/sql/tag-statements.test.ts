import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { keysetPredicate } from "../../src/sql/list-template.ts";
import {
  setFeatureStatement,
  setTableFeature,
} from "../../src/sql/table-features.ts";
import { renderTagBlock, setTagBlock } from "../../src/sql/tag-statements.ts";

const TABLE = "create table public.scale_items (id uuid primary key);\n";

const LIST = {
  name: "list",
  args: {
    search: "title",
    sort: "created_at:desc",
    filter: "status",
    tenant: "tenant_id",
  },
} as const;

const ACCESS = {
  name: "access",
  args: {
    read: "items.read",
    create: "items.write",
    update: "items.write",
    delete: "items.write",
    "actor-guard": true,
  },
} as const;

describe("rendered tags", () => {
  it("renders the SQL the pgTAP file applies", () => {
    const pgtap = readFileSync(
      new URL(
        "../../../../supabase/tests/database/bsb_tags_rendered.test.sql",
        import.meta.url,
      ),
      "utf-8",
    );

    for (const block of [
      renderTagBlock("list", "public", "scale_items", LIST),
      renderTagBlock("access", "public", "scale_items", ACCESS),
      renderTagBlock("idempotency", "public", "scale_items", {
        name: "idempotency",
        args: {},
      }),
    ]) {
      expect(pgtap).toContain(block);
    }
  });

  it("falls back to tenant_ids_with when the provider has no canIn", () => {
    const sql = renderTagBlock("access", "public", "scale_items", ACCESS);

    expect(sql).toContain(
      `"tenant_id" in (select better_supabase.tenant_ids_with('items.read'))`,
    );
    expect(sql).toContain("better_supabase.actor_may_write()");
  });

  it("uses the provider's canIn and actorMayWrite when it has them", () => {
    const sql = renderTagBlock("access", "public", "scale_items", ACCESS, {
      canIn: "authz.can_in({permission}, {tenant})",
      actorMayWrite: "authz.writable()",
    });

    expect(sql).toContain(`authz.can_in('items.read', "tenant_id")`);
    expect(sql).toContain("(authz.writable())");
    expect(sql).not.toContain("tenant_ids_with");
    expect(sql).not.toContain("better_supabase.actor_may_write");
  });

  it("refuses an access tag without an operation", () => {
    expect(() =>
      renderTagBlock("access", "public", "scale_items", {
        name: "access",
        args: {},
      }),
    ).toThrow("at least one of read=");
  });

  it("refuses an identifier that is not lower case", () => {
    expect(() =>
      renderTagBlock("list", "public", "scale_items", {
        name: "list",
        args: { search: "Title; drop table x" },
      }),
    ).toThrow("not a lower case identifier");
  });

  it("pages by keyset with a leading bound for mixed directions", () => {
    const sql = keysetPredicate(
      [
        { expr: "x.a", dir: "desc", type: "integer" },
        { expr: "x.id", dir: "asc", type: "uuid" },
      ],
      "v_after",
    );

    expect(sql).toContain("x.a <= (v_after ->> 0)::integer");
    expect(sql).toContain("x.id > (v_after ->> 1)::uuid");
  });

  it("compares keys of one direction as a row", () => {
    expect(
      keysetPredicate(
        [
          { expr: "x.a", dir: "desc", type: "integer" },
          { expr: "x.id", dir: "desc", type: "uuid" },
        ],
        "v_after",
      ),
    ).toBe(
      "(v_after is null or (x.a, x.id) < ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))",
    );
  });
});

describe("setFeatureStatement for a rendered tag", () => {
  const tagged = (): string =>
    `${TABLE}\ncomment on table public.scale_items is '@bsb access read=items.read';\n`;

  it("writes the block once and replaces it when the tag changes", () => {
    const first = setFeatureStatement(
      tagged(),
      "public",
      "scale_items",
      "access",
      true,
    );

    expect(first.match(/bsb-tag access begin/gu)).toHaveLength(1);
    expect(first).toContain("bsb_access_scale_items_read");

    const changed = setFeatureStatement(
      first.replace("read=items.read", "read=items.view"),
      "public",
      "scale_items",
      "access",
      true,
    );

    expect(changed.match(/bsb-tag access begin/gu)).toHaveLength(1);
    expect(changed).toContain("items.view");
    expect(changed).not.toContain("items.read");
  });

  it("removes the block when the feature is disabled", () => {
    const on = setFeatureStatement(
      tagged(),
      "public",
      "scale_items",
      "access",
      true,
    );

    expect(
      setFeatureStatement(on, "public", "scale_items", "access", false),
    ).not.toContain("bsb-tag access");
  });

  it("keeps the arguments of a tag that is enabled again", () => {
    expect(
      setTableFeature(tagged(), "public", "scale_items", "access", true),
    ).toContain("@bsb access read=items.read");
  });

  it("appends and removes a block by its markers", () => {
    const sql = setTagBlock(
      TABLE,
      "idempotency",
      "-- @bsb-tag idempotency begin\nx\n-- @bsb-tag idempotency end",
    );

    expect(sql).toContain("\nx\n");
    expect(setTagBlock(sql, "idempotency", undefined)).not.toContain(
      "idempotency",
    );
  });
});

const RPC = {
  name: "rpc",
  args: { name: "get_scale_tasks", columns: "id,title" },
} as const;

const COPY = {
  name: "copy",
  args: {
    columns: "tenant_id,project_id,title,hours",
    suffix: "title: (copy)",
  },
} as const;

const ROLLUP = {
  name: "rollup",
  args: {
    stored: true,
    to: "public.scale_projects",
    key: "project_id",
    column: "task_count",
  },
} as const;

describe("rpc, copy and rollup tags (ADR 0661)", () => {
  it("renders the SQL the second pgTAP file applies", () => {
    const pgtap = readFileSync(
      new URL(
        "../../../../supabase/tests/database/bsb_tags_rendered_more.test.sql",
        import.meta.url,
      ),
      "utf-8",
    );

    for (const block of [
      renderTagBlock("rpc", "public", "scale_tasks", RPC),
      renderTagBlock("copy", "public", "scale_tasks", COPY),
      renderTagBlock("rollup", "public", "scale_tasks", ROLLUP),
    ]) {
      expect(pgtap).toContain(block);
    }
  });

  it("caps the ids an rpc reads and keeps their order", () => {
    const sql = renderTagBlock("rpc", "public", "scale_tasks", {
      name: "rpc",
      args: { name: "get_scale_tasks", max: "50" },
    });

    expect(sql).toContain("get_scale_tasks.ids[1:50]");
    expect(sql).toContain("order by i.n");
    expect(() =>
      renderTagBlock("rpc", "public", "scale_tasks", {
        name: "rpc",
        args: { max: "9000" },
      }),
    ).toThrow(/1 to 5000/u);
  });

  it("refuses a copy without columns or with the id", () => {
    expect(() =>
      renderTagBlock("copy", "public", "scale_tasks", {
        name: "copy",
        args: {},
      }),
    ).toThrow(/columns=/u);
    expect(() =>
      renderTagBlock("copy", "public", "scale_tasks", {
        name: "copy",
        args: { columns: "id,title" },
      }),
    ).toThrow(/must not include id/u);
  });

  it("sums a column in a rollup and refuses what it cannot render", () => {
    const sql = renderTagBlock("rollup", "public", "scale_tasks", {
      name: "rollup",
      args: { ...ROLLUP.args, column: "hours_total", sum: "hours" },
    });

    expect(sql).toContain('"hours_total" + coalesce(new."hours", 0)');
    expect(sql).toContain('old."hours" is distinct from new."hours"');

    expect(() =>
      renderTagBlock("rollup", "public", "scale_tasks", {
        name: "rollup",
        args: { to: "public.scale_projects", key: "project_id", column: "n" },
      }),
    ).toThrow(/stored/u);
    expect(() =>
      renderTagBlock("rollup", "public", "scale_tasks", {
        name: "rollup",
        args: { stored: true, key: "project_id", column: "n" },
      }),
    ).toThrow(/to=/u);
  });
});
