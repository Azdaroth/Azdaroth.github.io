---
layout: post
title: "From collecting payments to distributing revenue: the FinTech system behind Smily"
date: 2026-09-15 10:00
comments: true
categories: [Architecture, Distributed Systems]
canonical_url: https://www.smily.com/engineering/from-collecting-payments-to-distributing-revenue-the-fintech-system-behind-smily
---

Collecting a payment sounds like a reasonably well-defined problem. A traveler pays for a booking, the payment succeeds, and the property manager receives the money.

Except that the property manager might only be entitled to part of it. The rest belongs to the owner. A booking channel might have already deducted its commission and collected a tax. The booking might include Travelers’ Fees or Cancellation Protection. And the bank transfer might cover twenty bookings, an adjustment to an older reservation, and a deduction that has nothing to do with any of them.

Suddenly, “the payment succeeded” tells us surprisingly little about what should happen next.

At Smily, we built the system that connects these steps: collecting money, understanding what it belongs to, distributing it between the right parties, collecting the applicable fees, and explaining the resulting bank payout.

Here is how the pieces fit together, and why the interesting engineering starts well before the money reaches someone’s bank account.

*I originally published this article on the [Smily Engineering Blog](https://www.smily.com/engineering/from-collecting-payments-to-distributing-revenue-the-fintech-system-behind-smily).*

<!--more-->

## Why build this inside a property management system?

Every gap between collecting a payment and explaining a payout creates work for someone. If the software stops at collection, the property manager still has to calculate the owner’s share, account for channel deductions, recover fees and assemble the records for their accountant.

The PMS already holds much of the context needed to do that work: the reservation, the rental, the parties involved and their commercial agreement. Connecting that context to the money lets us automate more of the customer’s financial workflow.

It also gives Smily a way to earn revenue from the services used on a booking. Payment processing, Travelers’ Fees, Split Payments and Cancellation Protection each contribute through their applicable fees. Extending this system makes another financial product possible without rebuilding collection, distribution and reporting from scratch.

For a small team, that reuse matters. We wanted each piece of infrastructure to support several products and carry them all the way through to the bank payout and accounting export.

## SmilyPay: the starting point

We started with card payments. SmilyPay let property managers collect payments, distribute the proceeds and generate financial reports within the same system.

Payment processing also gives us a revenue stream through the applicable processing fees. But it is only one way money enters the system. For many reservations, the channel collects the traveler’s payment and later sends a bank transfer to the IBAN configured on that channel.

When those transfers went directly to the property manager’s or owner’s bank account, the funds bypassed SmilyPay. We could not distribute that money or provide the same end-to-end financial reporting. Customers were left doing that work themselves.

Virtual IBANs gave us a way to bring those channel payouts into the same flow: receive the funds through SmilyPay, apply the booking’s distribution rules and send each party their share. Collecting our applicable fees from the incoming funds also avoids a separate card charge and its processing cost.

## A virtual IBAN brings channel payouts into the flow

Completing SmilyPay enrollment automatically starts virtual IBAN creation. We associate that IBAN with the relevant payment gateway and account, and it can then be configured as the payout destination on a supported channel.

The channel sends a bank transfer to that IBAN. The funds arrive in our SmilyPay collection wallet. The IBAN gives us the receiving context. To understand what the money represents, our channel applications retrieve payout details through the channels’ APIs or other available formats and normalize them into a common breakdown. That breakdown is the channel payout data used in the diagram below.

![Channel payouts: enrollment, virtual IBAN, reconciliation, wallet transfers and bank payouts](https://cdn.prod.website-files.com/5e71e686d09a97adb643219b/6aa929d77bff8b1eb71ebca2_channel-payouts.png)

*Channel payouts: enrollment, virtual IBAN, reconciliation, wallet transfers and bank payouts*

*Read from top to bottom: enrollment and virtual IBAN configuration precede the payment flow shown here. Arrows indicate workflow order. Smily performs reconciliation; SmilyPay executes the wallet transfers and bank payouts. Product eligibility and configuration determine the actual distribution.*

This gives us an important connection: channel-collected money can enter a flow that also supports Travelers’ Fees, Cancellation Protection and Split Payments. We can apply the booking’s financial rules when those funds are reconciled.

The virtual IBAN is the entry point. The reconciliation behind it does the rest.

## Reconciliation: what did we receive, and who should receive it next?

Consider a channel transfer covering several bookings. Its amount may already reflect channel commissions, withheld taxes, refunds or adjustments. One reservation can also produce multiple money movements over time.

Treating that transfer as one payment against one booking would lose information almost immediately.

The channel data and the money reach us through different paths. Each channel supplies payout details in its own format. Our channel applications process those differences and publish a normalized payout event carrying the reference, amount, currency and breakdown. The consumer application can then work with the same structure regardless of which supported channel supplied the data. It stores the booking-level and account-level movements and calculates the applicable distributions. Separately, a payment notification tells us that the bank wire has arrived.

Reconciliation joins those two inputs. The report describes what the channel intends to settle; the wire provides the funds with which to settle it. Having one does not mean we have the other.

They can also arrive in the wrong order. If a wire arrives before the channel application has published the report, the initial attempt cannot match it. A periodic recovery job revisits pending payouts and attempts the match again. When it finds multiple candidate wires for one reference, it reports the ambiguity instead of choosing one.

Before distributing the wire, the reconciliation checks its reference and amount against the stored payout. It also checks that the receiving IBAN and the bookings belong to the appropriate account. The transfer plan must account for the received amount.

From there, Smily creates the applicable transfers to the property manager’s wallet, the owner’s wallet, and the fee destinations. These movements retain their links to the booking and channel payout.

That last part is easy to underestimate. A transfer without its business context might move the right amount today, but it makes tomorrow’s accounting question much harder to answer.

![One channel payout combines multiple booking movements; reconciliation matches its report to the incoming wire](https://cdn.prod.website-files.com/5e71e686d09a97adb643219b/6aa92a38edeebdc673004d07_reconciliation-example.png)

*One channel payout combines multiple booking movements; reconciliation matches its report to the incoming wire*

*Illustrative amounts: two positive booking movements and a correction to an older booking settle in one €650 wire. A later movement for Booking A belongs to another payout. The event and wire can arrive in either order; reconciliation needs both.*

## Split Payments: making the distribution happen

Split Payments turns the property manager’s agreement with the owner into actual money movements.

The amount available for distribution depends on more than a single commission percentage. Channel costs, booking fees and the configured allocation rules all matter. The system calculates the shares and creates the transfers to the respective wallets, including the applicable split-payment fee.

For supported cases, this removes the step where the property manager receives everything and then has to calculate and transfer the owner’s share separately.

The calculation behind those shares is visible in **Revenue Distribution**. It breaks the booking total into acquisition costs, the property manager’s share and the owner’s share, with expandable calculations underneath each amount. The selected commission model defines the calculation base; the configuration also determines how booking fees and applicable payment costs are allocated.

Here is a Booking.com example from our Smily Admin UI screenshot catalogue. It uses the **Net payout** model, a 20% property-manager commission and Cancellation Protection. The €1,150 guest total consists of €1,000 rent, €100 cleaning and €50 city tax. These are demonstration data and configured example rates.

![Smily Admin UI: Booking.com revenue distribution with channel commission, Payments by Booking.com processing fees and Cancellation Protection](https://cdn.prod.website-files.com/5e71e686d09a97adb643219b/6aa92a5657dd0d71a7f2593f_bookingcom-revenue-distribution.png)

*Smily Admin UI: Booking.com revenue distribution with channel commission, Payments by Booking.com processing fees and Cancellation Protection*

*Existing demonstration screenshot: €547.68 for the owner, €116.52 for the property manager and €485.80 in the Acquisition fees section. This shows the revenue calculation; it is not a bank-payout confirmation.*

The acquisition breakdown separates **€187 Booking.com commission**, **€15.40 Payments by Booking.com processing fees**, **€84.50 Travelers’ Fees**, **€110 Cancellation Protection**, and **€88.90 in taxes**. The tax section itself separates city tax from the VAT on Travelers’ Fees and Cancellation Protection. “Acquisition fees” is the UI’s grouping for these costs and taxes; it is not all Smily revenue.

The property-manager calculation then shows exactly how the rent available for distribution becomes **€582.60** after the relevant deductions. The manager receives 20%, or **€116.52**. The owner receives the remaining **€466.08**, plus **€81.60** from cleaning after its channel commission and processing fee, giving **€547.68** in total. Together, `€485.80 + €116.52 + €547.68 = €1,150.00`.

Each expanded row explains which part of the booking generated a cost: rent, cleaning, Travelers’ Fees or their VAT. That detail lets a property manager understand both the final share and the calculation that produced it. Split Payments uses the applicable distribution rules to turn recipient shares into wallet transfers.

Of course, real bookings do not always fit the straightforward case. There may be insufficient funds for the expected split, an adjustment, or a payment outside the supported flow. We have an explicit fallback recipient for cases where the automatic split cannot be performed, and we record the reconciliation failure for follow-up.

A configured split and a completed split are different states. Keeping that distinction is part of the system.

## Travelers’ Fees: a small calculation with consequences

Travelers’ Fees are charged to the guest on eligible bookings. For channel bookings, collecting them requires us to account for how the channel takes its commission from the price we publish.

Simply adding the desired fee to that price is not enough. Part of the increase can itself be consumed by commission. We need a markup that preserves the intended amount after the configured deductions.

The required markup is:

![Required markup formula using the retained Travelers’ Fee and base percentage fractions](https://cdn.prod.website-files.com/5e71e686d09a97adb643219b/6aa92b7372f175f9ab75bd9a_Transparent%20Window%202026-09-15%20at%201.26.00%20PM.jpeg)

Here, **t** is the gross Travelers’ Fee percentage, including VAT, and **b** is the configured base percentage used to calculate the channel price increase. Their retained fractions multiply; adding the percentages would produce a different result.

For a simplified example, suppose those percentages are 2% and 20%, and the starting amount is €100. The combined retained fraction is `0.98 × 0.80 = 0.784`. Recovering €100 therefore requires a published price of approximately €127.55—a 27.55% markup. Adding 22% would produce €122, leaving only €95.65 after the same factors. These are illustrative inputs, not Smily’s pricing.

When the channel payout arrives, we collect the applicable fee through reconciliation and retain its link to the booking. For money collected through SmilyPay, the fee participates in the booking’s reconciliation flow. If the available funds cannot cover a fee, its outstanding amount needs a separate record and a later collection movement.

The formula determines what to publish. Reconciliation and accounting make sure we can explain what was collected.

## Cancellation Protection: two paths for the money

Flexible cancellation policies help travelers feel comfortable booking, but they also expose property managers and owners to lost rental income when a guest cancels.

[Cancellation Protection](https://www.smily.com/software/features/cancellation-protection) lets a property manager offer a protected refundable rate alongside a non-refundable option. When a protected guest cancellation meets the eligibility conditions, the program provides reimbursement of **96% of the rent**. The traveler gets flexibility, while the property manager and owner have protection for the rental income.

The property manager can also add a markup above the protection fee, creating an additional revenue stream when travelers choose the refundable option. SmilyPay handles the fee and payout infrastructure. The product is currently available on Airbnb and Booking.com, with protected bookings, fees, eligibility and claim progress visible inside Smily.

For our engineering team, that adds a second financial outcome to support: a reservation may generate booking proceeds, or an eligible cancellation may lead to reimbursement from the **CPR Partner**. Both need to connect to the booking and its financial records.

There are two flows worth separating.

In the booking-proceeds flow, the applicable protection fee is collected during reconciliation. It appears alongside the other applicable fees and the recipient distribution.

In the reimbursement flow, we receive a wire from the CPR Partner and match it to the reimbursement record. We credit the **full received reimbursement** to the designated recipient’s wallet, which can belong to the property manager or the owner. We separately record the applicable protection fee as an outstanding debt against that wallet.

![CPR Partner reimbursement: full recipient credit and separate protection-fee collection](https://cdn.prod.website-files.com/5e71e686d09a97adb643219b/6aa92a9e134aebaebd475725_reimbursement.png)

*CPR Partner reimbursement: full recipient credit and separate protection-fee collection*

*The reimbursement goes to one designated recipient. Fee collection is a separate transfer. In the Smily-managed payout flow, outstanding debt prevents payout scheduling until collection completes.*

Why make these separate movements? Because they describe different things: the reimbursement received and the fee owed. Both need to remain visible.

The debt collection process checks the wallet’s available balance and requests the fee transfer when it can be funded. The debt becomes collected when that transfer is acknowledged. Payout scheduling checks for outstanding debts before releasing money to the external bank account.

In practical terms, this lets us recover the fee from available funds before a subsequent bank payout. If the wallet cannot fund the collection yet, the outstanding amount remains recorded and the payout waits.

It also means the export can show the reimbursement and the later fee collection separately, linked back to the original booking.

## Wallet transfers and bank payouts are different steps

By this point, we have determined who receives what. The money still needs to reach the recipients’ own bank accounts.

A transfer between wallets represents an allocation inside the payment system. A payout sends available funds from a recipient’s wallet to their external bank account.

We support daily and weekly payout schedules. Scheduling operates on acknowledged transfers that have become eligible for payout, accounts for outgoing movements, and checks the available provider balance. Bank processing and the funds’ eligibility still determine when money can actually arrive.

This separation lets the system handle booking-level distribution independently from the recipient’s payout cadence. Several bookings and fee collections can contribute to one bank payout.

Which leads to the question the recipient will eventually ask: what exactly is in this transfer?

## Exports: following the money back to its source

The completed-payout CSV gives property managers a breakdown they can use in their accounting workflow: the related bookings, applicable fees, reimbursements, carry-over collections and payout amounts.

We also expose payout data through our documented API v3. Two resources cover the two stages of a channel-settled payment:

- [`/payouts`](https://developers.bookingsync.com/reference/endpoints/payouts) describes the Smily payout and its items.
- [`/channel_payouts`](https://developers.bookingsync.com/reference/endpoints/channel_payouts) describes the channel’s movements and their breakdown in a normalized form, so API consumers do not need to interpret a different format for every supported channel.

Related channel-payout references connect the two. An integration can move from a bank payout to the relevant booking items, then inspect the channel movements behind those items.

![Payout exports connect recipient payouts to booking items and channel movements](https://cdn.prod.website-files.com/5e71e686d09a97adb643219b/6aa92abf4e5b7ed3cee0b73e_exports.png)

*Payout exports connect recipient payouts to booking items and channel movements*

*CSV and API use shared export-row logic. Channel-side details remain a separate resource, connected by references.*

Inside the application, the CSV and API reuse the payout export row builder. The public serializer maps those rows into the API representation instead of independently recalculating their financial amounts.

Connecting these records also means preserving what each amount represents. Under Split Payments, a booking-level figure can cover both recipients, while a bank payout belongs to just one. Integrations need that distinction to explain why a booking total differs from the amount paid to a particular recipient.

Channel adjustments introduce another reporting limit: the channel may supply a net correction without enough detail to explain every component. We preserve the reported movement without inventing a breakdown. Our [Understanding payouts guide](https://developers.bookingsync.com/guides/understanding-payouts) explains these cases; the payout endpoints are currently in beta.

## The controls around the happy path

The straightforward journey is only part of the implementation. The system also needs to distinguish money that has arrived, money that has been allocated, and money that can actually leave a wallet.

A few controls make those boundaries concrete:

- **Record incoming notifications and track their processing.** The payment webhook handler checks whether a stored notification has already been processed and marks it after handling succeeds. This gives recovery a record to work from and guards against reprocessing a completed notification.
- **Match references and amounts before distributing funds.** Reconciliation checks the wire against the stored channel payout and verifies that its transfer plan accounts for the received amount. Unmatched or ambiguous inputs need follow-up, not an invented allocation.
- **Settle outstanding debts before releasing a bank payout.** A queued payout must wait until the debt has been collected. Requesting collection is not enough: we wait for confirmation that it completed before allowing the payout to proceed.

These controls give us specific states to investigate when the journey stops. They also keep a later recovery connected to the original booking, fee or payout rather than turning it into an unexplained correction.

## What this allowed us to build

SmilyPay, virtual IBANs, Split Payments, Travelers’ Fees, Cancellation Protection and payout exports each solve a different part of the workflow. Their value grows when they work together.

The virtual IBAN brings channel funds into the system. Reconciliation connects those funds to bookings and commercial rules. Wallet transfers execute the distribution and fee collection. Debt records preserve amounts that still need to be recovered. Bank payouts deliver the funds, and the exports explain them.

That is the foundation behind the FinTech portfolio’s contribution to our growth. We can build products around the financial life of a reservation because we have the machinery to collect their fees, distribute the proceeds and keep the movements connected.

The part I am proud of is how much of that journey our small team brought together. A reservation can start on an external channel, generate proceeds for several parties, involve protection and fee collection, and end in an accounting export that retains the context of those movements.

Getting a successful payment response was the beginning. Building everything around it is what made the system useful.
