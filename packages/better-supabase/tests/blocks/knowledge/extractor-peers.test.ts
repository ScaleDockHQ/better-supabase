import { crc32 } from "node:zlib";
import { describe, expect, it } from "vitest";

import type {
  DocxModule,
  PdfModule,
} from "../../../src/blocks/knowledge/index.ts";

import {
  DOCX_TYPE,
  PDF_TYPE,
  docxExtractor,
  pdfExtractor,
} from "../../../src/blocks/knowledge/index.ts";

const encoder = new TextEncoder();

/**
 * A one-page PDF with a text line, built by hand. pdf.js rebuilds the xref
 * table.
 */
function pdf(line: string): Uint8Array {
  const stream = `BT /F1 18 Tf 20 100 Td (${line}) Tj ET`;

  return encoder.encode(
    [
      "%PDF-1.4",
      "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj",
      "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj",
      "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj",
      `4 0 obj<</Length ${String(stream.length)}>>stream\n${stream}\nendstream endobj`,
      "5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj",
      "trailer<</Root 1 0 R/Size 6>>",
      "%%EOF",
    ].join("\n"),
  );
}

/** A zip that stores its entries uncompressed. */
function zip(entries: Readonly<Record<string, string>>): Uint8Array {
  const parts: number[] = [];
  const central: number[] = [];

  const u16 = (value: number) => [value % 256, Math.floor(value / 256) % 256];

  const u32 = (value: number) => [
    ...u16(value % 65_536),
    ...u16(Math.floor(value / 65_536)),
  ];

  for (const [name, content] of Object.entries(entries)) {
    const data = encoder.encode(content);
    const label = encoder.encode(name);
    const offset = parts.length;
    const checksum = crc32(data);

    const common = [
      ...u16(20),
      ...u16(0),
      ...u16(0),
      ...u16(0),
      ...u16(0x21),
      ...u32(checksum),
      ...u32(data.length),
      ...u32(data.length),
      ...u16(label.length),
      ...u16(0),
    ];

    parts.push(0x50, 0x4b, 3, 4, ...common, ...label, ...data);
    central.push(
      0x50,
      0x4b,
      1,
      2,
      ...u16(20),
      ...common,
      ...u16(0),
      ...u16(0),
      ...u16(0),
      ...u32(0),
      ...u32(offset),
      ...label,
    );
  }

  const count = Object.keys(entries).length;

  return Uint8Array.from([
    ...parts,
    ...central,
    0x50,
    0x4b,
    5,
    6,
    ...u16(0),
    ...u16(0),
    ...u16(count),
    ...u16(count),
    ...u32(central.length),
    ...u32(parts.length),
    ...u16(0),
  ]);
}

const docx = (text: string): Uint8Array =>
  zip({
    "[Content_Types].xml":
      '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
    "_rels/.rels":
      '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    "word/document.xml": `<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>${text}</w:t></w:r></w:p></w:body></w:document>`,
  });

describe("the optional peers unpdf and mammoth", () => {
  it("fit the structural module types", async () => {
    const pdfModule: PdfModule = await import("unpdf");
    const docxModule: DocxModule = await import("mammoth");

    expect(typeof pdfModule.extractText).toBe("function");
    expect(typeof docxModule.extractRawText).toBe("function");
  });

  it("reads a PDF through the default lazy load", async () => {
    const text = await pdfExtractor()(
      { mediaType: PDF_TYPE },
      pdf("Quarterly numbers"),
    );

    expect(text).toContain("Quarterly numbers");
  });

  it("reads a DOCX through the default lazy load", async () => {
    const text = await docxExtractor()(
      { mediaType: DOCX_TYPE },
      docx("Meeting notes"),
    );

    expect(text.trim()).toBe("Meeting notes");
  });

  it("reads both through an explicit load", async () => {
    expect(
      await pdfExtractor({ load: () => import("unpdf") })(
        { mediaType: PDF_TYPE },
        pdf("Explicit"),
      ),
    ).toContain("Explicit");
    expect(
      (
        await docxExtractor({ load: () => import("mammoth") })(
          { mediaType: DOCX_TYPE },
          docx("Explicit"),
        )
      ).trim(),
    ).toBe("Explicit");
  });
});
