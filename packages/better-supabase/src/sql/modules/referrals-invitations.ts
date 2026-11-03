import type { BlockSqlContext } from "../context.ts";
import type { ReferralSql } from "./referrals-sql.ts";

/** Whether `blocks.referrals.options.invitations` turns the integration on. */
export function attributesInvitations(ctx: BlockSqlContext): boolean {
  if (!ctx.flag("invitations", false)) {
    return false;
  }

  if (!ctx.installed("invitations")) {
    throw new TypeError(
      "blocks.referrals.options.invitations needs the invitations block",
    );
  }

  if (!ctx.of("invitations").has("invitations", "acceptedBy")) {
    throw new TypeError(
      "blocks.referrals.options.invitations needs the invitations acceptedBy column",
    );
  }

  return true;
}

/**
 * A trigger that attributes the referral of a code made for an invitation to
 * the user who accepts it. An invitation without a code does nothing.
 */
export function invitationReferralSql(
  ctx: BlockSqlContext,
  q: ReferralSql,
): string {
  const invitations = ctx.of("invitations");
  const i = (column: string): string => invitations.col("invitations", column);
  const fn = ctx.fn("bsb_referral_invitation");
  const trigger = ctx.naming.rename("invitations_referral");

  return `
-- Attributes the referral of an invitation's code when the invitation is
-- accepted (options.invitations): the accepting user becomes the referred
-- user. An invitation without a code, or a code that is used up, does nothing.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if new.${i("acceptedBy")} is null or old.${i("acceptedBy")} is not null then
    return null;
  end if;
  select x.${q.k("code")} into v_code from ${q.codes} x
  where x.${q.k("tenant")} = new.${i("tenant")} and x.${q.k("invitation")} = new.${i("id")};
  if v_code is null then
    return null;
  end if;
  begin
    perform ${q.fn("referral_attribute")}(new.${i("tenant")}, v_code, new.${i("acceptedBy")}, null, null);
  exception when others then
    return null;
  end;
  return null;
end;
$$;
revoke all on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${invitations.table("invitations")};
create trigger ${trigger}
after update of ${i("acceptedBy")} on ${invitations.table("invitations")}
for each row execute function ${fn}();
`;
}
