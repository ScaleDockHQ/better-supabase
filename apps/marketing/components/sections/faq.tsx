'use client';

import { Section } from '@/components/sections/section';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { faq } from '@/lib/home';

export function FaqSection() {
  return (
    <Section id="faq" eyebrow="FAQ" title="Questions">
      <Accordion className="max-w-3xl">
        {faq.map((item) => (
          <AccordionItem key={item.question} value={item.question}>
            <AccordionTrigger>{item.question}</AccordionTrigger>
            <AccordionContent>
              <p className="text-muted-foreground leading-6">{item.answer}</p>
            </AccordionContent>
          </AccordionItem>
        ))}
      </Accordion>
    </Section>
  );
}
