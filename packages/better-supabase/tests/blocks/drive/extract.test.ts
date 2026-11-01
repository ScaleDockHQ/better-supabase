import { describe, expect, it } from "vitest";

import type {
  DriveTextKnowledge,
  TextExtractor,
} from "../../../src/blocks/drive/index.ts";

import {
  createDriveText,
  plainTextExtractor,
  textExtractorOf,
} from "../../../src/blocks/drive/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { testTextExtractor } from "../../../src/testing/index.ts";

const SOURCE = {
  nodeId: "n1",
  organizationId: "org-1",
  name: "notes.txt",
  attachmentId: "a2",
  bucket: "attachments",
  path: "org-1/attachments/a2",
  mimeType: "text/plain",
  size: 11,
  status: "clean",
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

function fakeStorage(body = "hello world") {
  const downloads: string[] = [];

  return {
    downloads,
    storage: {
      from: () => ({
        download: (path: string) => {
          downloads.push(path);

          return Promise.resolve({ data: new Blob([body]), error: null });
        },
      }),
    },
  };
}

function fakeKnowledge(existing: readonly string[] = []) {
  const calls: unknown[][] = [];

  const knowledge = {
    documents: {
      list: (organizationId: string, options: unknown) => {
        calls.push(["list", organizationId, options]);

        return AsyncResult.ok(existing.map((id) => ({ id })));
      },
      remove: (id: string) => {
        calls.push(["remove", id]);

        return AsyncResult.ok(true);
      },
    },
    ingest: {
      text: ({
        organizationId,
        document,
      }: {
        organizationId: string | null;
        document: unknown;
      }) => {
        calls.push(["ingest", organizationId, document]);

        return AsyncResult.ok({ id: "k-new" });
      },
    },
    // SAFETY: the fake returns only the fields createDriveText reads.
  } as unknown as DriveTextKnowledge;

  return { calls, knowledge };
}

const setup = (
  results: Record<string, unknown>,
  extractor: TextExtractor = plainTextExtractor(),
  knowledge?: DriveTextKnowledge,
) => {
  const transport = fakeTransport(results);
  const storage = fakeStorage();

  return {
    ...transport,
    storage,
    text: createDriveText({
      transport: transport.transport,
      storage: storage.storage,
      extractor,
      ...(knowledge === undefined ? {} : { knowledge }),
    }),
  };
};

describe("textExtractorOf", () => {
  it("checks the version and the name", () => {
    const extractor = plainTextExtractor();
    expect(textExtractorOf(extractor)).toBe(extractor);
    expect(() =>
      textExtractorOf({
        ...extractor,
        apiVersion: 2,
      } as unknown as TextExtractor),
    ).toThrow(/targets API 2/);
    expect(() => textExtractorOf({ ...extractor, name: "Plain Text" })).toThrow(
      /name/,
    );
  });
});

describe("plainTextExtractor", () => {
  it("passes the conformance kit and reads text types only", async () => {
    const report = await testTextExtractor(plainTextExtractor());
    expect(report.checks.filter((check) => !check.ok)).toEqual([]);

    const extractor = plainTextExtractor();
    expect(
      await extractor.extract(new Blob(['{"a":1}']), {
        ...SOURCE,
        mimeType: "application/json",
      }),
    ).toBe('{"a":1}');
    expect(
      await extractor.extract(new Blob(["%PDF"]), {
        ...SOURCE,
        mimeType: "application/pdf",
      }),
    ).toBeUndefined();
  });
});

describe("createDriveText", () => {
  it("stores the text of a clean file for its current revision", async () => {
    const { text, calls, storage } = setup({
      drive_text_source: SOURCE,
      drive_set_text: true,
    });

    expect(await text.extract({ nodeId: "n1" }).orThrow()).toBe("stored");
    expect(storage.downloads).toEqual(["org-1/attachments/a2"]);
    expect(calls).toEqual([
      ["drive_text_source", { node: "n1" }],
      [
        "drive_set_text",
        {
          node: "n1",
          attachment: "a2",
          content: "hello world",
          extractor: "plain-text",
        },
      ],
    ]);
  });

  it("skips folders, unscanned files and replaced revisions", async () => {
    expect(
      await setup({ drive_text_source: null })
        .text.extract({ nodeId: "n1" })
        .orThrow(),
    ).toBe("skipped");

    const pending = setup({
      drive_text_source: { ...SOURCE, status: "pending" },
    });

    expect(await pending.text.extract({ nodeId: "n1" }).orThrow()).toBe(
      "skipped",
    );
    expect(pending.storage.downloads).toEqual([]);

    expect(
      await setup({ drive_text_source: SOURCE, drive_set_text: false })
        .text.extract({ nodeId: "n1" })
        .orThrow(),
    ).toBe("skipped");
  });

  it("clears the text of a file it can't read or that is too large", async () => {
    const unread = setup({
      drive_text_source: { ...SOURCE, mimeType: "image/png" },
      drive_set_text: true,
    });

    expect(await unread.text.extract({ nodeId: "n1" }).orThrow()).toBe(
      "cleared",
    );
    expect(unread.calls[1]?.[1]).toMatchObject({ content: null });

    const transport = fakeTransport({
      drive_text_source: { ...SOURCE, size: 100 },
      drive_set_text: true,
    });

    const storage = fakeStorage();

    const large = createDriveText({
      transport: transport.transport,
      storage: storage.storage,
      extractor: plainTextExtractor(),
      maxFileBytes: 10,
    });

    expect(await large.extract({ nodeId: "n1" }).orThrow()).toBe("cleared");
    expect(storage.downloads).toEqual([]);
  });

  it("fails with DRIVE_TEXT_FAILED when the extractor throws", async () => {
    const { text, calls } = setup(
      { drive_text_source: SOURCE },
      {
        name: "broken",
        extract: () => {
          throw new Error("no parser");
        },
      },
    );

    const result = await text.extract({ nodeId: "n1" });
    expect(result.ok ? undefined : result.error.hint).toBe("DRIVE_TEXT_FAILED");
    expect(calls.map(([fn]) => fn)).toEqual(["drive_text_source"]);
  });

  it("replaces the node's subject knowledge document", async () => {
    const { knowledge, calls } = fakeKnowledge(["k-old"]);

    const { text } = setup(
      { drive_text_source: SOURCE, drive_set_text: true },
      plainTextExtractor(),
      knowledge,
    );

    expect(await text.extract({ nodeId: "n1" }).orThrow()).toBe("stored");
    const subject = { type: "drive_node", id: "n1" };
    expect(calls).toEqual([
      ["list", "org-1", { scope: "subject", subject }],
      ["remove", "k-old"],
      [
        "ingest",
        "org-1",
        {
          title: "notes.txt",
          scope: "subject",
          subject,
          source: "notes.txt",
          metadata: { nodeId: "n1", attachmentId: "a2" },
          text: "hello world",
        },
      ],
    ]);
  });

  it("extracts from clean drive uploads in the outbox", async () => {
    const { text, calls } = setup({
      drive_text_source: SOURCE,
      drive_set_text: true,
    });

    await text.sink().send([
      {
        type: "dev.better-supabase.attachment.scanned",
        data: { attachmentId: "a2", status: "clean" },
      },
      {
        type: "dev.better-supabase.attachment.uploaded",
        data: { attachmentId: "a9", subjectType: "project", subjectId: "p1" },
      },
      { type: "dev.better-supabase.drive.node_created", data: {} },
      // SAFETY: the sink reads only type and data.
    ] as never);

    expect(calls).toEqual([
      ["drive_text_source", { attachment: "a2" }],
      [
        "drive_set_text",
        {
          node: "n1",
          attachment: "a2",
          content: "hello world",
          extractor: "plain-text",
        },
      ],
    ]);
  });
});
