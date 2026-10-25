import { describe, expect, it } from "vitest";

import type { DbErrorKind } from "../../src/core/errors.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import { attachmentQueueRoute } from "../../src/powersync/attachments.ts";

interface AttachmentInsert {
  readonly id: string;
  readonly organization_id: string;
  readonly name: string;
}

function repository(failWith?: DbErrorKind) {
  const calls: unknown[] = [];

  const reply = () =>
    new AsyncResult(
      Promise.resolve(
        failWith ? err(dbError(failWith, failWith)) : ok({ id: "x" }),
      ),
    );

  return {
    calls,
    repo: {
      create: (row: AttachmentInsert) => {
        calls.push(["create", row]);

        return reply();
      },
      delete: (id: string) => {
        calls.push(["delete", id]);

        return reply();
      },
    },
  };
}

describe("attachmentQueueRoute", () => {
  it("creates the record with the client id and only the writable columns", async () => {
    const { repo, calls } = repository();
    const route = attachmentQueueRoute(repo, { extraColumns: ["caption"] });

    const result = await route({
      op: "PUT",
      table: "attachments",
      id: "a1",
      opData: {
        organization_id: "org-1",
        name: "plan.pdf",
        mime_type: "application/pdf",
        size: 12,
        caption: "Floor",
        object_path: "org-1/attachments/a1",
        status: "clean",
        local_uri: "file:///plan.pdf",
      },
    });

    expect(result.ok).toBe(true);
    expect(calls).toEqual([
      [
        "create",
        {
          id: "a1",
          organization_id: "org-1",
          name: "plan.pdf",
          mime_type: "application/pdf",
          size: 12,
          caption: "Floor",
        },
      ],
    ]);
  });

  it("counts a conflict on PUT and a missing row on DELETE as applied", async () => {
    const conflict = repository("conflict");
    const missing = repository("not_found");

    expect(
      await attachmentQueueRoute(conflict.repo)({
        op: "PUT",
        table: "attachments",
        id: "a1",
        opData: {},
      }),
    ).toEqual(ok(undefined));
    expect(
      await attachmentQueueRoute(missing.repo)({
        op: "DELETE",
        table: "attachments",
        id: "a1",
      }),
    ).toEqual(ok(undefined));
    expect(missing.calls).toEqual([["delete", "a1"]]);
  });

  it("refuses a PATCH", async () => {
    const { repo, calls } = repository();

    const result = await attachmentQueueRoute(repo)({
      op: "PATCH",
      table: "attachments",
      id: "a1",
      opData: { name: "x" },
    });

    expect(result).toMatchObject({ ok: false, error: { kind: "unsupported" } });
    expect(calls).toEqual([]);
  });

  it("builds the object path the database generates", () => {
    const { repo } = repository();

    expect(
      attachmentQueueRoute(repo).path({ id: "a1", organization_id: "o" }),
    ).toBe("o/attachments/a1");

    const custom = attachmentQueueRoute(repo, {
      path: "{organization_id}/{subject_type}/{subject_id}/{id}.{ext}",
    });

    expect(
      custom.path({
        id: "a1",
        organization_id: "o",
        subject_type: null,
        name: "Plan.PDF",
        version: 3,
      }),
    ).toBe("o/-/-/a1.pdf-v3");
    expect(
      custom.path({ id: "a1", organization_id: "o", name: "README" }),
    ).toBe("o/-/-/a1.");
    expect(() =>
      attachmentQueueRoute(repo, {
        path: "{organization_id}/{nope}/{id}",
      }).path({ id: "a1" }),
    ).toThrow(/\{nope\} is not an attachments path placeholder/);
  });
});
