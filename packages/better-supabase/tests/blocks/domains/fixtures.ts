import type {
  VercelDomainsSdk,
  VercelProjectDomain,
} from "../../../src/blocks/domains/index.ts";

/** An `@vercel/sdk` `VercelError`: the status, the JSON body and headers. */
export class FakeVercelError extends Error {
  readonly statusCode: number;
  readonly body: string;
  readonly headers: Headers;

  constructor(
    statusCode: number,
    code: string,
    message: string,
    headers: Record<string, string> = {},
  ) {
    super(`API error occurred: Status ${statusCode}`);
    this.name = "SDKError";
    this.statusCode = statusCode;
    this.body = JSON.stringify({ error: { code, message } });
    this.headers = new Headers(headers);
  }
}

export const CHALLENGE = {
  type: "TXT",
  domain: "_vercel.acme.test",
  value: "vc-domain-verify=app.acme.test,abc",
  reason: "pending_domain_verification",
};

type Method = keyof VercelDomainsSdk["projects"];

export interface FakeVercel {
  readonly sdk: VercelDomainsSdk;
  /** Method, request and request options of every call. */
  readonly calls: [Method, Record<string, unknown>, unknown][];
  readonly domains: Map<string, { verified: boolean }>;
  /** Publishes Vercel's TXT challenge, so pending domains verify. */
  publish(): void;
  failWith(method: Method, error: Error): void;
}

/**
 * A Vercel project in memory. `challenge` makes added domains need Vercel's TXT
 * record until `publish()`; `elsewhere` puts hostnames on other projects.
 */
export function fakeVercel(
  options: {
    readonly projectId?: string;
    readonly challenge?: boolean;
    readonly elsewhere?: Readonly<Record<string, string>>;
  } = {},
): FakeVercel {
  const projectId = options.projectId ?? "prj_1";
  const domains = new Map<string, { verified: boolean }>();
  const calls: [Method, Record<string, unknown>, unknown][] = [];
  const failures = new Map<Method, Error>();
  let published = false;

  const domainOf = (name: string): VercelProjectDomain => {
    const found = domains.get(name);

    if (found === undefined) {
      throw new FakeVercelError(404, "not_found", `${name} is not found`);
    }

    return {
      name,
      projectId,
      verified: found.verified,
      ...(found.verified ? {} : { verification: [CHALLENGE] }),
    };
  };

  const record = (method: Method, request: object, requestOptions: unknown) => {
    calls.push([method, { ...request }, requestOptions]);
    const failure = failures.get(method);

    if (failure !== undefined) {
      throw failure;
    }
  };

  const sdk: VercelDomainsSdk = {
    projects: {
      addProjectDomain(request, requestOptions) {
        record("addProjectDomain", request, requestOptions);
        const { name } = request.requestBody;
        const other = options.elsewhere?.[name];

        if (other !== undefined) {
          return Promise.reject(
            new FakeVercelError(
              409,
              "domain_already_in_use",
              `${name} is in use by project ${other}`,
            ),
          );
        }

        if (domains.has(name)) {
          return Promise.reject(
            new FakeVercelError(
              400,
              "domain_already_exists",
              `${name} is already on this project`,
            ),
          );
        }

        domains.set(name, { verified: options.challenge !== true });

        return Promise.resolve(domainOf(name));
      },
      verifyProjectDomain(request, requestOptions) {
        record("verifyProjectDomain", request, requestOptions);
        const found = domains.get(request.domain);

        if (found === undefined) {
          return Promise.reject(
            new FakeVercelError(404, "not_found", "not found"),
          );
        }

        if (!found.verified && !published) {
          return Promise.reject(
            new FakeVercelError(
              400,
              "missing_txt_record",
              "The TXT record is missing",
            ),
          );
        }

        found.verified = true;

        return Promise.resolve({
          name: request.domain,
          projectId,
          verified: true,
        });
      },
      removeProjectDomain(request, requestOptions) {
        record("removeProjectDomain", request, requestOptions);

        if (!domains.delete(request.domain)) {
          return Promise.reject(
            new FakeVercelError(404, "not_found", "not found"),
          );
        }

        return Promise.resolve({});
      },
      getProjectDomain(request, requestOptions) {
        record("getProjectDomain", request, requestOptions);

        try {
          return Promise.resolve(domainOf(request.domain));
        } catch (cause) {
          return Promise.reject(cause);
        }
      },
    },
  };

  return {
    sdk,
    calls,
    domains,
    publish: () => {
      published = true;
    },
    failWith: (method, error) => {
      failures.set(method, error);
    },
  };
}
