import { can } from '@/features/user/user-permissions';
import { getSession } from '@/features/user/user-queries';

import { getCustomers } from '../customer-queries';
import { CreateCustomerForm } from './create-customer-form';

export async function CustomerList() {
  const [session, customers] = await Promise.all([
    getSession(),
    getCustomers(),
  ]);
  return (
    <>
      <ul>
        {customers.map((customer) => (
          <li key={customer.id}>
            {customer.name} <small>{customer.status}</small>
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
