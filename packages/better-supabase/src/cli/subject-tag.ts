import type { SubjectConfig } from "../config/index.ts";
import type { BsbTag } from "../sql/index.ts";

type Args = BsbTag["args"];

const PERMISSION_PREFIX = "can-";

function text(value: string | true | undefined): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function columns(value: string | true | undefined): string[] {
  return typeof value === "string"
    ? value
        .split(",")
        .map((item) => item.trim())
        .filter((item) => item !== "")
    : [];
}

/**
 * The `subject` entry a tag stands for. `table` is the tagged table. Options
 * the tag has no word for (`search.from`, `search.watch`, row grants) stay in
 * `subjects`.
 */
export function subjectFromTag(args: Args, table: string): SubjectConfig {
  const tenant = text(args["tenant"]);
  const searchTitle = text(args["search-title"]);
  const searchBody = columns(args["search-body"]);
  const description = text(args["search-description"]);
  const exclude = text(args["search-exclude"]);
  const versions = columns(args["versions"]);
  const rank = text(args["rank"]);

  const permissions = Object.fromEntries(
    Object.entries(args).flatMap(([key, value]) =>
      key.startsWith(PERMISSION_PREFIX) && typeof value === "string"
        ? [[key.slice(PERMISSION_PREFIX.length), value]]
        : [],
    ),
  );

  const search =
    searchTitle !== undefined ||
    searchBody.length > 0 ||
    description !== undefined ||
    exclude !== undefined ||
    args["search"] === true;

  const id = text(args["id"]);
  const idType = text(args["id-type"]);
  const title = text(args["title"]);
  const url = text(args["url"]);
  const scope = text(args["scope"]);
  const deletedAt = text(args["deleted-at"]);
  const rankGroup = text(args["rank-group"]);

  return {
    table,
    ...(id === undefined ? {} : { id }),
    ...(idType === undefined ? {} : { idType }),
    ...(tenant === undefined
      ? {}
      : { tenant: tenant === "false" ? false : tenant }),
    ...(title === undefined ? {} : { title }),
    ...(url === undefined ? {} : { url }),
    ...(scope === undefined ? {} : { scope }),
    ...(args["cascade"] === true ? { cascade: true } : {}),
    ...(deletedAt === undefined ? {} : { deletedAt }),
    ...(Object.keys(permissions).length === 0 ? {} : { permissions }),
    ...(search
      ? {
          search: {
            ...(searchTitle === undefined ? {} : { title: searchTitle }),
            ...(searchBody.length === 0 ? {} : { body: searchBody }),
            ...(description === undefined ? {} : { description }),
            ...(exclude === undefined ? {} : { exclude }),
          },
        }
      : {}),
    ...(rank === undefined && rankGroup === undefined
      ? {}
      : {
          rank: {
            column: rank ?? "rank",
            ...(rankGroup === undefined ? {} : { group: rankGroup }),
          },
        }),
    ...(versions.length === 0
      ? {}
      : {
          versions: {
            columns: versions,
            auto: args["versions-auto"] !== "false",
          },
        }),
  };
}

/**
 * The tag arguments for `subject`, or `undefined` when the entry holds an
 * option a tag can't carry, so it stays in `subjects`.
 */
export function subjectTagArgs(
  type: string,
  subject: SubjectConfig,
  table: string,
): Record<string, string | true> | undefined {
  const permissions = Object.entries(subject.permissions ?? {});

  if (
    permissions.some(([, value]) => typeof value !== "string") ||
    subject.search?.from !== undefined ||
    subject.search?.watch !== undefined
  ) {
    return undefined;
  }

  const args: Record<string, string | true> = {};

  const set = (key: string, value: string | true | undefined): void => {
    if (value !== undefined) {
      args[key] = value;
    }
  };

  set("type", type === table ? undefined : type);
  set("id", subject.id);
  set("id-type", subject.idType);
  set("tenant", subject.tenant === false ? "false" : subject.tenant);
  set("title", subject.title);
  set("url", subject.url);
  set("scope", subject.scope);
  set("cascade", subject.cascade === true ? true : undefined);
  set("deleted-at", subject.deletedAt);
  set("search-title", subject.search?.title);
  set(
    "search-body",
    subject.search?.body === undefined
      ? undefined
      : subject.search.body.join(","),
  );
  set("search-description", subject.search?.description);
  set("search-exclude", subject.search?.exclude);
  set(
    "search",
    subject.search !== undefined &&
      Object.keys(args).every((key) => !key.startsWith("search-"))
      ? true
      : undefined,
  );
  set("rank", subject.rank?.column);
  set("rank-group", subject.rank?.group);

  if (subject.versions !== undefined) {
    set("versions", subject.versions.columns.join(","));
    set("versions-auto", subject.versions.auto ? undefined : "false");
  }

  for (const [action, key] of permissions) {
    set(
      `${PERMISSION_PREFIX}${action}`,
      typeof key === "string" ? key : undefined,
    );
  }

  return args;
}
