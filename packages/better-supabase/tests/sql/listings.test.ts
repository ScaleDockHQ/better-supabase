import { describe, expect, it } from "vitest";

import type { ResolvedConfig } from "../../src/config/index.ts";

import { resolveConfig } from "../../src/config/index.ts";
import { listAccessPolicies, listActions } from "../../src/sql/listings.ts";
import { renderTagBlock } from "../../src/sql/tag-statements.ts";

function configWith(
  authorization: unknown,
  extra: Record<string, unknown> = {},
): ResolvedConfig {
  // SAFETY: only the provider fields the listings read are set.
  const provider = authorization as never;

  return resolveConfig(
    { blocks: ["audit"], authorization: provider, ...extra } as never,
    "/project",
  );
}

describe("listActions", () => {
  it("names the key and its source for every kind", () => {
    const config = configWith(
      {
        apiVersion: 1,
        name: "stub",
        functions: {},
        actionKeys: {
          blocks: { audit: { read: "audit.view" } },
          recordTypes: { note: { read: "note.read", write: "note.write" } },
          buckets: { logos: { read: "logo.read", delete: "logo.remove" } },
          topics: { "room:{id}": { receive: "room.listen" } },
        },
      },
      {
        recordTypes: {
          note: { table: "public.notes", permissions: { write: "note.edit" } },
        },
        buckets: {
          logos: {
            path: "{organizationId}/{...rest}",
            policy: { access: { read: "logo.view", write: "logo.upload" } },
          },
        },
        topics: { "room:{id}": "room:{id}" },
      },
    );

    const rows = listActions(config);

    const find = (kind: string, name: string, action: string) =>
      rows.find(
        (row) =>
          row.kind === kind && row.name === name && row.action === action,
      );

    expect(find("block", "audit", "read")).toMatchObject({
      key: "audit.view",
      source: "provider",
    });
    expect(
      rows.filter((row) => row.kind === "block" && row.name === "audit"),
    ).not.toHaveLength(0);
    expect(find("recordType", "note", "read")).toMatchObject({
      key: "note.read",
      source: "provider",
    });
    expect(find("recordType", "note", "write")).toMatchObject({
      key: "note.edit",
      source: "config",
    });
    expect(find("bucket", "logos", "read")).toMatchObject({
      key: "logo.view",
      source: "config",
    });
    expect(find("bucket", "logos", "delete")).toMatchObject({
      key: "logo.remove",
      source: "provider",
    });
    expect(find("topic", "room:{id}", "receive")).toMatchObject({
      key: "room.listen",
      source: "provider",
    });
    expect(find("topic", "room:{id}", "send")).toMatchObject({ key: null });
  });
});

describe("listAccessPolicies", () => {
  const comment = (text: string) => ({
    schema: "public",
    name: "scale_items",
    comment: text,
  });

  it("lists one row per policy the tag renders, matching the SQL", () => {
    const config = configWith(undefined);

    const rows = listAccessPolicies(config, [
      comment("@bsb access read=items.read create=items.write actor-guard"),
    ]);

    expect(rows.map((row) => [row.operation, row.key, row.actorGuard])).toEqual(
      [
        ["read", "items.read", false],
        ["create", "items.write", true],
      ],
    );

    const sql = renderTagBlock("access", "public", "scale_items", {
      name: "access",
      args: { read: "items.read", create: "items.write", "actor-guard": true },
    });

    expect(sql.match(/create policy/gu)).toHaveLength(rows.length);

    for (const row of rows) {
      expect(sql).toContain(`"${row.name}"`);
    }
  });

  it("lists nothing for a table without an access tag", () => {
    expect(
      listAccessPolicies(configWith(undefined), [comment("@bsb audit")]),
    ).toEqual([]);
  });
});
