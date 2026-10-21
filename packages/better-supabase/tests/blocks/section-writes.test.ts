import type { Temporal } from "temporal-polyfill";

import { describe, expect, it } from "vitest";

import type { AnySection } from "../../src/blocks/sections.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type { SubjectRef } from "../../src/schema/types.ts";

import { attachmentsBlock } from "../../src/blocks/attachments/index.ts";
import { commentsBlock } from "../../src/blocks/comments/index.ts";
import { relationsBlock } from "../../src/blocks/relations/index.ts";
import { shareLinksBlock } from "../../src/blocks/share-links/index.ts";
import { slaBlock } from "../../src/blocks/sla/index.ts";
import { tagsBlock } from "../../src/blocks/tags/index.ts";
import { versionsBlock } from "../../src/blocks/versions/index.ts";
import { resolved } from "../fixtures/ports.ts";

const subject: SubjectRef = { type: "customer", id: "c1" };
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

async function validate(section: AnySection, write: string, input: unknown) {
  const entry = section.writes?.[write];

  if (entry === undefined) {
    throw new Error(`no write ${write}`);
  }

  return entry.input["~standard"].validate(input);
}

async function run(
  section: AnySection,
  write: string,
  input: unknown,
): Promise<readonly Call[]> {
  const settled = await validate(section, write, input);

  if (settled.issues !== undefined) {
    throw new Error(settled.issues.map((issue) => issue.message).join(", "));
  }

  const { client, calls } = recorder();

  // SAFETY: the recorder answers every method the write calls.
  const runWrite = section.writes?.[write]?.run as (
    client: object,
    subject: SubjectRef,
    input: unknown,
  ) => AsyncResult<unknown>;

  const result = await runWrite(client, subject, settled.value);

  expect(result.ok).toBe(true);

  return calls;
}

describe("section writes", () => {
  it("adds and removes comments", async () => {
    const section = commentsBlock.sections.comments;

    expect(await run(section, "add", { body: "Hi" })).toMatchObject([
      ["create", subject, { body: "Hi" }],
    ]);
    expect(await run(section, "remove", { id: ID })).toEqual([["remove", ID]]);
    expect((await validate(section, "add", {})).issues).toBeDefined();
  });

  it("removes attachments with the manage permission", async () => {
    const section = attachmentsBlock.sections.attachments;

    expect(section.writes.remove.permission).toBe("manage");
    expect(await run(section, "remove", { id: ID })).toEqual([["remove", ID]]);
  });

  it("applies and removes tags", async () => {
    const section = tagsBlock.sections.tags;

    expect(await run(section, "apply", { tagId: ID })).toEqual([
      ["tag", subject, ID],
    ]);
    expect(await run(section, "remove", { tagId: ID })).toEqual([
      ["untag", subject, ID],
    ]);
  });

  it("creates share links with an ISO expiry and revokes them", async () => {
    const section = shareLinksBlock.sections.shareLinks;

    const [call] = await run(section, "create", {
      role: "viewer",
      expiresAt: "2026-11-01T00:00:00Z",
      maxUses: 3,
    });

    expect(call?.[0]).toBe("create");
    expect(call?.[1]).toEqual(subject);
    expect(call?.[2]).toMatchObject({ role: "viewer", maxUses: 3 });
    // SAFETY: `create` received the options the section built.
    const created = call?.[2] as { readonly expiresAt?: Temporal.Instant };

    expect(created.expiresAt?.toString()).toBe("2026-11-01T00:00:00Z");
    expect(await run(section, "revoke", { id: ID })).toEqual([["revoke", ID]]);
    expect((await validate(section, "create", { maxUses: 0 })).issues).toEqual(
      expect.any(Array),
    );
  });

  it("links and unlinks related records", async () => {
    const section = relationsBlock.sections.relations;
    const target = { type: "project", id: "p1" };

    expect(
      await run(section, "link", { target, kind: "owns", data: { a: 1 } }),
    ).toEqual([["link", subject, target, { kind: "owns", data: { a: 1 } }]]);
    expect(await run(section, "unlink", { target, kind: "owns" })).toEqual([
      ["unlink", subject, target, { kind: "owns" }],
    ]);
  });

  it("records and restores versions", async () => {
    const section = versionsBlock.sections.versions;

    expect(await run(section, "snapshot", { label: "Before import" })).toEqual([
      ["snapshot", subject, { label: "Before import" }],
    ]);
    expect(await run(section, "snapshot", {})).toEqual([
      ["snapshot", subject, {}],
    ]);
    expect(section.writes.restore.permission).toBe("restore");
    expect(await run(section, "restore", { id: ID })).toEqual([
      ["restore", ID],
    ]);
  });

  it("starts SLA clocks", async () => {
    const section = slaBlock.sections.sla;

    expect(await run(section, "start", { priority: "high" })).toEqual([
      ["start", subject, "high"],
    ]);
    expect(await run(section, "start", {})).toEqual([
      ["start", subject, undefined],
    ]);
  });
});
