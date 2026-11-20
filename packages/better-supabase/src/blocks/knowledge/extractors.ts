import { textExtract } from "./knowledge.ts";

/** The part of a file an extractor looks at. An `AiFile` fits. */
export interface ExtractorFile {
  readonly mediaType: string;
}

/** `createKnowledge({ extract })`: the text of a file's bytes. */
export type KnowledgeExtractor = (
  file: ExtractorFile,
  data: Uint8Array,
) => Promise<string>;

/**
 * The part of `unpdf` that `pdfExtractor` uses. Any module with this
 * `extractText` fits, so better-supabase lists no PDF library as a dependency.
 */
export interface PdfModule {
  extractText(
    data: Uint8Array,
    options: { readonly mergePages: false },
  ): Promise<{ readonly text: readonly string[] }>;
}

/** The part of `mammoth` that `docxExtractor` uses. */
export interface DocxModule {
  extractRawText(input: {
    readonly arrayBuffer: ArrayBuffer;
  }): Promise<{ readonly value: string }>;
}

export const PDF_TYPE = "application/pdf";

export const DOCX_TYPE =
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

/** A form feed, which `chunk()` reads as a page break to fill `position.page`. */
const PAGE_BREAK = "\f";

/**
 * Calls `load` on the first use only, so the library is not imported until a
 * file needs it.
 */
function once<T>(load: () => Promise<T>): () => Promise<T> {
  let loaded: Promise<T> | undefined;

  return () => {
    loaded ??= load().catch((cause: unknown) => {
      loaded = undefined;
      throw cause;
    });

    return loaded;
  };
}

/**
 * Extracts the text of PDF files, one form feed between pages so chunks get a
 * `position.page`. `load` returns the PDF library; it runs on the first PDF:
 *
 * ```ts
 * pdfExtractor({ load: () => import("unpdf") });
 * ```
 */
export function pdfExtractor(options: {
  readonly load: () => Promise<PdfModule>;
}): KnowledgeExtractor {
  const library = once(options.load);

  return async (_file, data) => {
    const pdf = await library();
    const { text } = await pdf.extractText(data, { mergePages: false });

    return text.join(PAGE_BREAK);
  };
}

/**
 * Extracts the text of `.docx` files. `load` returns the library and runs on
 * the first file:
 *
 * ```ts
 * docxExtractor({ load: () => import("mammoth") });
 * ```
 */
export function docxExtractor(options: {
  readonly load: () => Promise<DocxModule>;
}): KnowledgeExtractor {
  const library = once(options.load);

  return async (_file, data) => {
    const docx = await library();

    const arrayBuffer = new ArrayBuffer(data.byteLength);

    new Uint8Array(arrayBuffer).set(data);

    const { value } = await docx.extractRawText({ arrayBuffer });

    return value;
  };
}

const withoutParameters = (mediaType: string): string =>
  (mediaType.split(";")[0] ?? "").trim().toLowerCase();

/**
 * Picks an extractor by media type (parameters such as `charset` ignored) and
 * falls back to `fallback`, which decodes text, JSON, XML and YAML by default.
 *
 * ```ts
 * createKnowledge({
 *   extract: extractors({
 *     [PDF_TYPE]: pdfExtractor({ load: () => import("unpdf") }),
 *     [DOCX_TYPE]: docxExtractor({ load: () => import("mammoth") }),
 *   }),
 * });
 * ```
 */
export function extractors(
  byType: Readonly<Record<string, KnowledgeExtractor>>,
  fallback: KnowledgeExtractor = textExtract,
): KnowledgeExtractor {
  const table = new Map(
    Object.entries(byType).map(([type, extractor]) => [
      type.toLowerCase(),
      extractor,
    ]),
  );

  return (file, data) =>
    (table.get(withoutParameters(file.mediaType)) ?? fallback)(file, data);
}
