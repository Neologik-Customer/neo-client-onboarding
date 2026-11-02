# Finishing Steps After Deployment

## Overview

Neologik tells you when the deployment of the Neologik Platform to your resource group is complete. Five steps then remain before your users can work with the Neologik Platform. This guide is for the Administrators who complete the five steps.

Complete the five steps in the order shown. Step 2 needs the DNS record from step 1, because the consent page returns the browser to the environment by the host name. Step 5 applies only when an agent works unattended.

| Step | Who acts | Purpose |
|---|---|---|
| [1. Create the DNS record](#step-1-create-the-dns-record) | The person who manages your DNS | Directs the host name of the environment to the deployment |
| [2. Give administrator consent](#step-2-give-administrator-consent) | A Global Administrator | Allows each sign-in application to sign in your users |
| [3. Publish the Teams app](#step-3-publish-the-teams-app) | A Teams Administrator | Makes the agent available in Microsoft Teams |
| [4. Give users access](#step-4-give-users-access) | A Groups Administrator or a Global Administrator | Adds users to the security groups |
| [5. Give agent accounts access](#step-5-give-agent-accounts-access) | An administrator of Microsoft 365. [AGENT-ACCOUNT-ACCESS-GUIDE.md](AGENT-ACCOUNT-ACCESS-GUIDE.md) names the role for each task | Gives an agent account access to a mailbox, a site or a team. Applies only when an agent works unattended |

## Contents

1. [What you need](#what-you-need)
2. [Step 1: Create the DNS record](#step-1-create-the-dns-record)
3. [Step 2: Give administrator consent](#step-2-give-administrator-consent)
4. [Step 3: Publish the Teams app](#step-3-publish-the-teams-app)
5. [Step 4: Give users access](#step-4-give-users-access)
6. [Step 5: Give agent accounts access](#step-5-give-agent-accounts-access)
7. [Checklist](#checklist)
8. [Later changes](#later-changes)
9. [Update windows](#update-windows)
10. [Troubleshooting](#troubleshooting)
11. [Help](#help)

## What you need

Neologik sends you these items.

| Item | Step |
|---|---|
| Confirmation that the deployment is complete | All steps |
| The target of the DNS record, which is a public IP address or a host name | Step 1 |
| A consent link for the Platform Sign-in application | Step 2 |
| A consent link for the sign-in application of each agent with a Teams channel or a web chat channel | Step 2 |
| The Teams app package for each agent with a Teams channel. A Teams app package is a `.zip` file | Step 3 |

Steps 1 to 4 need these roles.

| Role | Step |
|---|---|
| The person who manages the DNS zone of your domain | Step 1 |
| Global Administrator | Step 2 |
| Teams Administrator | Step 3 |
| Groups Administrator or Global Administrator | Step 4 |

[AGENT-ACCOUNT-ACCESS-GUIDE.md](AGENT-ACCOUNT-ACCESS-GUIDE.md) names the role for each task of step 5.

`<short name>` stands for the short name of the environment, for example `abcprd01`. The completion summary of the onboarding script shows the short name.

## Step 1: Create the DNS record

Neologik sends you the target of the DNS record. The type of the DNS record depends on the target.

| Target that Neologik sends | Type of DNS record | Value of DNS record |
|---|---|---|
| A public IP address | A | The public IP address |
| A host name | CNAME | The host name |

1. Sign in to your DNS provider and open the zone of your domain.
2. Create the DNS record with these values:

   | Field | Value |
   |---|---|
   | Type | A or CNAME, from the table above |
   | Name | The first part of the host name of the environment. For `neologik.contoso.com`, enter `neologik` |
   | Value | The target that Neologik sent |
   | TTL | 3600, or a value of your choice |

3. Save the DNS record.
4. Confirm that the host name resolves:

   ```powershell
   nslookup neologik.contoso.com
   ```

   The answer shows the target that you entered. A new DNS record usually resolves within minutes. Some resolvers take up to 48 hours.

5. Open `https://<your host name>/nce` in a browser. The Neologik Context Engine opens and asks you to sign in. The Neologik Context Engine shows the name **Neologik Admin Tool** on screen. The sign-in page confirms that the host name and the TLS certificate work.

## Step 2: Give administrator consent

A sign-in application signs in your users. One sign-in application is the Platform Sign-in application. Each agent with a Teams channel or a web chat channel has one further sign-in application.

Neologik sends one consent link for each sign-in application.

Each sign-in application asks for delegated Microsoft Graph permissions. A delegated permission works on behalf of the signed-in user.

A Global Administrator gives consent to the permissions once, for the whole tenant. Microsoft then asks no user for consent.

Complete these steps for each consent link that Neologik sent.

1. Open the consent link in a browser. The consent link has this form:

   ```
   https://login.microsoftonline.com/<tenant id>/adminconsent?client_id=<application id>&redirect_uri=https://<your host name>/nce/consent-complete
   ```

2. Sign in as a Global Administrator.
3. Read the permissions that the page lists. The page lists every permission that the sign-in application requests.
4. Select **Accept**.

The browser then returns to the confirmation page of the environment. The confirmation page reports success, or shows the message from Microsoft.

To confirm the consent later, follow these steps.

1. In the Azure portal, open **Microsoft Entra ID**, then **Enterprise applications**.
2. Open the sign-in application.
3. Select **Permissions**.

## Step 3: Publish the Teams app

### Upload the Teams app

1. Sign in to the Teams admin centre, https://admin.teams.microsoft.com, as a Teams Administrator.
2. Open **Teams apps**, then **Manage apps**.
3. Select **Upload new app** and select the `.zip` file.
4. Open the Teams app. Confirm the name, the description and the permissions.
5. Check that the status of the Teams app reads **Allowed**.

Repeat these steps for each Teams app package that Neologik sent.

### Allow the Teams app

1. Open **Teams apps**, then **Permission policies**.
2. Edit the policy **Global (Org-wide default)**, or create a new policy.
3. Under **Custom apps**, allow all apps. Alternatively, allow specific apps and add the Neologik Teams app.
4. When you created a new policy, assign the new policy to the users or to the group `Neologik User Group - <short name>`.

### Make the Teams app available to users

Choose one of the two methods.

| Method | Steps |
|---|---|
| Each user adds the Teams app | In **Manage apps**, open the Teams app. Under **Available to**, choose everyone in your organisation, or choose specific groups and select `Neologik User Group - <short name>`. Save |
| Microsoft Teams installs the Teams app for each user | Open **Teams apps**, then **Setup policies**. Edit a policy or create a policy. Under **Installed apps**, select **Add apps**. Find the Neologik Teams app and add the Teams app. Save. Assign the policy to `Neologik User Group - <short name>` |

### Tell your users

Tell your users three things:

- the Teams app is available
- the name to search for under **Apps** in Microsoft Teams
- how to pin the Teams app

## Step 4: Give users access

A security group in your Microsoft Entra tenant controls access to each agent. Only a member of the security group of an agent can use that agent. The agent refuses any other user, even when the user can see the Teams app.

Each agent uses the group `Neologik User Group - <short name>`, which the onboarding script created. To use another security group for an agent, tell Neologik the name of an existing security group. The Neologik Platform creates no security group.

### Add a user

1. In the Azure portal, open **Microsoft Entra ID**, then **Groups**.
2. Search for `Neologik User Group` and open the group.
3. Select **Members**, then **Add members**.
4. Find the user, select the user and confirm.

The user has access within a few minutes. No restart and no new deployment is needed. When the agent still refuses the user, ask the user to close the agent in Microsoft Teams and open the agent again.

### Remove a user

1. Open the group and select **Members**.
2. Select the user.
3. Select **Remove**.

### The other security groups

The onboarding script created three further security groups. Add a person to one of these groups only when the person needs the role.

| Group | Role of a member |
|---|---|
| `Neologik NCE Contributors - <short name>` | Configures agents and Apps in the Neologik Context Engine |
| `Neologik NCE Admins - <short name>` | Administers the Neologik Context Engine |
| `Neologik Admin User Group - <short name>` | Administers the Azure resources in the resource group |

You manage the members of all four security groups.

## Step 5: Give agent accounts access

Step 5 applies only when an agent works unattended. An agent works unattended when the agent does one of these things:

- runs on a schedule
- reads files from a SharePoint library
- reads or sends email from a shared mailbox

An agent that works unattended has an agent account in your Microsoft Entra directory. An administrator assigns a licence to the agent account. An administrator then gives the agent account access to the mailbox, the site or the team.

[AGENT-ACCOUNT-ACCESS-GUIDE.md](AGENT-ACCOUNT-ACCESS-GUIDE.md) gives the instructions.

## Checklist

| Check | Done |
|---|---|
| A DNS lookup of the host name returns the target that Neologik sent | |
| `https://<your host name>/nce` opens and asks for a sign-in | |
| A Global Administrator has given administrator consent for the Platform Sign-in application | |
| A Global Administrator has given administrator consent for the sign-in application of each agent | |
| The Teams app is uploaded and the status reads **Allowed** | |
| The Teams app is available to `Neologik User Group - <short name>` | |
| At least one test user is a member of the security group of each agent | |
| The test user can find the Teams app, send a message and receive a reply | |

When the checklist is complete, follow these steps.

1. Tell Neologik.
2. Test with a small group of users.
3. Plan the wider rollout.

## Later changes

When an agent or an App is to work unattended in Microsoft 365, a Global Administrator runs the grants script, `Grant-NeologikAgentAccess.ps1`, with the agent grants file and the mailbox grants file. The agent grants file lists the grants to agent users. A platform operator downloads the agent grants file from the **Admin** page of the Neologik Context Engine. The mailbox grants file lists the mailbox grants of the email channels. Neologik sends the mailbox grants file. The Global Administrator runs the grants script again whenever either file changes.

[GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md](GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md) explains three subjects:

- what the grants script applies
- what the sign-in asks you to approve
- what you receive at the end of the run

The home page of the Neologik Context Engine lists each outstanding deployment step under **Outstanding tasks**.

## Update windows

The Neologik Platform takes updates inside weekly windows. The table shows the default windows.

| Update | What the update changes | Default window | Default state |
|---|---|---|---|
| Azure Kubernetes Service maintenance | The node image and the Kubernetes patch version of the cluster | Sunday, 02:00 to 06:00 UTC | On |
| Neologik Platform updates | The newest release of each Neologik Platform component, on the version of your environment | Sunday, 06:00 to 10:00 UTC | Off |

The cluster continues to function through Azure Kubernetes Service maintenance, so the Neologik Platform continues to operate. Azure can apply an urgent security fix outside the window. A cluster that stops outside working hours starts for each window that is on, then stops afterwards.

The times in the table are the default windows. Neologik Support can change a window or disable a window. Neologik does not recommend that you disable a window, because your environment then stops receiving security updates and fixes. Neologik Platform updates stay off until you ask Neologik Support to turn the updates on. To ask for a change, email support@neologik.ai.

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| The host name does not resolve | The DNS record has not reached your resolver, or the DNS record is in the wrong zone | Check the DNS record with your DNS provider. Wait for the TTL to pass. On Windows, the command `ipconfig /flushdns` clears the local cache |
| A DNS lookup of the host name returns another target | The value of the DNS record is wrong | Correct the DNS record |
| The browser reports a certificate error | The TLS certificate is for another host name, or the certificate chain is incomplete | Check the TLS certificate against [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md) and tell Neologik |
| A user sees the message "Need admin approval" | No Global Administrator has given administrator consent for the sign-in application | Open the consent link for the sign-in application, as described in step 2 |
| A consent link reports an error | A Global Administrator opened the consent link before the host name resolved, or signed in to the wrong tenant | Complete step 1. Check the tenant that you signed in to. Open the consent link again |
| The agent refuses a user | The user is not a member of the security group of the agent | Add the user to the security group, as described in step 4 |
| The agent refuses a user who joined the security group a few minutes ago | The session of the user does not yet show the new membership | Ask the user to close the agent in Microsoft Teams and open the agent again |
| The Teams app does not appear in Microsoft Teams | The permission policy does not allow the Teams app, or the Teams app is not available to the group of the user | Check the permission policy and the availability, as described in step 3 |

## Help

Email support@neologik.ai with these details:

- the step that you have reached
- the error message, or a screenshot of the error message
- the name of your organisation and the host name of the environment
