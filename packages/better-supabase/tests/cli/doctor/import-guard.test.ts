import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import {
  IMPORT_GUARD_RULES,
  appRowTriggers,
  unguardedRowTriggers,
} from "../../../src/cli/doctor/import-guard.ts";

const file = (text: string, path = "supabase/schemas/public/orders.sql") => ({
  path,
  text,
});

const UNGUARDED = file(`
create function public.notify_order() returns trigger language plpgsql as $$
begin
  perform pg_notify('orders', new.id::text);
  return new;
end;
$$;
create trigger notify_order after insert on public.orders
  for each row execute function public.notify_order();
`);

const GUARDED = file(`
create function public.notify_order() returns trigger language plpgsql as $fn$
begin
  if better_supabase.importing() then
    return new;
  end if;
  return new;
end;
$fn$;
create trigger notify_order after insert on public.orders
  for each row execute function public.notify_order();
`);

describe("appRowTriggers", () => {
  it("skips statement triggers and bsb_ triggers", () => {
    const found = appRowTriggers([
      file(`
create trigger a after insert on public.t for each statement execute function public.f();
create trigger bsb_audit after insert on public.t for each row execute function public.f();
create trigger b after update on public.t for each row execute function public.f();
`),
    ]);

    expect(found.map((trigger) => trigger.name)).toEqual(["b"]);
  });
});

describe("unguardedRowTriggers", () => {
  it("reports a row trigger whose function ignores imports", () => {
    expect(unguardedRowTriggers([UNGUARDED]).map((t) => t.fn)).toEqual([
      "notify_order",
    ]);
  });

  it("accepts a function that calls importing()", () => {
    expect(unguardedRowTriggers([GUARDED])).toEqual([]);
  });

  it("does not judge a function outside the schema files", () => {
    expect(
      unguardedRowTriggers([
        file(
          "create trigger t after insert on public.t for each row execute function ext.f();",
        ),
      ]),
    ).toEqual([]);
  });
});

describe("BS633", () => {
  it("reads schema files and skips migrations", async () => {
    const rule = IMPORT_GUARD_RULES[0];

    const context = {
      sqlFiles: [
        UNGUARDED,
        file(UNGUARDED.text, "supabase/migrations/1_orders.sql"),
      ],
      // SAFETY: the rule reads only sqlFiles.
    } as unknown as DoctorContext;

    const findings = await rule?.check(context);

    expect(findings).toHaveLength(1);
    expect(findings?.[0]?.target).toBe("public.orders.notify_order");
  });
});
