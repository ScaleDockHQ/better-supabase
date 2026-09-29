import { Suspense } from 'react';

import {
  CustomerList,
  CustomerListSkeleton,
} from '@/features/customers/components/customer-list';
import {
  SimilarNotes,
  SimilarNotesSkeleton,
} from '@/features/notes/components/similar-notes';
import { PermissionGate } from '@/features/user/components/permission-gate';

export const instant = true;

export default function CustomersPage() {
  return (
    <>
      <h1>Customers</h1>
      <Suspense fallback={<CustomerListSkeleton />}>
        <PermissionGate permission="customers.read">
          <CustomerList />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<SimilarNotesSkeleton />}>
        <PermissionGate permission="customers.read">
          <SimilarNotes />
        </PermissionGate>
      </Suspense>
    </>
  );
}
