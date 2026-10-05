# What the Neologik Platform reports to Neologik

## Overview

Your Neologik Platform environment reports aggregate operational statistics to Neologik. Neologik uses the statistics to support your environment. The statistics show Neologik that the environment is healthy and which software versions the environment runs. The statistics also let Neologik plan capacity, find faults early and report on usage.

This document is for Approvers, Administrators and anyone who reviews what leaves your environment. This document tells you what the environment reports and what the environment never reports. This document also tells you how long Neologik keeps the statistics and how to withdraw from reporting.

| Subject | Detail |
|---|---|
| What is reported | Counts, totals, timestamps and fixed labels about health, versions, configuration, usage and faults |
| What is never reported | Conversation content, documents, user identities, raw log lines and secrets |
| Direction | Outbound from your environment only. Neologik cannot reach into your environment through this reporting |
| Where Neologik keeps the statistics | Neologik's own Azure subscription in the UK South region of the United Kingdom |
| How long | The retention period in your agreement. 24 months unless your agreement states otherwise |
| How to withdraw | Ask Neologik at support@neologik.ai |

## Contents

1. [How reporting works](#how-reporting-works)
2. [What is reported](#what-is-reported)
3. [What is never reported](#what-is-never-reported)
4. [Information read from Azure outside your environment](#information-read-from-azure-outside-your-environment)
5. [How Neologik protects the statistics](#how-neologik-protects-the-statistics)
6. [Retention and deletion](#retention-and-deletion)
7. [Withdrawing from reporting or narrowing it](#withdrawing-from-reporting-or-narrowing-it)
8. [Changes to what is reported](#changes-to-what-is-reported)
9. [Questions](#questions)

## How reporting works

A single small software component runs inside your environment. On a fixed schedule the component calculates summary figures inside your environment. The component then sends only those figures to Neologik's analytics service over an encrypted connection.

The component makes outbound connections only. Neologik cannot reach into your environment through the component. The set of figures the component can report is fixed in its released software. Neologik can reduce or stop reporting remotely. Neologik cannot widen reporting without releasing new software to your environment.

## What is reported

Every item reported is a count, a total, a timestamp or a fixed label.

| Category | Examples |
|---|---|
| Service health | Running components and their versions, restart counts, pending workloads, resource saturation, warning events by reason |
| Configuration inventory | Names, types and status of agents, applications, channels, tools and search indexes. The data classification tier of each agent |
| Configuration changes | What changed, when it changed and which operator account changed it. Never the old or new values |
| Usage | Per agent per day: conversation counts, message counts, the number of distinct users as a count only, token totals by model and response times |
| Feedback | Per agent per day: counts of positive, negative and commented feedback. Never the comment text |
| AI model estate | Model deployments on the AI account of your environment: names, versions, provisioned capacity, daily request and throttling counts, peak usage against the allowance |
| Faults and errors | Error and warning patterns with daily counts: exception type names, method names, event reasons and status codes |
| Message patterns | Error and warning messages with every identifier and value removed before they leave your environment |
| Document processing | Per search index: file counts, sizes and error counts |
| Schedule | The start and stop times and days of the cluster of your environment |

Agent and search index display names are reported so that Neologik staff can discuss "the Finance agent" with you rather than an identifier. You may ask Neologik to withhold display names.

## What is never reported

- Conversation content, prompts, documents, search results or files.
- User names, email addresses or any identifier of an individual user. User activity appears only as counts.
- Raw error messages or stack traces.
- Secrets, connection strings, keys or endpoint addresses.
- Tenant identifiers or infrastructure identifiers other than the name of your environment.

Two technical controls enforce this. The database account of the component can read only a dedicated set of summary views. The database account has no permission on any table that holds content. The transport format holds only numbers, fixed labels and masked message patterns. Content has nowhere to travel, even in error.

## Information read from Azure outside your environment

Separately from the component above, Neologik's central tooling reads the following directly from Azure. The tooling uses the deployment credentials that already operate your environment.

| Item | Detail |
|---|---|
| Subscription | The display name, offer type and state of your subscription |
| Daily total cost | One figure per day for the whole subscription. No resource detail and no usage detail. On a subscription bought through a Cloud Solution Provider, Azure returns this figure only when the partner has enabled cost visibility for you. Until then Neologik reads no cost figure |
| Credential expiry dates | The expiry dates of the credentials held by Neologik's own application registrations in your directory, so that Neologik renews them before they lapse |
| Deployed versions | The software versions recorded in Neologik's own deployment records for your environment |

None of these reads touches anything inside your environment.

## How Neologik protects the statistics

- Your environment authenticates to the analytics service with a key held in the key vault of your environment. Neologik stores only a hash of the key.
- Neologik stores the statistics in Neologik's own Azure subscription in the UK South region of the United Kingdom.
- Access to the statistics is limited to named Neologik staff through Microsoft Entra sign-in.

## Retention and deletion

Neologik keeps the statistics as daily summaries for the retention period in your agreement. The retention period is 24 months unless your agreement states otherwise. Neologik's analytics service applies the retention period to your environment and deletes older statistics every day. Neologik records each deletion.

When your agreement ends, or when you withdraw from reporting, Neologik erases every statistic held for your environment within 30 days. Neologik confirms the erasure in writing.

## Withdrawing from reporting or narrowing it

You may withdraw from reporting at any time. Ask Neologik at support@neologik.ai. Neologik then removes the component from your environment, and nothing remains that reports.

You may instead ask Neologik to narrow reporting. Examples:

- keep health reporting and stop usage reporting
- withhold agent and search index display names

## Changes to what is reported

Any addition to the list of reported items requires a new software release to your environment. Neologik tells you of the change before that release is deployed. This document lists the reported items for the version of the Neologik Platform that the onboarding kit belongs to.

## Questions

Send questions and requests about reporting to support@neologik.ai.
