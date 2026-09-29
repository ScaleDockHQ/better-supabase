import { can } from '@/features/user/user-permissions';
import { getSession } from '@/features/user/user-queries';

import { getCustomers, getStatusCounts } from '../customer-queries';
import { CreateCustomerForm } from './create-customer-form';

export async function CustomerList() {
  const [session, customers, statuses] = await Promise.all([
    getSession(),
    getCustomers(),
    getStatusCounts(),
  ]);
  return (
    <>
      <p>
        {statuses.map((group) => `${group._count} ${group.status}`).join(' · ')}
      </p>
      <ul>
        {customers.map((customer) => (
          <li key={customer.id}>
            {customer.name} <small>{customer.status}</small>{' '}
            <small>
              {customer._count.notes} notes
              {customer._max.notes.createdAt
                ? `, last ${customer._max.notes.createdAt.slice(0, 10)}`
                : ''}
            </small>
          </li>
        ))}
      </ul>
      {can(session, 'customers.write') ? (
        <CreateCustomerForm />
      ) : (
        <p>Only admins can add customers.</p>
      )}
    </>
  );
}

export function CustomerListSkeleton() {
  return (
    <ul aria-busy="true">
      {Array.from({ length: 3 }, (_, index) => (
        <li key={index} className="skeleton" />
      ))}
    </ul>
  );
}
