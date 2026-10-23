import type { Temporal } from "temporal-polyfill";

import { describe, expect, it } from "vitest";

import type { AnyRecordBinding } from "../../src/blocks/record-bindings.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { RecordRef } from "../../src/schema/types.ts";

import { attachmentsBlock } from "../../src/blocks/attachments/index.ts";
import { commentsBlock } from "../../src/blocks/comments/index.ts";
import { relationsBlock } from "../../src/blocks/relations/index.ts";
import { shareLinksBlock } from "../../src/blocks/share-links/index.ts";
import { slaBlock } from "../../src/blocks/sla/index.ts";
import { tagsBlock } from "../../src/blocks/tags/index.ts";
import { versionsBlock } from "../../src/blocks/versions/index.ts";
import { resolved } from "../fixtures/ports.ts";

const subject: RecordRef = { type: "customer", id: "c1" };
const ID = "00000000-0000-4000-8000-000000000001";

type Call = readonly [method: string, ...args: unknown[]];

/** A client whose every method records its call and resolves to `true`. */
function recorder(): { readonly client: object; readonly calls: Call[] } {
  const calls: Call[] = [];

  const client = new Proxy(
    {},
    {
      get:
        (_target, method) =>
        (...args: unknown[]): AsyncResult<boolean> => {
          calls.push([String(method), ...args]);

          return resolved(true);
        },
    },
  );

  return { client, calls };
}

async function validate(
  binding: AnyRecordBinding,
  write: string,
  input: unknown,
) {
  const entry = binding.writes?.[write];

  if (entry === undefined) {
    throw new Error(`no write ${write}`);
  }

  return entry.input["~standard"].validate(input);
}

async function run(
  binding: AnyRecordBinding,
  write: string,
  input: unknown,
): Promise<readonly Call[]> {
  const settled = await validate(binding, write, input);

  if (settled.issues !== undefined) {
    throw new Error(settled.issues.map((issue) => issue.message).join(", "));
  }

  const { client, calls } = recorder();

  // SAFETY: the recorder answers every method the write calls.
  const runWrite = binding.writes?.[write]?.run as (
    client: object,
    subject: RecordRef,
    input: unknown,
  ) => AsyncResult<unknown>;

  const result = await runWrite(client, subject, settled.value);

  expect(result.ok).toBe(true);

  return calls;
}

describe("binding writes", () => {
  it("adds and removes comments", async () => {
    const binding = commentsBlock.record;

    expect(await run(binding, "add", { body: "Hi" })).toMatchObject([
      ["create", subject, { body: "Hi" }],
    ]);
    expect(await run(binding, "remove", { id: ID })).toEqual([["remove", ID]]);
    expect((await validate(binding, "add", {})).issues).toBeDefined();
  });

  it("removes attachments with the manage permission", async () => {
    const binding = attachmentsBlock.record;

    expect(binding.writes.remove.permission).toBe("manage");
    expect(await run(binding, "remove", { id: ID })).toEqual([["remove", ID]]);
  });

  it("applies and removes tags", async () => {
    const binding = tagsBlock.record;

    expect(await run(binding, "apply", { tagId: ID })).toEqual([
      ["attach", subject, ID],
    ]);
    expect(await run(binding, "remove", { tagId: ID })).toEqual([
      ["detach", subject, ID],
    ]);
  });

  it("creates share links with an ISO expiry and revokes them", async () => {
    const binding = shareLinksBlock.record;

    const [call] = await run(binding, "create", {
      role: "viewer",
      expiresAt: "2026-11-01T00:00:00Z",
      maxUses: 3,
    });

    expect(call?.[0]).toBe("create");
    expect(call?.[1]).toEqual(subject);
    expect(call?.[2]).toMatchObject({ role: "viewer", maxUses: 3 });
    // SAFETY: `create` received the options the binding built.
    const created = call?.[2] as { readonly expiresAt?: Temporal.Instant };

    expect(created.expiresAt?.toString()).toBe("2026-11-01T00:00:00Z");
    expect(await run(binding, "revoke", { id: ID })).toEqual([["revoke", ID]]);
    expect((await validate(binding, "create", { maxUses: 0 })).issues).toEqual(
      expect.any(Array),
    );
  });

  it("links and unlinks related records", async () => {
    const binding = relationsBlock.record;
    const target = { type: "project", id: "p1" };

    expect(
      await run(binding, "link", { target, kind: "owns", data: { a: 1 } }),
    ).toEqual([["link", subject, target, { kind: "owns", data: { a: 1 } }]]);
    expect(await run(binding, "unlink", { target, kind: "owns" })).toEqual([
      ["unlink", subject, target, { kind: "owns" }],
    ]);
  });

  it("records and restores versions", async () => {
    const binding = versionsBlock.record;

    expect(await run(binding, "snapshot", { label: "Before import" })).toEqual([
      ["snapshot", subject, { label: "Before import" }],
    ]);
    expect(await run(binding, "snapshot", {})).toEqual([
      ["snapshot", subject, {}],
    ]);
    expect(binding.writes.restore.permission).toBe("restore");
    expect(await run(binding, "restore", { id: ID })).toEqual([
      ["restore", ID],
    ]);
  });

  it("creates a share link with only the defaults", async () => {
    const binding = shareLinksBlock.record;

    expect(await run(binding, "create", {})).toEqual([["create", subject, {}]]);
  });

  it("links without data", async () => {
    const binding = relationsBlock.record;
    const target = { type: "project", id: "p1" };

    expect(await run(binding, "link", { target, kind: "relates" })).toEqual([
      ["link", subject, target, { kind: "relates" }],
    ]);
  });

  it("starts SLA clocks", async () => {
    const binding = slaBlock.record;

    expect(await run(binding, "start", { priority: "high" })).toEqual([
      ["start", subject, "high"],
    ]);
    expect(await run(binding, "start", {})).toEqual([
      ["start", subject, undefined],
    ]);
  });
});

describe("binding loads", () => {
  const cases: readonly [string, AnyRecordBinding, string][] = [
    ["comments", commentsBlock.record, "list"],
    ["attachments", attachmentsBlock.record, "list"],
    ["tags", tagsBlock.record, "list"],
    ["shareLinks", shareLinksBlock.record, "list"],
    ["relations", relationsBlock.record, "of"],
    ["versions", versionsBlock.record, "list"],
    ["sla", slaBlock.record, "clocks"],
  ];

  it.each(cases)(
    "loads %s through the block client",
    async (name, binding, method) => {
      const { client, calls } = recorder();

      const result = await binding.load(
        client as never,
        subject,
        undefined as never,
      );

      expect(result.ok).toBe(true);
      expect(calls[0]?.[0]).toBe(method);
      expect(calls[0]?.[1]).toEqual(
        name === "tags" ? { on: subject } : subject,
      );
    },
  );

  it("counts comments for many records", async () => {
    const { client, calls } = recorder();
    const count = commentsBlock.record.count;

    expect(count).toBeDefined();
    await count?.(client as never, [subject]);

    expect(calls).toEqual([["counts", [subject]]]);
  });
});
