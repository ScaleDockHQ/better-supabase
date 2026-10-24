import { PassThrough } from "node:stream";
import { setTimeout } from "node:timers/promises";
import { describe, expect, it } from "vitest";

import {
  dispatch,
  encodeFrame,
  frameReader,
  serve,
} from "../../src/mapper/rpc.ts";

describe("frameReader", () => {
  it("reads frames split across chunks and several in one chunk", () => {
    const seen: unknown[] = [];
    const read = frameReader((message) => seen.push(message));
    const one = encodeFrame({ id: 1, text: "é" });
    const two = encodeFrame({ id: 2 });

    read(one.subarray(0, 5));
    read(one.subarray(5, 20));
    expect(seen).toEqual([]);
    read(Buffer.concat([one.subarray(20), two]));
    expect(seen).toEqual([{ id: 1, text: "é" }, { id: 2 }]);
  });

  it("counts the body in bytes", () => {
    expect(encodeFrame("é").toString("utf-8")).toBe(
      'Content-Length: 4\r\n\r\n"é"',
    );
  });

  it("refuses a header without Content-Length", () => {
    const read = frameReader(() => {});

    expect(() => {
      read(Buffer.from("X: 1\r\n\r\n{}"));
    }).toThrow("The frame header has no Content-Length: X: 1");
  });
});

describe("dispatch", () => {
  const handlers = {
    echo: (params: unknown) => params,
    nothing: () => undefined,
    fail: () => {
      throw new Error("broken");
    },
  };

  it("answers a request with its result, or null", async () => {
    expect(
      await dispatch(handlers, { id: 1, method: "echo", params: { a: 1 } }),
    ).toEqual({ jsonrpc: "2.0", id: 1, result: { a: 1 } });
    expect(await dispatch(handlers, { id: 2, method: "nothing" })).toEqual({
      jsonrpc: "2.0",
      id: 2,
      result: null,
    });
  });

  it("answers a failure and an unknown method with an internal error", async () => {
    expect(await dispatch(handlers, { id: 3, method: "fail" })).toEqual({
      jsonrpc: "2.0",
      id: 3,
      error: { code: -32_603, message: "broken" },
    });
    expect(await dispatch(handlers, { id: 4, method: "toString" })).toEqual({
      jsonrpc: "2.0",
      id: 4,
      error: { code: -32_603, message: "Unknown method toString" },
    });
  });

  it("doesn't answer a notification", async () => {
    expect(await dispatch(handlers, { method: "echo" })).toBeUndefined();
  });
});

describe("serve", () => {
  it("answers each framed request on the output, and ends with the input", async () => {
    const input = new PassThrough();
    const output = new PassThrough();
    let ended = false;
    const received: unknown[] = [];
    const read = frameReader((message) => received.push(message));

    output.on("data", (chunk: Buffer) => {
      read(chunk);
    });
    serve({ echo: (params) => params }, input, output, () => {
      ended = true;
    });

    input.write(
      encodeFrame({ jsonrpc: "2.0", id: "a", method: "echo", params: 1 }),
    );
    await setTimeout(10);
    input.end();
    await setTimeout(10);

    expect(received).toEqual([{ jsonrpc: "2.0", id: "a", result: 1 }]);
    expect(ended).toBe(true);
  });
});
