---
layout: post
title: "Beyond the Engineering: How Tech Executives Can Collaborate With Other Business Leaders to Prevail Over Technical Debt"
date: 2024-07-16 8:00
comments: true
categories: [Technical Debt, Leadership, Business Impact]
published: false
---


In the [previous article](https://karolgalanciak.com/blog/2024/07/07/beyond-the-engineering-the-business-risks-of-ignoring-technical-debt/), I focused on **technical debt** as a crucial concept not merely in the engineering domain but in **multiple business areas** and how **effective communication** and **speaking the language of other stakeholders** is critical for successfully dealing with it. This time, let's dedicate more time to collaborating with other executives and business leaders and how they could get a solid understanding of the subject and contribute substantially to the resolution of the problem and even become advocates of the initiative.

To avoid generalization and be more specific, let's pick the CFO as the example hero executive for this article. Many KPIs can be translated to financial metrics with extra effort, and money is the common "language" for all business stakeholders, so the same reasoning and principles demonstrated in this article can be applied when discussing the matter with the rest of the leaders. Also, since we are talking about debt, who else would be a better partner on such a matter than a CFO?


<!--more-->

## The interests from technical debt - even more sneaky than you might think

What might not be entirely clear to non-tech business leaders is that technical debt is like real financial debt - it also accumulates interest. In the case of tech debt, though, these interests are a bit more sneaky. When paying off the monetary debt, you might not even notice that you are paying anything. When it comes to the tech one, it often turns out to be more impactful and is closer to the anchor that keeps slowing you down all the time rather than something that might go unnoticeable.

At the same time, a single financial debt is a singular item - so there is only one corresponding installment. When it comes to technical debt, it's not impossible to have a few different installments from a single item!

Imagine the case where the engineering team is pressured by a tight deadline and is making some significant design tradeoffs in the complex distributed system. Not only can this make expanding the system more difficult and time-consuming, but it will likely make the system more unreliable, taking more time on the developers' side to debug the issues (not to mention customer dissatisfaction caused by these problems). It may also trigger extra alerts and notifications, disrupting the flow and killing engineers' productivity, resulting in alert fatigue.

It already sounds like a severe issue, but it's not everything that can go wrong! If this issue persists for a long enough time, it will undoubtedly impact developers' satisfaction and might cause turnover, as it doesn't sound like a great environment to work in. Furthermore, it's not unusual to be asked during job interviews about the state of the tech debt by the candidates, especially the more promising ones - and such an environment doesn't sound very welcoming.

Of course, such a critical scenario was supposed to demonstrate a point: not every tech debt is that severe. Sometimes, the interest is nearly zero! Nevertheless, it's essential to understand that tech debt can impact multiple areas.

# Why CFOs play a crucial role in addressing technical debt

The answer to why CFOs play a crucial role in addressing technical debt is straightforward—they are accountable for the budget. Without the budget, nothing will get done. The CFO ultimately decides how much funding will be allocated for technical debt (if any).

The good news is that CFOs might see clear benefits of addressing tech debt, assuming that the tech executives communicate the matter effectively.

## How CFOs and CTOs can collaborate to prevail over tech debt - metrics, KPIs and financial impact

While mutual understanding of the term and the impact of its interests is fundamental, it doesn't end there—it's just a start. To go beyond that, we need some numbers to make data-informed decisions.

We need precise numbers demonstrating a return on investment to tackle the technical debt. The good news is that we have quite a few fundamental metrics that can often be easily translated into a monetary impact:

- **On-time delivery** - how well engineering teams are meeting their commitments
- **Cycle Time** - how quickly the teams can deliver the projects
- **Incident Frequency** - number of incidents in a given period (reflecting reliability)
- **Allocations** - what the teams are working on (where their time is allocated)
- **Customer churn** - loss of customers in a given period
- **Ramp-up Time** - how quickly new hires become productive

For example, by knowing the total cost of monthly salaries for a given team, we can see how a 20% productivity loss (reflected in Cycle Time, On-Time Delivery, and likely in Allocations) becomes a financial issue. To illustrate the impact, for a team of 25 engineers with an average compensation of 6000€, a 20% productivity loss equals €30 000 per month.

To compensate for that loss, hiring new engineers might be required. It creates two challenges, though:
When working with external recruiters, the success fee per hire might be pretty high, even 20% of the annual compensation for a senior role. For a single developer with a monthly compensation of 6000€, it translates to 14 400€.
Depending on the Ramp-Up Time, hiring engineers will decrease the current team's productivity for some time as the developers will need to invest their time into onboarding, training, and mentoring new hires. This will exacerbate the issue even further in the initial stage.

Incident Frequency and Customer Churn are likely correlated if the technical debt causes reliability issues. Customer Churn translates directly into a revenue loss, so for a 10 mln € ARR company, an increase of the churn by 1 percentage point would be equal to a loss of 100 000€.

Having a solid understanding of the areas that would be impacted by paying off technical debt might be beneficial not only when speaking with CFOs or other executives but also with other engineers. It reminds me of a relatively recent conversation with one of the team leaders in Smily, who was initially skeptical about whether addressing technical debt should be at the top of the priorities in the given quarter. Understanding the expected impact on critical KPIs, especially the monetary impact, quickly resolved the doubts.

## CAPEX vs. OPEX

Going from technical debt straight to accounting might be a bit of a stretch, yet this is a valid concern - accrued technical debt resulting in a lot of maintenance and bug fixing can be a drag on the balance sheet as extra operational expenditures (OPEX). The same applies to incremental improvements, which only bring a few benefits to the business. At the same time, some major enhancements that bring significant value can be accounted for as capital expenditures (CAPEX). Depending on the priorities of the company, this can be a deciding factor in whether the technical debt will be a significant area of focus or not.

## Wrapping Up

As demonstrated, **technical debt** is not only an engineering problem but a **complex issue impacting multiple business areas**. It resembles real financial debt, sometimes even with even more sneaky installments.

Addressing it appropriately **requires effective communications** from the CTOs and close collaboration with other business leaders.

In the next part of the series, I'll focus on evaluating technical debt and successfully managing it.
