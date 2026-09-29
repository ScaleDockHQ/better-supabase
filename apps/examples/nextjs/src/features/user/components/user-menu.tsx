import Link from 'next/link';

import { rolesOf } from '../user-permissions';
import { getSession } from '../user-queries';
import { SignOutButton } from './sign-out-button';

export async function UserMenu() {
  const session = await getSession();
  if (session.kind !== 'user') return <Link href="/login">Sign in</Link>;
  const roles = rolesOf(session.claims);
  return (
    <div className="user-menu">
      {session.impersonator ? (
        <strong role="status">
          Support session by {session.impersonator.id}
          {session.impersonator.reason
            ? ` (${session.impersonator.reason})`
            : ''}
        </strong>
      ) : null}
      <span>{session.user.email}</span>
      <small data-testid="role">
        {roles.length > 0 ? roles.join(', ') : 'no role'}
      </small>
      <SignOutButton />
    </div>
  );
}

export function UserMenuSkeleton() {
  return <div className="user-menu skeleton" aria-busy="true" />;
}
