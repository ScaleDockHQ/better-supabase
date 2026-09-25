import { Suspense } from 'react';

import {
  CustomerList,
  CustomerListSkeleton,
} from '@/features/customers/components/customer-list';
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
    </>
  );
}
