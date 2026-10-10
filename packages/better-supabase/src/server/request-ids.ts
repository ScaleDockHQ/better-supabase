import type { SessionOptions } from "../postgres/pool.ts";

export interface RequestIdOptions {
  readonly requestHeader?: string;
  readonly correlationHeader?: string;
  readonly incoming?: boolean;
  readonly generate?: boolean;
}

export interface RequestIds {
  readonly requestId?: string;
  readonly correlationId?: string;
}

export interface RequestIdPolicy {
  forRequest(request: Request | undefined, explicit: RequestIds): RequestIds;
  headers(ids: RequestIds): Readonly<Record<string, string>>;
}

const REQUEST_ID_PATTERN: RegExp = /^[A-Za-z0-9._:;,@/+=-]{1,128}$/;

function requestIdOrUndefined(
  value: string | null | undefined,
): string | undefined {
  return typeof value === "string" && REQUEST_ID_PATTERN.test(value)
    ? value
    : undefined;
}

export function sessionWith(
  ids: RequestIds,
  tenant: string | undefined,
  readOnly = false,
): SessionOptions | undefined {
  const settings = {
    ...(ids.requestId === undefined
      ? {}
      : { "better_supabase.request_id": ids.requestId }),
    ...(ids.correlationId === undefined
      ? {}
      : { "better_supabase.correlation_id": ids.correlationId }),
    ...(tenant === undefined ? {} : { "better_supabase.tenant": tenant }),
  };
  const hasSettings = Object.keys(settings).length > 0;
  if (!hasSettings && !readOnly) return undefined;
  return {
    ...(readOnly ? { readOnly: true } : {}),
    ...(hasSettings ? { settings } : {}),
  };
}

export function requestIdPolicy(
  options: RequestIdOptions | false = {},
): RequestIdPolicy {
  const on = options !== false;
  const settings = on ? options : {};
  const requestHeader = (
    settings.requestHeader ?? "x-request-id"
  ).toLowerCase();
  const correlationHeader = (
    settings.correlationHeader ?? "x-correlation-id"
  ).toLowerCase();
  const incoming = on && (settings.incoming ?? true);
  const generate = on && (settings.generate ?? true);
  const generated = new WeakMap<Request, string>();
  const fromHeader = (
    request: Request | undefined,
    name: string,
  ): string | undefined =>
    incoming && request
      ? requestIdOrUndefined(request.headers.get(name))
      : undefined;
  const generatedFor = (request: Request | undefined): string | undefined => {
    if (!generate || !request) return undefined;
    const known = generated.get(request);
    if (known !== undefined) return known;
    const id = crypto.randomUUID();
    generated.set(request, id);
    return id;
  };
  return {
    forRequest(request, explicit) {
      const requestId =
        requestIdOrUndefined(explicit.requestId) ??
        fromHeader(request, requestHeader) ??
        generatedFor(request);
      const correlationId =
        requestIdOrUndefined(explicit.correlationId) ??
        fromHeader(request, correlationHeader) ??
        requestId;
      return {
        ...(requestId === undefined ? {} : { requestId }),
        ...(correlationId === undefined ? {} : { correlationId }),
      };
    },
    headers: (ids) => ({
      ...(ids.requestId === undefined
        ? {}
        : { [requestHeader]: ids.requestId }),
      ...(ids.correlationId === undefined
        ? {}
        : { [correlationHeader]: ids.correlationId }),
    }),
  };
}
