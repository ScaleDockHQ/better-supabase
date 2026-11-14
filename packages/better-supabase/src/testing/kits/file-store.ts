import type { Result } from "../../core/result.ts";
import type { FileStore } from "../../storage/file-store.ts";
import type { ConformanceReport } from "../conformance.ts";

import { conform, expect } from "../conformance.ts";

export interface TestFileStoreOptions {
  /** A bucket the store may write to; the kit deletes what it writes. */
  readonly bucket: string;
  /** The path the kit writes. Default a fresh `conformance/<uuid>.txt`. */
  readonly path?: string;
  /**
   * Fetches the signed download URL and checks its bytes, and sends a file to
   * the signed upload URL. Without it the kit only checks the URLs' shape.
   */
  readonly fetch?: (url: string, init?: RequestInit) => Promise<Response>;
}

const kindOf = (result: Result<unknown>): string =>
  result.ok ? "ok" : result.error.kind;

const typeOf = (type: string): string =>
  (type.split(";")[0] ?? "").trim().toLowerCase();

const isUrl = (value: string): boolean => URL.canParse(value);

const METHODS: ReadonlySet<string> = new Set(["PUT", "POST"]);

/**
 * Runs the `FileStore` contract against `store`: the API version, put and get
 * with the same bytes and type, a put without `upsert` on a taken path, an
 * overwrite with `upsert`, a signed download URL, `head` and `signedUploadUrl`
 * when the store has them, and deletes that leave `get` answering `not_found`.
 * Run it against a test bucket or store: it writes one or two small files and
 * deletes them.
 */
export function testFileStore(
  store: FileStore,
  options: TestFileStoreOptions,
): Promise<ConformanceReport> {
  const { bucket } = options;
  const path = options.path ?? `conformance/${crypto.randomUUID()}.txt`;
  const uploadPath = `${path}.upload`;
  const first = "conformance one";
  const second = "conformance two";
  let written = false;

  const wrote = async (): Promise<void> => {
    if (!written) {
      await store
        .put(bucket, path, new Blob([first]), { contentType: "text/plain" })
        .orThrow();
      written = true;
    }
  };

  return conform(`FileStore "${store.name}"`, [
    [
      "has apiVersion 1 and a name",
      () => {
        const version: unknown = store.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(store.name.length > 0, "name is empty");
      },
    ],
    [
      "puts a file and gets the same bytes and type",
      async () => {
        await wrote();
        const file = await store.get(bucket, path).orThrow();

        expect(
          (await file.text()) === first,
          "get returned other bytes than put stored",
        );
        expect(
          typeOf(file.type) === "text/plain",
          `get typed the file "${file.type}", not text/plain`,
        );
      },
    ],
    [
      "refuses a put without upsert on a taken path",
      async () => {
        await wrote();

        const again = await store.put(bucket, path, new Blob([second]), {
          contentType: "text/plain",
        });

        expect(!again.ok, "a second put without upsert succeeded");

        const kept = await store.get(bucket, path).orThrow();

        expect(
          (await kept.text()) === first,
          "the refused put changed the file",
        );
      },
    ],
    [
      "overwrites a file with upsert",
      async () => {
        await wrote();
        await store
          .put(bucket, path, new TextEncoder().encode(second), {
            contentType: "text/plain",
            upsert: true,
          })
          .orThrow();

        const file = await store.get(bucket, path).orThrow();

        expect(
          (await file.text()) === second,
          "upsert did not replace the bytes",
        );
      },
    ],
    [
      "signs a download URL",
      async () => {
        await wrote();

        const url = await store
          .signedUrl(bucket, path, { expiresIn: 60 })
          .orThrow();

        expect(isUrl(url), `signedUrl returned "${url}"`);

        const download = await store
          .signedUrl(bucket, path, { expiresIn: 60, download: "file.txt" })
          .orThrow();

        expect(
          isUrl(download),
          `signedUrl with download returned "${download}"`,
        );

        if (options.fetch !== undefined) {
          const response = await options.fetch(url);
          expect(response.ok, `the signed URL answered ${response.status}`);

          const text = await response.text();
          expect(
            text === first || text === second,
            "the signed URL served other bytes",
          );
        }
      },
    ],
    store.head !== undefined && [
      "reads the size and type with head, and undefined for a missing file",
      async () => {
        await wrote();

        if (store.head === undefined) {
          return;
        }

        const found = await store.head(bucket, path).orThrow();

        expect(found !== undefined, "head found no file at the written path");
        expect(
          found.size === first.length || found.size === second.length,
          `head gave size ${found.size}`,
        );
        expect(
          typeOf(found.contentType) === "text/plain",
          `head gave type "${found.contentType}"`,
        );

        const missing = await store
          .head(bucket, `${path}.missing-${crypto.randomUUID()}`)
          .orThrow();

        expect(missing === undefined, "head found a file that doesn't exist");
      },
    ],
    store.signedUploadUrl !== undefined && [
      "signs an upload URL",
      async () => {
        if (store.signedUploadUrl === undefined) {
          return;
        }

        const upload = await store
          .signedUploadUrl(bucket, uploadPath, {
            expiresIn: 60,
            contentType: "text/plain",
            maxSize: 1024,
          })
          .orThrow();

        const method: string = upload.method;

        expect(isUrl(upload.url), `signedUploadUrl returned "${upload.url}"`);
        expect(METHODS.has(method), `signedUploadUrl gave method ${method}`);

        if (options.fetch !== undefined) {
          const response = await options.fetch(upload.url, {
            method: upload.method,
            headers: { "content-type": "text/plain", ...upload.headers },
            body: new Blob([first], { type: "text/plain" }),
          });

          expect(response.ok, `the upload URL answered ${response.status}`);

          const file = await store.get(bucket, uploadPath).orThrow();

          expect(
            (await file.text()) === first,
            "the uploaded file has other bytes",
          );
        }
      },
    ],
    [
      "deletes files, after which get answers not_found",
      async () => {
        await wrote();
        await store.delete(bucket, [path, uploadPath]).orThrow();

        const gone = await store.get(bucket, path);

        expect(
          kindOf(gone) === "not_found",
          `get after delete gave ${kindOf(gone)}`,
        );
      },
    ],
    [
      "deletes a missing path and an empty list without an error",
      async () => {
        const missing = await store.delete(bucket, [
          `${path}.missing-${crypto.randomUUID()}`,
        ]);

        expect(missing.ok, `deleting a missing path gave ${kindOf(missing)}`);

        const none = await store.delete(bucket, []);

        expect(none.ok, `deleting no paths gave ${kindOf(none)}`);
      },
    ],
  ]);
}
