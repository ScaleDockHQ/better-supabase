import Image from 'next/image';

import { can } from '@/features/user/user-permissions';
import { getSession } from '@/features/user/user-queries';

import { getCustomers } from '../customer-queries';
import { CreateCustomerForm } from './create-customer-form';
import { CustomerLogoForm } from './customer-logo-form';

export async function CustomerList() {
  const [session, page] = await Promise.all([getSession(), getCustomers()]);
  const writer = can(session, 'customers.write');
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
            {customer.logoUrl ? (
              <Image src={customer.logoUrl} width={24} height={24} alt="" />
            ) : null}{' '}
            {customer.name} <small>{customer.status}</small>{' '}
            <small>
              {customer._count.notes} notes
              {customer._max.notes.createdAt
                ? `, last ${customer._max.notes.createdAt.slice(0, 10)}`
                : ''}
            </small>
            {writer ? <CustomerLogoForm customerId={customer.id} /> : null}
          </li>
        ))}
      </ul>
      {writer ? <CreateCustomerForm /> : <p>Only admins can add customers.</p>}
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
