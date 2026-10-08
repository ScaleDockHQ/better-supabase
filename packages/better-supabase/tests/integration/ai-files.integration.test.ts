import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { AiFileStorage } from "../../src/blocks/ai-files/index.ts";

import {
  aiFileUrl,
  createAiFiles,
  sqlTransport,
} from "../../src/blocks/ai-files/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const BUCKET = "bs-it-ai-files";

/** Signs nothing: the test stores objects through SQL as the caller. */
const storage: AiFileStorage = {
  from: () => ({
    createSignedUploadUrl: (path) =>
      Promise.resolve({
        data: { signedUrl: `https://storage.test/upload/${path}`, token: "t" },
        error: null,
      }),
    createSignedUrl: (path) =>
      Promise.resolve({
        data: { signedUrl: `https://storage.test/sign/${path}` },
        error: null,
      }),
    download: () =>
      Promise.resolve({
        data: new Blob([new Uint8Array([1, 2])]),
        error: null,
      }),
    remove: () => Promise.resolve({ data: [], error: null }),
    upload: () => Promise.resolve({ data: {}, error: null }),
  }),
};

describe.skipIf(!live)("ai-files module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("accepts only the reserved upload and shows files to their owner and the chat", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "ai-chat", "ai-files"], {
        modules: {
          "ai-files": {
            options: { bucket: BUCKET, allowedMimeTypes: ["image/*"] },
          },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });
      expect(
        await s.value<boolean>(
          "exists (select 1 from storage.buckets where id = $1 and not public)",
          [BUCKET],
        ),
      ).toBe(true);
      const files = createAiFiles({ transport: sqlTransport(s.sql), storage });

      await s.asRole(member);
      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1, $2)",
        [tenant, { title: "Pictures" }],
      );
      const wrongType = await files.files.upload(tenant, {
        filename: "a.pdf",
        mediaType: "application/pdf",
        size: 3,
      });
      expect(wrongType.ok ? undefined : wrongType.error.hint).toBe(
        "AI_FILE_TYPE",
      );
      const { file, signedUrl } = await files.files
        .upload(tenant, {
          filename: "cat.png",
          mediaType: "image/png",
          size: 3,
          chatId: chat.id,
        })
        .orThrow();
      expect(file).toMatchObject({
        status: "pending",
        bucket: BUCKET,
        ownerId: member.id,
        path: `${tenant}/${member.id}/${file.id}/cat.png`,
      });
      expect(signedUrl).toContain(file.path);
      const early = await files.files.confirm(file.id);
      expect(early.ok ? undefined : early.error.hint).toBe(
        "AI_FILE_NOT_UPLOADED",
      );

      const store = (name: string): Promise<string> =>
        s.hint(
          `insert into storage.objects (bucket_id, name, owner_id, metadata)
           values ($1, $2, auth.uid()::text, '{"size": 2, "mimetype": "image/png"}')`,
          [BUCKET, name],
        );
      expect(
        await store(`${tenant}/${member.id}/${crypto.randomUUID()}/x.png`),
      ).not.toBe("no error");
      await s.asRole(owner);
      expect(await store(file.path)).not.toBe("no error");
      await s.asRole(member);
      expect(await store(file.path)).toBe("no error");
      const ready = await files.files
        .confirm(file.id, "ab".repeat(32))
        .orThrow();
      expect(ready).toMatchObject({ status: "ready", size: 2 });
      expect(ready.uploadedAt).toBeDefined();

      const visible = (): Promise<number> =>
        s.value<number>(
          "(select count(*)::int from storage.objects where bucket_id = $1)",
          [BUCKET],
        );
      expect(await visible()).toBe(1);
      expect((await files.files.resolve(aiFileUrl(file)).orThrow()).id).toBe(
        file.id,
      );

      await s.asRole(outsider);
      expect(await visible()).toBe(0);
      expect((await files.files.resolve(aiFileUrl(file))).ok).toBe(false);
      expect(await files.files.list(chat.id).orThrow()).toEqual([]);

      // The owner is an ai_chat admin of the organization.
      await s.asRole(owner);
      expect(await visible()).toBe(1);
      expect(
        (await files.files.list(chat.id).orThrow()).map((row) => row.id),
      ).toEqual([file.id]);

      await s.asRole(outsider);
      expect(await files.files.remove(file.id).orThrow()).toBe(false);
      await s.asRole(member);
      expect(await files.files.remove(file.id).orThrow()).toBe(true);
      expect((await files.files.get(file.id)).ok).toBe(false);
    } finally {
      await s.close();
    }
  });

  it("stores generated files, caches provider references and purges stale ones", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "ai-chat", "ai-files"], {
        modules: { "ai-files": { options: { bucket: BUCKET } } },
      });
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);
      await s.as(owner);
      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1, $2)",
        [tenant, { title: "Draw" }],
      );

      await s.service();
      const files = createAiFiles({ transport: sqlTransport(s.sql), storage });
      const generated = await files.files
        .store(tenant, {
          ownerId: owner.id,
          filename: "sun.png",
          mediaType: "image/png",
          data: new Uint8Array([1, 2, 3]),
          chatId: chat.id,
        })
        .orThrow();
      expect(generated).toMatchObject({
        status: "ready",
        source: "generated",
        size: 3,
      });

      expect(
        await files.providerFiles.get(generated.id, "openai").orThrow(),
      ).toBeUndefined();
      await files.providerFiles
        .set(
          generated.id,
          "openai",
          "file-1",
          Temporal.Now.instant().add({ minutes: 30 }),
        )
        .orThrow();
      expect(
        (await files.providerFiles.get(generated.id, "openai").orThrow())
          ?.reference,
      ).toBe("file-1");
      expect(
        (await files.providerFiles.expiring("1 hour").orThrow()).map(
          (row) => row.fileId,
        ),
      ).toContain(generated.id);
      await files.providerFiles
        .set(
          generated.id,
          "openai",
          "file-1",
          Temporal.Now.instant().subtract({ minutes: 1 }),
        )
        .orThrow();
      expect(
        await files.providerFiles.get(generated.id, "openai").orThrow(),
      ).toBeUndefined();

      await s.as(owner);
      const stale = await s.value<{ id: string }>(
        "better_supabase.reserve_ai_file($1, 'old.png', 'image/png', 1)",
        [tenant],
      );
      await s.service();
      await s.rows(
        "update better_supabase.ai_files set created_at = now() - interval '2 days' where id = $1",
        [stale.id],
      );
      expect(await files.files.purge().orThrow()).toBe(1);
      await s.rows("delete from better_supabase.ai_chats where id = $1", [
        chat.id,
      ]);
      expect(await files.files.purge().orThrow()).toBe(1);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.ai_files where organization_id = $1)",
          [tenant],
        ),
      ).toBe(0);

      await s.asRole(owner);
      expect(await s.hint("better_supabase.purge_ai_files()")).toMatch(
        /permission denied/,
      );
    } finally {
      await s.close();
    }
  });

  it("versions documents, guards concurrent edits and resolves suggestions", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "ai-chat", "ai-files"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const tenant = await s.organization(owner, { member });
      const files = createAiFiles({ transport: sqlTransport(s.sql), storage });

      await s.asRole(member);
      const doc = await files.documents
        .create(tenant, { kind: "code", title: "main.ts", content: "a" })
        .orThrow();
      expect(doc.version).toBe(1);
      await files.documents
        .update(doc.id, { content: "b", expectedVersion: 1, messageId: "m1" })
        .orThrow();
      const conflict = await files.documents.update(doc.id, {
        content: "c",
        expectedVersion: 1,
      });
      expect(conflict.ok ? undefined : conflict.error.hint).toBe(
        "AI_DOCUMENT_CONFLICT",
      );
      const rolled = await files.documents.rollback(doc.id, 1).orThrow();
      expect(rolled.version).toBe(3);
      expect((await files.documents.get(doc.id).orThrow()).content).toBe("a");
      expect(
        (await files.documents.versions(doc.id).orThrow()).map((v) => [
          v.version,
          v.content,
          v.messageId,
        ]),
      ).toEqual([
        [3, "a", undefined],
        [2, "b", "m1"],
        [1, "a", undefined],
      ]);

      const suggestion = await files.documents
        .suggest(doc.id, { originalText: "a", suggestedText: "A" })
        .orThrow();
      expect(suggestion.version).toBe(3);
      await files.documents.resolve(suggestion.id, true).orThrow();
      expect(await files.documents.suggestions(doc.id).orThrow()).toEqual([]);

      await s.asRole(outsider);
      expect((await files.documents.get(doc.id)).ok).toBe(false);
      const foreign = await files.documents.update(doc.id, { content: "x" });
      expect(foreign.ok ? undefined : foreign.error.hint).toBe(
        "AI_DOCUMENT_NOT_FOUND",
      );
      const forbidden = await files.documents.create(tenant, {
        kind: "text",
        title: "x",
        content: "x",
      });
      expect(forbidden.ok ? undefined : forbidden.error.hint).toBe(
        "AI_DOCUMENT_FORBIDDEN",
      );
      expect(await files.documents.remove(doc.id).orThrow()).toBe(false);

      await s.asRole(member);
      expect(await files.documents.remove(doc.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });
});
