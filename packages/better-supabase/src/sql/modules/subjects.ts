import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  SERVICE_CALLER,
  schemaPreamble,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import {
  type RegisteredSubject,
  registeredIdMatches,
  registeredSubjects,
  urlExpression,
} from "../subject-registry.ts";

const NAMES: ModuleNames = { tables: {} };

/**
 * The permission check for `action` on row `s`, `true` when the action has no
 * key.
 */
function actionCheck(ctx: ModuleContext, subject: RegisteredSubject): string {
  const permissions = Object.entries(subject.config.permissions ?? {});

  if (permissions.length === 0) {
    return "true";
  }

  const scope = subject.config.scope;

  const held = (key: string): string => {
    const parts = [
      ...(subject.tenant === undefined
        ? []
        : [ctx.can("tenant", `s.${subject.tenant}`, sqlString(key))]),
      ...(scope === undefined
        ? []
        : [ctx.can(scope, `s.${subject.id}::text`, sqlString(key))]),
    ];

    return parts.length === 1 ? parts[0]! : `(${parts.join(" or ")})`;
  };

  return `(${SERVICE_CALLER} or case can_subject.action\n${permissions
    .map(
      ([action, key]) =>
        `          when ${sqlString(action)} then ${held(key)}`,
    )
    .join("\n")}\n          else true\n        end)`;
}

/**
 * `user` holds the key for `action` on row `s`, through `can_user`. An action
 * without a key is false: nothing but the row's policies would decide it, and
 * they answer for the caller only.
 */
function actionCheckFor(subject: RegisteredSubject, user: string): string {
  const permissions = Object.entries(subject.config.permissions ?? {});

  if (permissions.length === 0) {
    return "false";
  }

  const scope = subject.config.scope;

  const held = (key: string): string => {
    const userCan = (scopeName: string, id: string): string =>
      `coalesce(better_supabase.can_user(${user}, ${sqlString(scopeName)}, ${id}, ${sqlString(key)}), false)`;

    const parts = [
      ...(subject.tenant === undefined
        ? []
        : [userCan("tenant", `s.${subject.tenant}`)]),
      ...(scope === undefined ? [] : [userCan(scope, `s.${subject.id}::text`)]),
    ];

    return parts.length === 1 ? parts[0]! : `(${parts.join(" or ")})`;
  };

  return `case can_subject_for.action\n${permissions
    .map(
      ([action, key]) =>
        `          when ${sqlString(action)} then ${held(key)}`,
    )
    .join("\n")}\n          else false\n        end`;
}

/** The row `s` is `id` and, with `deletedAt`, not soft-deleted. */
function rowMatches(subject: RegisteredSubject, id: string): string {
  const match = registeredIdMatches(subject, id);

  return subject.config.deletedAt === undefined
    ? match
    : `${match} and s.${sqlIdent(subject.config.deletedAt)} is null`;
}

function cases(
  subjects: readonly RegisteredSubject[],
  branch: (subject: RegisteredSubject) => string | undefined,
): string {
  const whens = subjects.flatMap((subject) => {
    const body = branch(subject);

    return body === undefined
      ? []
      : [`    when ${sqlString(subject.type)} then\n      ${body}`];
  });

  return whens.length === 0 ? "    when '' then null;" : whens.join("\n");
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const subjects = registeredSubjects(ctx.subjects, ctx.naming);
  const fn = (name: string): string => ctx.fn(name);

  return `${schemaPreamble(ctx)}
-- The app's subject registry (config.subjects, ADR 0020). Each function runs
-- as the caller, so the subject table's own policies decide what is visible.
create or replace function ${fn("subject_types")}()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select ${sqlString(`{${subjects.map((subject) => subject.type).join(",")}}`)}::text[]
$$;
${userGrant(`${fn("subject_types")}()`)}

create or replace function ${fn("subject_title")}(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_title.subject_type
${cases(subjects, (subject) =>
  subject.config.title === undefined
    ? undefined
    : `return (select s.${sqlIdent(subject.config.title)}::text from ${subject.qualified} s where ${rowMatches(subject, "subject_title.subject_id")});`,
)}
    else
      return null;
  end case;
  return null;
end;
$$;
${userGrant(`${fn("subject_title")}(text, text)`)}

create or replace function ${fn("subject_url")}(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_url.subject_type
${cases(subjects, (subject) =>
  subject.config.url === undefined
    ? undefined
    : `return (select ${urlExpression(subject.config.url)} from ${subject.qualified} s where ${rowMatches(subject, "subject_url.subject_id")});`,
)}
    else
      return null;
  end case;
  return null;
end;
$$;
${userGrant(`${fn("subject_url")}(text, text)`)}

-- True when the caller can see the subject row and, for an action with a
-- key in config.subjects.<type>.permissions, holds that key in the
-- subject's tenant (or on the record, through the subject's scope).
create or replace function ${fn("can_subject")}(subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case can_subject.subject_type
${cases(
  subjects,
  (subject) =>
    `return exists (
        select 1 from ${subject.qualified} s
        where ${rowMatches(subject, "can_subject.subject_id")}
          and ${actionCheck(ctx, subject)}
      );`,
)}
    else
      return false;
  end case;
  return false;
end;
$$;
${userGrant(`${fn("can_subject")}(text, text, text)`)}

-- can_subject for another user, for server code that decides who receives
-- an event. It reads the row past its policies and asks can_user for the
-- action's key in config.subjects.<type>.permissions, so an action without
-- a key is false and a share-link grant never counts. A provider that
-- can't answer for others (no idsWithFor) gives false.
create or replace function ${fn("can_subject_for")}(member uuid, subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case can_subject_for.subject_type
${cases(
  subjects,
  (subject) =>
    `return exists (
        select 1 from ${subject.qualified} s
        where ${rowMatches(subject, "can_subject_for.subject_id")}
          and ${actionCheckFor(subject, "can_subject_for.member")}
      );`,
)}
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$$;
${serviceGrant(`${fn("can_subject_for")}(uuid, text, text, text)`)}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "subject_types", args: [], returns: "text[]" },
    { name: "subject_title", args: ["text", "text"], returns: "text" },
    { name: "subject_url", args: ["text", "text"], returns: "text" },
    { name: "can_subject", args: ["text", "text", "text"], returns: "boolean" },
    {
      name: "can_subject_for",
      args: ["uuid", "text", "text", "text"],
      returns: "boolean",
    },
  ];
}

export const SUBJECTS: ModuleDefinition = {
  name: "subjects",
  scopes: ["tenant"],
  title: "Subjects",
  description:
    "The app-wide subject registry from config.subjects: subject_title, subject_url, can_subject and can_subject_for for every registered type.",
  requires: ["access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
