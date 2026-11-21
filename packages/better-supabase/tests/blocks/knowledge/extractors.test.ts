import { describe, expect, it, vi } from "vitest";

import {
  DOCX_TYPE,
  PDF_TYPE,
  chunk,
  docxExtractor,
  extractors,
  pdfExtractor,
} from "../../../src/blocks/knowledge/index.ts";

const bytes = (text: string) => new TextEncoder().encode(text);

describe("extractors", () => {
  it("joins PDF pages with form feeds and loads the library once", async () => {
    const load = vi.fn(() =>
      Promise.resolve({
        extractText: () => Promise.resolve({ text: ["page one", "page two"] }),
      }),
    );

    const extract = pdfExtractor({ load });
    const file = { mediaType: PDF_TYPE };

    expect(load).not.toHaveBeenCalled();

    const text = await extract(file, bytes("%PDF"));
    await extract(file, bytes("%PDF"));

    expect(text).toBe("page one\fpage two");
    expect(load).toHaveBeenCalledOnce();
    expect(chunk(text, { size: 10, overlap: 0 }).at(-1)?.position?.page).toBe(
      2,
    );
  });

  it("retries a failed load on the next file", async () => {
    const load = vi
      .fn()
      .mockRejectedValueOnce(new Error("not installed"))
      .mockResolvedValue({
        extractRawText: () => Promise.resolve({ value: "hello" }),
      });

    const extract = docxExtractor({ load });
    const file = { mediaType: DOCX_TYPE };

    await expect(extract(file, bytes("x"))).rejects.toThrow("not installed");
    expect(await extract(file, bytes("x"))).toBe("hello");
  });

  it("picks by media type and falls back to text", async () => {
    const pdf = vi.fn(() => Promise.resolve("from pdf"));
    const extract = extractors({ [PDF_TYPE]: pdf });

    expect(
      await extract({ mediaType: "Application/PDF; x=1" }, bytes("")),
    ).toBe("from pdf");
    expect(await extract({ mediaType: "text/plain" }, bytes("plain"))).toBe(
      "plain",
    );
    await expect(
      extract({ mediaType: "image/png" }, bytes("")),
    ).rejects.toThrow(/No text extractor/);
  });
});
