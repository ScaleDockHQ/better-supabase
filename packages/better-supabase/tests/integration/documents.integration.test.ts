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

  it("takes suggestions from readers and names versions for editors", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const member = await s.user("member");
      const viewer = await s.user("viewer");
      const outsider = await s.user("outsider");
      await s.install(MODULES, {
        modules: {
          documents: {
            options: { maxUpdateBytes: 4096 },
            permissions: {
              read: "organization.read",
              suggest: "organization.read",
            },
          },
        },
      });
      const tenant = await s.organization(owner, { member, viewer });
      const documents = createDocuments({ transport: sqlTransport(s.sql) });

      const ref = {
        organizationId: tenant,
        subjectType: "page",
        subjectId: "p2",
      };

      await s.asRole(member);
      const opened = await documents.open(ref).orThrow();
      expect(opened).toMatchObject({ canWrite: true, canSuggest: true });
      const base = new Y.Doc();
      const first: Uint8Array[] = [];
      base.on("update", (update: Uint8Array) => first.push(update));
      base.getText("t").insert(0, "hello");
      await documents.push(opened.id, Y.mergeUpdates(first)).orThrow();

      await s.asRole(viewer);
      const read = await documents.open(ref).orThrow();
      expect(read).toMatchObject({ canWrite: false, canSuggest: true });
      const draft = new Y.Doc();

      for (const item of read.updates) {
        Y.applyUpdate(draft, item.update);
      }

      const drafted: Uint8Array[] = [];
      draft.on("update", (update: Uint8Array) => drafted.push(update));
      draft.getText("t").insert(5, " world");
      const change = Y.mergeUpdates(drafted);
      expect(await documents.push(opened.id, change).then(hint)).toBe(
        "DOCUMENT_FORBIDDEN",
      );
      expect(
        await documents.suggest(opened.id, new Uint8Array(5000)).then(hint),
      ).toBe("DOCUMENT_UPDATE_TOO_LARGE");

      const suggested = await documents
        .suggest(opened.id, change, " Finish the greeting ")
        .orThrow();

      expect(suggested).toMatchObject({
        status: "open",
        summary: "Finish the greeting",
        createdBy: viewer.id,
      });
      expect(suggested.update).toEqual(change);
      expect(
        await documents.decideSuggestion(suggested.id, "accepted").then(hint),
      ).toBe("DOCUMENT_FORBIDDEN");

      await s.asRole(outsider);
      expect(await documents.suggest(opened.id, change).then(hint)).toBe(
        "DOCUMENT_NOT_FOUND",
      );
      expect(
        await documents.decideSuggestion(suggested.id, "rejected").then(hint),
      ).toBe("DOCUMENT_SUGGESTION_NOT_FOUND");

      await s.asRole(member);
      expect(await documents.suggestions(opened.id).orThrow()).toHaveLength(1);
      expect(
        await documents
          .decideSuggestion(suggested.id, "maybe" as "accepted")
          .then(hint),
      ).toBe("DOCUMENT_SUGGESTION_INVALID");
      expect(
        await documents.decideSuggestion(suggested.id, "withdrawn").then(hint),
      ).toBe("DOCUMENT_FORBIDDEN");

      const accepted = await documents
        .decideSuggestion(suggested.id, "accepted", "Thanks")
        .orThrow();

      expect(accepted).toMatchObject({
        status: "accepted",
        decidedBy: member.id,
        note: "Thanks",
      });
      expect(accepted.seq).toBeGreaterThan(0);
      expect(
        await documents.decideSuggestion(suggested.id, "rejected").then(hint),
      ).toBe("DOCUMENT_SUGGESTION_CLOSED");
      const state = await documents.pull(opened.id, 0).orThrow();
      const merged = new Y.Doc();

      for (const item of state.updates) {
        Y.applyUpdate(merged, item.update);
      }

      expect(merged.getText("t").toString()).toBe("hello world");

      await s.asRole(viewer);
      const second = await documents.suggest(opened.id, change).orThrow();
      const third = await documents.suggest(opened.id, change).orThrow();

      const withdrawn = await documents
        .decideSuggestion(third.id, "withdrawn")
        .orThrow();

      expect(withdrawn.status).toBe("withdrawn");
      expect(withdrawn.seq).toBeUndefined();

      await s.asRole(member);
      expect(
        (
          await documents
            .decideSuggestion(second.id, "rejected", "Already in")
            .orThrow()
        ).status,
      ).toBe("rejected");
      expect(await documents.suggestions(opened.id).orThrow()).toEqual([]);
      expect(
        (await documents.suggestions(opened.id, { status: "all" }).orThrow())
          .map((item) => item.status)
          .toSorted(),
      ).toEqual(["accepted", "rejected", "withdrawn"]);

      const saved = await documents
        .saveVersion(opened.id, Y.encodeStateAsUpdate(merged))
        .orThrow();

      expect(
        await documents.versions(opened.id, { named: true }).orThrow(),
      ).toEqual([]);
      expect(
        await documents
          .nameVersion(opened.id, saved.id, " Approved ")
          .orThrow(),
      ).toBe(true);

      const named = await documents
        .versions(opened.id, { named: true })
        .orThrow();

      expect(named).toMatchObject([
        { id: saved.id, label: "Approved", source: "manual", frozen: false },
      ]);
      expect(
        await documents.nameVersion(opened.id, opened.id, "Missing").then(hint),
      ).toBe("DOCUMENT_VERSION_NOT_FOUND");
      await documents.nameVersion(opened.id, saved.id, null).orThrow();
      expect(
        await documents.versions(opened.id, { named: true }).orThrow(),
      ).toEqual([]);

      await s.asRole(viewer);
      expect(
        await documents.nameVersion(opened.id, saved.id, "Mine").then(hint),
      ).toBe("DOCUMENT_FORBIDDEN");

      await s.service();

      const frozen = await s.value<{ id: string }>(
        "better_supabase.version_insert($1, 'document', $2, '{}'::jsonb, null, 'Signed', 'auto', true, null)",
        [tenant, opened.id],
      );

      await s.asRole(member);
      expect(
        await documents.nameVersion(opened.id, frozen.id, "Other").then(hint),
      ).toBe("DOCUMENT_VERSION_FROZEN");

      await s.service();
      expect(
        await s.rows<{ actor: string }>(
          "select actor from better_supabase.document_updates where document_id = $1 order by seq",
          [opened.id],
        ),
      ).toEqual([{ actor: member.id }, { actor: viewer.id }]);
      expect(
        await s.rows<{ type: string }>(
          "select type from better_supabase.outbox_events where subject = $1 order by type",
          [`documents/${opened.id}`],
        ),
      ).toEqual([
        { type: "document.created" },
        { type: "document.suggested" },
        { type: "document.suggested" },
        { type: "document.suggested" },
        { type: "document.suggestion_accepted" },
        { type: "document.suggestion_rejected" },
      ]);
    } finally {
      await s.close();
    }
  });
});
