import { describe, expect, it } from "vitest";

import { pollingStreamReader } from "../../../src/workflow-sdk/world/polling.ts";

interface Row {
  id: string;
  data: Buffer;
  eof: boolean;
}

function chunk(id: number, text: string, eof = false): Row {
  return {
    id: `chnk_${String(id).padStart(4, "0")}`,
    data: Buffer.from(text),
    eof,
  };
}

/** A pool over an array of rows that mimics `id > $2 order by id`. */
function fakePool(rows: Row[]) {
  return {
    query: async (_text: string, params: unknown[] = []) => ({
      rows: rows.filter((row) => row.id > String(params[1])),
    }),
  };
}

async function readAll(stream: ReadableStream<Uint8Array>): Promise<string> {
  const decoder = new TextDecoder();
  let out = "";

  for await (const part of stream) {
    out += decoder.decode(part);
  }

  return out;
}

describe("pollingStreamReader", () => {
  it("reads the stored chunks up to the eof chunk", async () => {
    const rows = [chunk(1, "a"), chunk(2, "b"), chunk(3, "", true)];
    const { get } = pollingStreamReader(fakePool(rows), 5);

    expect(await readAll(get("s"))).toBe("ab");
  });

  it("skips a start index of data chunks and counts back from the end", async () => {
    const rows = [
      chunk(1, "a"),
      chunk(2, "b"),
      chunk(3, "c"),
      chunk(4, "", true),
    ];

    const { get } = pollingStreamReader(fakePool(rows), 5);

    expect(await readAll(get("s", 1))).toBe("bc");
    expect(await readAll(get("s", -1))).toBe("c");
    expect(await readAll(get("s", 9))).toBe("");
  });

  it("follows a stream that is still being written", async () => {
    const rows = [chunk(1, "a")];
    const { get } = pollingStreamReader(fakePool(rows), 5);
    const done = readAll(get("s"));

    setTimeout(() => rows.push(chunk(2, "b")), 20);
    setTimeout(() => rows.push(chunk(3, "c", true)), 40);

    expect(await done).toBe("abc");
  });

  it("errors a waiting read when the World closes", async () => {
    const reader = pollingStreamReader(fakePool([chunk(1, "a")]), 5);
    const pending = readAll(reader.get("s"));

    setTimeout(() => {
      reader.close();
    }, 20);

    await expect(pending).rejects.toThrow("closed");
  });

  it("stops polling when the consumer cancels", async () => {
    let reads = 0;

    const pool = {
      query: async () => {
        reads += 1;

        return { rows: [] };
      },
    };

    const stream = pollingStreamReader(pool, 5).get("s");
    await stream.cancel();
    const seen = reads;
    await new Promise<void>((resolve) => {
      setTimeout(resolve, 30);
    });

    expect(reads).toBe(seen);
  });
});
