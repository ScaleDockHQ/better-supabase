import { can } from '@/features/user/user-permissions';
import { getSession } from '@/features/user/user-queries';

import { getCustomers } from '../customer-queries';
import { CreateCustomerForm } from './create-customer-form';

export async function CustomerList() {
  const [session, page] = await Promise.all([getSession(), getCustomers()]);
  return (
    <>
      <p data-testid="status-facets">
        {Object.entries(page.facetCounts.status)
          .map(([status, count]) => `${count} ${status}`)
          .join(' · ')}
      </p>
      <ul>
        {page.items.map((customer) => (
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
