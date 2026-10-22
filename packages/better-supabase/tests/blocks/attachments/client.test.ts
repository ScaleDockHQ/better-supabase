import { afterEach, describe, expect, it, vi } from "vitest";

import type {
  AttachmentScanState,
  AttachmentSend,
  AttachmentUploadTicket,
} from "../../../src/blocks/attachments/client.ts";
import type { NewAttachment } from "../../../src/blocks/attachments/index.ts";
import type { Result } from "../../../src/core/result.ts";

import {
  createAttachmentUploadController,
  xhrSend,
} from "../../../src/blocks/attachments/client.ts";
import { dbError } from "../../../src/core/errors.ts";
import { err, ok } from "../../../src/core/result.ts";
import { failed, flush, mount, resolved } from "../../fixtures/ports.ts";

const file = (body = "hello", type = "image/png") => new Blob([body], { type });

function setup(
  scans: readonly AttachmentScanState[] = [{ status: "clean" }],
  more: { refresh?: boolean; send?: AttachmentSend } = {},
) {
  let created = 0;

  const start = vi.fn((_file: NewAttachment) => {
    created += 1;

    return resolved<AttachmentUploadTicket>({
      id: `a${String(created)}`,
      signedUrl: `https://s/upload/a${String(created)}`,
    });
  });

  const queue = [...scans];

  const next = () =>
    resolved<AttachmentScanState>(queue.shift() ?? { status: "clean" });

  const confirm = vi.fn((_id: string) => next());
  const refresh = vi.fn((_id: string) => next());

  const send = vi.fn<AttachmentSend>(
    more.send ??
      ((_ticket, _body, progress) => {
        progress(0.5);
        progress(2);

        return Promise.resolve(ok(null));
      }),
  );

  const onUploaded = vi.fn();

  const controller = createAttachmentUploadController({
    start,
    confirm,
    ...(more.refresh === false ? {} : { refresh }),
    send,
    pollInterval: 10,
    onUploaded,
  });

  return { start, confirm, refresh, send, onUploaded, controller };
}

afterEach(() => {
  vi.useRealTimers();
});

describe("createAttachmentUploadController", () => {
  it("uploads, confirms and finishes a clean file", async () => {
    const { start, send, onUploaded, controller } = setup();
    const { view, unmount } = mount(controller);

    view().add([]);
    expect(view().uploads).toEqual([]);

    view().add([
      { file: file(), name: "photo.png", width: 800, height: 600, pages: 1 },
    ]);
    expect(view().busy).toBe(true);
    expect(view().uploads[0]).toMatchObject({
      name: "photo.png",
      mimeType: "image/png",
      status: "uploading",
    });

    await flush();

    expect(start).toHaveBeenCalledWith({
      name: "photo.png",
      mimeType: "image/png",
      size: 5,
      width: 800,
      height: 600,
      pages: 1,
    });
    expect(send.mock.calls[0]?.[0]).toEqual({
      id: "a1",
      signedUrl: "https://s/upload/a1",
    });
    expect(view().uploads[0]).toMatchObject({
      status: "done",
      progress: 1,
      id: "a1",
    });
    expect(view().busy).toBe(false);
    expect(onUploaded).toHaveBeenCalledWith("a1");

    view().clear();
    expect(view().uploads).toEqual([]);
    unmount();
  });

  it("watches a pending scan until it answers", async () => {
    const { refresh, onUploaded, controller } = setup([
      { status: "pending" },
      { status: "pending" },
      { status: "clean" },
    ]);

    const { view, unmount } = mount(controller);

    view().add([
      { file: file("x", ""), name: "notes", mimeType: "text/plain" },
    ]);
    await flush();
    expect(view().uploads[0]?.status).toBe("scanning");

    await vi.waitFor(() => {
      expect(view().uploads[0]?.status).toBe("done");
    });
    expect(refresh).toHaveBeenCalledTimes(2);
    expect(onUploaded).toHaveBeenCalledWith("a1");
    unmount();
  });

  it("finishes a pending file without refresh, and an unscanned one", async () => {
    const { controller } = setup([{ status: "pending" }, null], {
      refresh: false,
    });

    const { view, unmount } = mount(controller);

    view().add([
      { file: file("a", ""), name: "a.bin" },
      { file: file("b"), name: "b.png" },
    ]);
    await flush();

    expect(view().uploads.map((item) => item.status)).toEqual(["done", "done"]);
    expect(view().uploads[0]?.mimeType).toBe("application/octet-stream");
    unmount();
  });

  it("blocks an infected file and fails a failed scan", async () => {
    const { controller } = setup([
      { status: "infected" },
      { status: "failed" },
    ]);

    const { view, unmount } = mount(controller);

    view().add([
      { file: file(), name: "a.png" },
      { file: file(), name: "b.png" },
    ]);
    await flush();

    expect(view().uploads[0]?.status).toBe("blocked");
    expect(view().uploads[1]).toMatchObject({
      status: "error",
      error: { hint: "ATTACHMENT_SCAN_FAILED" },
    });

    view().dismiss(view().uploads[1]?.key ?? "");
    expect(view().uploads).toHaveLength(1);
    unmount();
  });

  it("keeps a failed step with its error and retries it", async () => {
    const { start, controller } = setup();

    start.mockReturnValueOnce(failed("no room"));
    const { view, unmount } = mount(controller);

    view().add([{ file: file(), name: "a.png" }]);
    await flush();

    const [item] = view().uploads;

    expect(item?.status).toBe("error");
    expect(view().busy).toBe(false);

    view().retry("missing");
    view().retry(item?.key ?? "");
    await flush();
    expect(view().uploads[0]?.status).toBe("done");

    view().retry(item?.key ?? "");
    await flush();
    expect(start).toHaveBeenCalledTimes(2);
    unmount();
  });

  it("reports a send, confirm or refresh error", async () => {
    const refused = setup([], {
      send: () =>
        Promise.resolve(err(dbError("network", "refused", { hint: "X" }))),
    });

    const sent = mount(refused.controller);

    sent.view().add([{ file: file(), name: "a.png" }]);
    await flush();
    expect(sent.view().uploads[0]?.error?.hint).toBe("X");
    sent.unmount();

    const unconfirmed = setup();

    unconfirmed.confirm.mockReturnValueOnce(failed("gone"));
    const confirmed = mount(unconfirmed.controller);

    confirmed.view().add([{ file: file(), name: "a.png" }]);
    await flush();
    expect(confirmed.view().uploads[0]?.status).toBe("error");
    confirmed.unmount();

    const lost = setup([{ status: "pending" }]);

    lost.refresh.mockReturnValueOnce(failed("gone"));
    const refreshed = mount(lost.controller);

    refreshed.view().add([{ file: file(), name: "a.png" }]);
    await vi.waitFor(() => {
      expect(refreshed.view().uploads[0]?.status).toBe("error");
    });
    refreshed.unmount();
  });

  it("keeps the upload when onUploaded throws", async () => {
    const { onUploaded, controller } = setup();

    onUploaded.mockRejectedValueOnce(new Error("refresh failed"));
    const { view, unmount } = mount(controller);

    view().add([{ file: file(), name: "a.png" }]);
    await vi.waitFor(() => {
      expect(view().uploads[0]?.error).toBeDefined();
    });
    expect(view().uploads[0]?.status).toBe("done");
    unmount();
  });

  it("drops a dismissed upload's late answers", async () => {
    let release: (() => void) | undefined;

    const { confirm, controller } = setup([], {
      send: (_ticket, _body, _progress, signal) =>
        new Promise((resolve) => {
          release = () => {
            resolve(
              signal.aborted ? err(dbError("aborted", "stopped")) : ok(null),
            );
          };
        }),
    });

    const { view, unmount } = mount(controller);

    view().add([{ file: file(), name: "a.png" }]);
    await flush();
    view().dismiss(view().uploads[0]?.key ?? "");
    release?.();
    await flush();

    expect(view().uploads).toEqual([]);
    expect(confirm).not.toHaveBeenCalled();
    unmount();
  });

  it("stops polling when the last listener leaves and resumes on the next", async () => {
    const { refresh, controller } = setup([
      { status: "pending" },
      { status: "clean" },
    ]);

    const first = mount(controller);

    first.view().add([{ file: file(), name: "a.png" }]);
    await flush();
    first.unmount();
    await new Promise((resolve) => {
      setTimeout(resolve, 30);
    });
    expect(refresh).not.toHaveBeenCalled();

    const second = mount(controller);

    await vi.waitFor(() => {
      expect(second.view().uploads[0]?.status).toBe("done");
    });
    second.unmount();
  });
});

describe("createAttachmentUploadController after a dismiss", () => {
  const deferred = <T>() => {
    let resolve: (value: T) => void = () => undefined;

    const promise = new Promise<T>((done) => {
      resolve = done;
    });

    return { promise, resolve };
  };

  it("ignores a late start, progress, confirm and refresh", async () => {
    const started = deferred<ReturnType<typeof ok<AttachmentUploadTicket>>>();
    const confirmed = deferred<ReturnType<typeof ok<AttachmentScanState>>>();
    const refreshed = deferred<Result<AttachmentScanState>>();
    let progress: ((fraction: number) => void) | undefined;
    const ticket = { id: "a1", signedUrl: "https://s/upload/a1" };

    const start = vi
      .fn()
      .mockReturnValueOnce(started.promise)
      .mockResolvedValue(ok(ticket));

    const confirm = vi
      .fn()
      .mockReturnValueOnce(confirmed.promise)
      .mockResolvedValue(ok({ status: "pending" }));

    const controller = createAttachmentUploadController({
      start,
      confirm,
      refresh: () => refreshed.promise,
      send: (_ticket, _body, report) => {
        progress = report;

        return Promise.resolve(ok(null));
      },
      pollInterval: 1,
    });

    const { view, unmount } = mount(controller);
    const key = () => view().uploads[0]?.key ?? "";

    view().add([{ file: file(), name: "late-start.png" }]);
    view().dismiss(key());
    started.resolve(ok(ticket));
    await flush();
    expect(view().uploads).toEqual([]);

    view().add([{ file: file(), name: "late-confirm.png" }]);
    await flush();
    const late = key();
    view().dismiss(late);
    progress?.(0.5);
    confirmed.resolve(ok({ status: "clean" }));
    await flush();
    expect(view().uploads).toEqual([]);

    view().add([{ file: file(), name: "late-refresh.png" }]);
    await vi.waitFor(() => {
      expect(view().uploads[0]?.status).toBe("scanning");
    });
    view().retry(key());
    view().retry("missing");
    await new Promise((resolve) => {
      setTimeout(resolve, 5);
    });
    view().dismiss(key());
    refreshed.resolve(err(dbError("network", "down")));
    await flush();
    expect(view().uploads).toEqual([]);
    unmount();
  });

  it("defaults to XMLHttpRequest and a two-second poll", async () => {
    vi.stubGlobal("XMLHttpRequest", undefined);

    const controller = createAttachmentUploadController({
      start: () =>
        Promise.resolve(ok({ id: "a1", signedUrl: "https://s/upload/a1" })),
      confirm: () => Promise.resolve(ok(null)),
    });

    const { view, unmount } = mount(controller);

    view().add([{ file: file(), name: "a.png" }]);
    await vi.waitFor(() => {
      expect(view().uploads[0]?.status).toBe("error");
    });
    unmount();
    vi.unstubAllGlobals();
  });
});

describe("xhrSend", () => {
  const ticket = { id: "a1", signedUrl: "https://s/upload/a1" };

  function fakeXhr(outcome: "load" | "error" | "abort", status = 200) {
    const sent: { method?: string; url?: string; headers: [string, string][] } =
      { headers: [] };

    class FakeXhr {
      status = status;
      private readonly listeners = new Map<string, () => void>();
      private progressListener:
        | ((event: { loaded: number; total: number }) => void)
        | undefined;

      readonly upload = {
        addEventListener: (
          _type: "progress",
          listener: (event: { loaded: number; total: number }) => void,
        ) => {
          this.progressListener = listener;
        },
      };

      open(method: string, url: string) {
        sent.method = method;
        sent.url = url;
      }

      setRequestHeader(name: string, value: string) {
        sent.headers.push([name, value]);
      }

      addEventListener(type: string, listener: () => void) {
        this.listeners.set(type, listener);
      }

      abort() {
        this.listeners.get("abort")?.();
      }

      send() {
        this.progressListener?.({ loaded: 0, total: 0 });
        this.progressListener?.({ loaded: 5, total: 10 });

        if (outcome !== "abort") {
          this.listeners.get(outcome)?.();
        }
      }
    }

    vi.stubGlobal("XMLHttpRequest", FakeXhr);

    return sent;
  }

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("PUTs the file with progress", async () => {
    const sent = fakeXhr("load");
    const progress = vi.fn();

    const result = await xhrSend(
      ticket,
      file(),
      progress,
      new AbortController().signal,
    );

    expect(result).toEqual(ok(null));
    expect(sent).toEqual({
      method: "PUT",
      url: "https://s/upload/a1",
      headers: [
        ["x-upsert", "false"],
        ["content-type", "image/png"],
      ],
    });
    expect(progress).toHaveBeenCalledExactlyOnceWith(0.5);
  });

  it("maps a refused, failed or stopped upload", async () => {
    fakeXhr("load", 403);
    expect(
      await xhrSend(
        ticket,
        file("x", ""),
        () => {},
        new AbortController().signal,
      ),
    ).toMatchObject({
      ok: false,
      error: { hint: "ATTACHMENT_UPLOAD_FAILED", message: /403/ },
    });

    fakeXhr("error");
    expect(
      await xhrSend(ticket, file(), () => {}, new AbortController().signal),
    ).toMatchObject({ ok: false, error: { kind: "network" } });

    fakeXhr("abort");
    const abort = new AbortController();
    const pending = xhrSend(ticket, file(), () => {}, abort.signal);

    abort.abort();
    expect(await pending).toMatchObject({
      ok: false,
      error: { kind: "aborted" },
    });
  });

  it("fails without XMLHttpRequest", async () => {
    vi.stubGlobal("XMLHttpRequest", undefined);

    expect(
      await xhrSend(ticket, file(), () => {}, new AbortController().signal),
    ).toMatchObject({ ok: false, error: { kind: "invalid_request" } });
  });
});
