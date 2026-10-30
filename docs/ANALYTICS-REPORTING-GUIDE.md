# What the Neologik Platform reports to Neologik

## Overview

Your Neologik Platform environment reports operational statistics to Neologik, with the names and ids that this document lists. Neologik uses the statistics to support your environment. The statistics show Neologik that the environment is healthy and which software versions the environment runs. The statistics also let Neologik plan capacity, find faults early and report on usage.

This document is for Approvers, Administrators and anyone who reviews what leaves your environment. This document tells you what the environment reports and what the environment never reports. This document also tells you how long Neologik keeps the statistics and how to withdraw from reporting.

| Subject | Detail |
|---|---|
| What is reported | Counts, totals, timestamps and fixed labels about health, versions, configuration, usage and faults. The names and ids of configuration objects. The operator account behind each configuration change. Outstanding tasks |
| What is never reported | Conversation content, documents, the identity of an end user, raw log lines and secrets |
| Direction | Outbound from your environment only. Neologik cannot reach into your environment through this reporting. The one exception is the log query relay, which runs only with your recorded agreement |
| Where Neologik keeps the statistics | Neologik's own Azure subscription in the UK South region of the United Kingdom |
| How long | The retention period in your agreement. 24 months unless your agreement states otherwise |
| How to withdraw | Ask Neologik at support@neologik.ai |

## Contents

1. [How reporting works](#how-reporting-works)
2. [What is reported](#what-is-reported)
3. [What is never reported](#what-is-never-reported)
4. [The log query relay](#the-log-query-relay)
5. [Information read from Azure outside your environment](#information-read-from-azure-outside-your-environment)
6. [How Neologik protects the statistics](#how-neologik-protects-the-statistics)
7. [Retention and deletion](#retention-and-deletion)
8. [Withdrawing from reporting or narrowing it](#withdrawing-from-reporting-or-narrowing-it)
9. [Changes to what is reported](#changes-to-what-is-reported)
10. [Questions](#questions)

## How reporting works

A single small software component runs inside your environment. On a fixed schedule the component prepares the reported items inside your environment. The component then sends only those items to Neologik's analytics service over an encrypted connection.

The component makes outbound connections only. Neologik cannot reach into your environment through the component. The set of items the component can report is fixed in the released software. Neologik can reduce or stop reporting remotely. Neologik cannot widen reporting without releasing new software to your environment. [The log query relay](#the-log-query-relay) is the one exception. The log query relay runs only with your recorded agreement.

## What is reported

Most reported items are counts, totals, timestamps and fixed labels. The other items are names, ids and masked message patterns, as the table shows.

| Category | Examples |
|---|---|
| Service health | Running components and their versions, restart counts, pending workloads, resource saturation, warning events by reason |
| Configuration inventory | Names, types and status of agents, applications, channels, tools and search indexes. The data classification tier of each agent |
| Configuration changes | What changed and when. The display name of the operator account that made the change. The object id of the account stands in when the sign-in token holds no display name. A change by an application shows the client id of the application. A change by the platform shows a fixed label. Never the old or new values |
| Outstanding tasks | One entry for each deployment step that waits for your administrator or for Neologik. Each entry holds the type of the task, the owner, the status and the date the task began. Each entry also holds the kind, the id and the name of the object. An entry can also hold the id of the related App or agent. The total of tasks for each owner. Never the instruction text or a consent link |
| Usage | Per agent per day: conversation counts, message counts, the number of distinct users as a count only, token totals by model and response times |
| Feedback | Per agent per day: counts of positive, negative and commented feedback. Never the comment text |
| AI model estate | Model deployments on the AI account of your environment: names, versions, provisioned capacity, daily request and throttling counts, peak usage against the allowance |
| Faults and errors | Error and warning patterns with daily counts: exception type names, method names, event reasons and status codes. The name of the service, the Azure resource or the host that a fault concerns |
| Message patterns | Error and warning messages with every identifier and value removed before they leave your environment |
| Document processing | Per search index: file counts, sizes and error counts |
| Schedule | The start and stop times and days of the cluster of your environment |
| Automatic updates | The settings of the automatic update window. One entry for each update window. Each entry holds the kind of update, the outcome and the target release. Each entry also holds a link to the update run and a short message about the outcome |

Agent and search index display names are reported so that Neologik staff can discuss "the Finance agent" with you rather than an identifier. You may ask Neologik to withhold display names.

## What is never reported

- Conversation content, prompts, documents, search results or files.
- The name, the email address or any other identifier of an end user. User activity appears only as counts.
- Raw error messages or stack traces.
- Secrets, connection strings or keys.
- Tenant identifiers or subscription identifiers.

Two technical controls enforce this. The database account of the component can read only a dedicated set of summary views. The database account has no permission on any table that holds content. The transport format holds only numbers, fixed labels, the names and ids that the table lists, and masked message patterns. Content has nowhere to travel, even in error. The log query relay, which runs only with your recorded agreement, is the one exception.

## The log query relay

The log query relay stays off unless you record your agreement with Neologik. Without that agreement, the component answers no query from Neologik.

With your agreement, an automated Neologik review of a fault can read the log records of your environment.

| Subject | Detail |
|---|---|
| How a query reaches your environment | The component asks Neologik's analytics service for waiting queries every 20 seconds, over the same outbound connection |
| What a query reads | The Log Analytics workspace of your environment, through the identity of the component. The analytics service accepts a query only when the query starts with one of these tables: `AppExceptions`, `AppDependencies`, `AppTraces`, `AppRequests`, `KubeEvents`, `ContainerLogV2` or `AGWAccessLogs` |
| Limits | 200 rows and 168 hours for each query |
| What leaves your environment | The rows, after the component masks each text cell inside your environment. The masking replaces email addresses, web addresses, file names, ids and numbers. The component cuts each text cell to 300 characters. Other words of a log record stay in the text cell. Dates, numbers and true or false values in a column of their own stay as they are |
| Who reads the rows | The automated Neologik review and Neologik staff. The automated review uses a Claude model from Anthropic |
| What Neologik keeps | Each query and the masked rows, in Neologik's analytics service |
| How to turn the log query relay off | Ask Neologik at support@neologik.ai |

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
