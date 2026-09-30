import { rolesOf } from '../user-permissions';
import { getSession } from '../user-queries';

export async function ProfileDetails() {
  const session = await getSession();
  if (session.kind !== 'user') return <p>Not signed in.</p>;
  return (
    <dl>
      <dt>Name</dt>
      <dd>{session.profile?.display_name ?? 'not set'}</dd>
      <dt>Email</dt>
      <dd>{session.user.email}</dd>
      <dt>Roles</dt>
      <dd>{rolesOf(session.claims).join(', ') || 'none'}</dd>
      <dt>Token expires</dt>
      <dd>
        {session.expiresAt === null
          ? 'unknown'
          : new Date(session.expiresAt * 1000).toISOString()}
      </dd>
    </dl>
  );
}

export function ProfileDetailsSkeleton() {
  return <dl className="skeleton" aria-busy="true" />;
}
