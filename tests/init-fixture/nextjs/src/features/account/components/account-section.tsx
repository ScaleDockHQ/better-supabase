import { getUser } from '../../auth/auth-queries';
import { getAccountSection } from '../account-queries';

export async function AccountSection({ section }: { section: string }) {
  const user = await getUser();
  const account = user ? await getAccountSection(user.id, section) : null;

  return (
    <section>
      <h1>{account?.section}</h1>
      <p>{account?.email}</p>
    </section>
  );
}

export function AccountSectionSkeleton() {
  return <section aria-busy="true" />;
}
