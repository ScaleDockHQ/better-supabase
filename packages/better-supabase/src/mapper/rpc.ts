import type { Readable, Writable } from "node:stream";

/** One method of the content mapper protocol. */
export type Handler = (params: unknown) => unknown;

export type Handlers = Readonly<Record<string, Handler>>;

interface Request {
  readonly id?: number | string;
  readonly method?: unknown;
  readonly params?: unknown;
}

const HEADER_END = "\r\n\r\n";
const CONTENT_LENGTH = /content-length:\s*(\d+)/i;

/** Frames a JSON-RPC message with the `Content-Length` header tsc reads. */
export function encodeFrame(message: unknown): Buffer {
  const body = Buffer.from(JSON.stringify(message), "utf-8");

  return Buffer.concat([
    Buffer.from(`Content-Length: ${body.length}${HEADER_END}`, "ascii"),
    body,
  ]);
}

/**
 * Splits a byte stream into the JSON bodies of its frames. A chunk may hold
 * part of a frame or several, so the reader keeps what it hasn't consumed.
 */
export function frameReader(
  onMessage: (message: unknown) => void,
): (chunk: Buffer) => void {
  let buffer = Buffer.alloc(0);

  return (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);

    for (;;) {
      const headerEnd = buffer.indexOf(HEADER_END);

      if (headerEnd === -1) {
        return;
      }

      const header = buffer.subarray(0, headerEnd).toString("ascii");
      const length = Number(CONTENT_LENGTH.exec(header)?.[1] ?? Number.NaN);

      if (Number.isNaN(length)) {
        throw new TypeError(
          `The frame header has no Content-Length: ${header}`,
        );
      }

      const start = headerEnd + HEADER_END.length;

      if (buffer.length < start + length) {
        return;
      }

      const body = buffer.subarray(start, start + length).toString("utf-8");
      buffer = buffer.subarray(start + length);
      onMessage(JSON.parse(body));
    }
  };
}

const isRequest = (value: unknown): value is Request =>
  typeof value === "object" && value !== null;

/**
 * Answers one message. A notification (no `id`) gets no response; a failing
 * handler answers with a JSON-RPC internal error instead of throwing, so tsc
 * reports it on the file.
 */
export async function dispatch(
  handlers: Handlers,
  message: unknown,
): Promise<Record<string, unknown> | undefined> {
  const request = isRequest(message) ? message : {};
  const method = typeof request.method === "string" ? request.method : "";

  const handler = Object.hasOwn(handlers, method)
    ? handlers[method]
    : undefined;

  let response: Record<string, unknown>;

  try {
    if (handler === undefined) {
      throw new Error(`Unknown method ${method}`);
    }

    const result: unknown = await handler(request.params);
    response = { jsonrpc: "2.0", id: request.id, result: result ?? null };
  } catch (error) {
    response = {
      jsonrpc: "2.0",
      id: request.id,
      error: {
        code: -32_603,
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }

  return request.id === undefined ? undefined : response;
}

/**
 * Serves `handlers` over a pair of streams until the input ends. tsc closes the
 * pipe when it's done with the mapper, and `onEnd` lets the bin exit then.
 */
export function serve(
  handlers: Handlers,
  input: Readable,
  output: Writable,
  onEnd: () => void = () => {},
): void {
  const read = frameReader((message) => {
    void dispatch(handlers, message).then((response) => {
      if (response !== undefined) {
        output.write(encodeFrame(response));
      }
    });
  });

  input.on("data", (chunk: Buffer) => {
    read(chunk);
  });
  input.on("end", onEnd);
}
