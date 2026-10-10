import { type CsvOptions, toCsv } from "../blocks/csv.ts";

export interface CsvResponseOptions extends CsvOptions {
  /** The download name, such as `invoices.csv`. */
  readonly filename: string;
  /** Extra headers, such as `cache-control`. `content-type` and `content-disposition` win. */
  readonly headers?: ConstructorParameters<typeof Headers>[0];
  readonly status?: number;
}

function disposition(filename: string): string {
  const safe = filename.replaceAll(/[\r\n]/g, " ");
  const ascii = safe.replaceAll(/[^\u0020-\u007E]|["\\]/g, "_");
  const encoded = encodeURIComponent(safe).replaceAll(
    /['()*]/g,
    (char) => `%${char.codePointAt(0)!.toString(16).toUpperCase()}`,
  );
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encoded}`;
}

/**
 * `rows` as a CSV download: `text/csv; charset=utf-8` with an `attachment`
 * `Content-Disposition`. Text cells that start with a formula character are
 * escaped unless `escapeFormulas` is false.
 */
export function csvResponse(
  rows: readonly Readonly<Record<string, unknown>>[],
  options: CsvResponseOptions,
): Response {
  const { filename, headers, status, ...csv } = options;
  const response = new Response(toCsv(rows, csv), {
    status: status ?? 200,
    ...(headers ? { headers } : {}),
  });
  response.headers.set("content-type", "text/csv; charset=utf-8");
  response.headers.set("content-disposition", disposition(filename));
  return response;
}
