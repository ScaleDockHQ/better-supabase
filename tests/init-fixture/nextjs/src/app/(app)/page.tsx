import Link from 'next/link';

import { AccountMenu } from '../../features/auth/components/account-menu';

export default function HomePage() {
  return (
    <main>
      <AccountMenu />
      <Link href="/account/profile">Your account</Link>
    </main>
  );
}
