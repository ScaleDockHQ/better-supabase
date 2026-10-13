import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";
import * as Y from "yjs";

import type { Result } from "../../src/core/result.ts";

import {
  createDocuments,
  sqlTransport,
} from "../../src/blocks/documents/index.ts";
import { compactDocument } from "../../src/yjs/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "outbox", "versions", "documents"];

describe.skipIf(!live)("documents", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  const hint = (result: Result<unknown>) =>
    result.ok ? "ok" : result.error.hint;

  it("stores updates, compacts them and saves versions under the tenant's rules", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const member = await s.user("member");
      const viewer = await s.user("viewer");
      const outsider = await s.user("outsider");
      await s.install(MODULES, {
        modules: { documents: { options: { maxUpdateBytes: 4096 } } },
      });
      const tenant = await s.organization(owner, { member, viewer });
      const documents = createDocuments({ transport: sqlTransport(s.sql) });
      const ref = {
        organizationId: tenant,
        subjectType: "page",
        subjectId: "p1",
      };

      await s.asRole(viewer);
      expect(await documents.open(ref).then(hint)).toBe("DOCUMENT_FORBIDDEN");

      await s.asRole(member);
      const opened = await documents.open(ref).orThrow();
      expect(opened).toMatchObject({
        canWrite: true,
        name: "body",
        snapshotSeq: 0,
        updates: [],
        topic: `documents:${opened.id}`,
      });
      const doc = new Y.Doc();
      const pushed: Promise<number>[] = [];
      doc.on("update", (update: Uint8Array) => {
        pushed.push(documents.push(opened.id, update).orThrow());
      });
      doc.getText("t").insert(0, "hello");
      doc.getText("t").insert(5, " world");
      expect(await Promise.all(pushed)).toHaveLength(2);
      expect(
        await documents.push(opened.id, new Uint8Array(5000)).then(hint),
      ).toBe("DOCUMENT_UPDATE_TOO_LARGE");
      expect(await documents.push(opened.id, new Uint8Array()).then(hint)).toBe(
        "DOCUMENT_UPDATE_INVALID",
      );
      expect(
        await s.value<boolean>(
          "better_supabase.document_topic_access($1, true)",
          [opened.topic],
        ),
      ).toBe(true);
      expect(
        await s.value<boolean>(
          "better_supabase.document_topic_access($1, false)",
          ["documents:not-a-uuid"],
        ),
      ).toBe(false);
      expect(
        await documents.compact(opened.id, new Uint8Array([0]), 1).then(hint),
      ).toBe("DOCUMENT_FORBIDDEN");

      await s.asRole(viewer);
      expect(await documents.pull(opened.id, 0).then(hint)).toBe(
        "DOCUMENT_NOT_FOUND",
      );
      expect(
        await s.value<boolean>(
          "better_supabase.document_topic_access($1, false)",
          [opened.topic],
        ),
      ).toBe(false);
      await s.asRole(outsider);
      expect(await documents.open(ref).then(hint)).toBe("DOCUMENT_NOT_FOUND");

      await s.service();
      expect(await documents.toCompact({ minUpdates: 2 }).orThrow()).toEqual([
        opened.id,
      ]);
      expect(
        await compactDocument({
          documents,
          documentId: opened.id,
          yjs: Y,
        }).orThrow(),
      ).toBe(true);
      expect(await documents.toCompact({ minUpdates: 1 }).orThrow()).toEqual(
        [],
      );

      await s.asRole(owner);
      const reopened = await documents.open(ref).orThrow();
      expect(reopened.id).toBe(opened.id);
      expect(reopened.updates).toEqual([]);
      const copy = new Y.Doc();
      Y.applyUpdate(copy, reopened.snapshot!);
      expect(copy.getText("t").toString()).toBe("hello world");
      const stale = await documents.pull(opened.id, 0).orThrow();
      expect(stale.snapshotSeq).toBe(reopened.snapshotSeq);

      const saved = await documents
        .saveVersion(opened.id, Y.encodeStateAsUpdate(copy), "first draft")
        .orThrow();
      expect(saved.number).toBe(1);
      const versions = await documents.versions(opened.id).orThrow();
      expect(versions).toMatchObject([{ number: 1, label: "first draft" }]);
      const restored = new Y.Doc();
      Y.applyUpdate(
        restored,
        await documents.version(opened.id, saved.id).orThrow(),
      );
      expect(restored.getText("t").toString()).toBe("hello world");

      await s.service();
      expect(
        await s.rows<{ type: string }>(
          "select type from better_supabase.outbox_events where subject = $1",
          [`documents/${opened.id}`],
        ),
      ).toEqual([{ type: "document.created" }]);
    } finally {
      await s.close();
    }
  });
});
