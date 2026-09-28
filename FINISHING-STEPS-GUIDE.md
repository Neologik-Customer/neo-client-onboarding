# Finishing Steps After Deployment

## Overview

When Neologik has deployed the platform to your resource group, the steps below remain before your users can work with it. Complete them in the order given: the consent in step 2 returns to the environment by its host name, so the DNS record in step 1 comes first.

| Step | Who | Purpose |
|---|---|---|
| [1. Create the DNS record](#step-1-create-the-dns-record) | Your DNS administrator | Points the environment's host name at the deployment |
| [2. Give administrator consent](#step-2-give-administrator-consent) | Your Global Administrator | Lets the sign-in applications sign your users in |
| [3. Publish the Teams app](#step-3-publish-the-teams-app) | Your Teams administrator | Makes the agent available in Microsoft Teams |
| [4. Give users access](#step-4-give-users-access) | Your Microsoft Entra administrator | Adds users to the access groups |
| [5. Give agent accounts access](#step-5-give-agent-accounts-access) | Your Microsoft 365 administrators | Needed only when an agent works unattended |

## Contents

1. [What you need](#what-you-need)
2. [Step 1: Create the DNS record](#step-1-create-the-dns-record)
3. [Step 2: Give administrator consent](#step-2-give-administrator-consent)
4. [Step 3: Publish the Teams app](#step-3-publish-the-teams-app)
5. [Step 4: Give users access](#step-4-give-users-access)
6. [Step 5: Give agent accounts access](#step-5-give-agent-accounts-access)
7. [Checklist](#checklist)
8. [Later changes](#later-changes)
9. [Troubleshooting](#troubleshooting)
10. [Help](#help)

## What you need

From Neologik:

| Item | Used in |
|---|---|
| Confirmation that the deployment is complete | All steps |
| The target of the DNS record: a public IP address, or a host name | Step 1 |
| A consent link for each sign-in application: the Platform Sign-in application and each agent with a Teams or web chat channel | Step 2 |
| The Teams app package (a `.zip` file) for each agent with a Teams channel | Step 3 |

Roles in your organisation:

| Role | Used in |
|---|---|
| Management of the DNS zone of your domain | Step 1 |
| Global Administrator | Step 2 |
| Teams Administrator | Step 3 |
| Groups Administrator or Global Administrator | Step 4 |

`<short name>` is the short name of the environment, shown in the completion summary of the onboarding script, for example `abcprd01`.

## Step 1: Create the DNS record

Neologik gives you the target of the record. Its form depends on your deployment type:

| Target supplied | Record type | Value |
|---|---|---|
| A public IP address | A | The IP address |
| A host name | CNAME | The host name |

1. Sign in to your DNS provider and open the zone of your domain.
2. Create the record:

   | Field | Value |
   |---|---|
   | Type | A or CNAME, as above |
   | Name | The host part of the environment's host name. For `neologik.contoso.com`, enter `neologik` |
   | Value | The target Neologik supplied |
   | TTL | 3600, or your organisation's standard |

3. Save the record.
4. Confirm that the name resolves:

   ```powershell
   nslookup neologik.contoso.com
   ```

   The answer shows the target you entered. A new record usually resolves within minutes; allow up to 48 hours for it to reach every resolver.

5. Open `https://<your host name>/nce` in a browser. The Neologik Context Engine opens and asks you to sign in, which confirms that the host name and the certificate are in place.

## Step 2: Give administrator consent

Each sign-in application asks for delegated Microsoft Graph permissions, which it uses on behalf of the signed-in user. A Global Administrator consents to them once, for the whole tenant, so that your users are not asked one by one.

For each link Neologik supplies:

1. Open the link in a browser. It has this form:

   ```
   https://login.microsoftonline.com/<tenant id>/adminconsent?client_id=<application id>&redirect_uri=https://<your host name>/nce/consent-complete
   ```

2. Sign in as a Global Administrator.
3. Read the permissions the page lists. The page lists every permission the application requests.
4. Select **Accept**.

The browser returns to the confirmation page of the environment, which reports success or the message from Microsoft.

To confirm the consent afterwards, open **Microsoft Entra ID**, then **Enterprise applications**, open the application and select **Permissions**.

## Step 3: Publish the Teams app

### Upload the app

1. Sign in to the Teams admin centre, https://admin.teams.microsoft.com, as a Teams Administrator.
2. Open **Teams apps**, then **Manage apps**.
3. Select **Upload new app** and select the `.zip` file.
4. Open the app and confirm its name, description and permissions. Check that its status reads **Allowed**.

Repeat for each package if Neologik supplied more than one.

### Allow the app

1. Open **Teams apps**, then **Permission policies**.
2. Edit the **Global (Org-wide default)** policy, or create a policy of your own.
3. Under **Custom apps**, allow all apps, or allow specific apps and add the Neologik app.
4. If you created a policy of your own, assign it to the users or to the group `Neologik User Group - <short name>`.

### Make the app available to users

Choose one of the two methods:

| Method | Steps |
|---|---|
| Users add the app themselves | In **Manage apps**, open the app. Under **Available to**, choose everyone in your organisation or specific groups, and select `Neologik User Group - <short name>`. Save |
| The app is installed for users | Open **Teams apps**, then **Setup policies**. Edit or create a policy. Under **Installed apps**, select **Add apps**, find the Neologik app and add it. Save, then assign the policy to `Neologik User Group - <short name>` |

### Tell your users

Tell your users that the app is available, the name to search for under **Apps** in Microsoft Teams, and how to pin it.

## Step 4: Give users access

Access to each agent is controlled by a security group in your Microsoft Entra tenant. Only members of the agent's group can use it; a user outside the group is refused even when the app is visible in Teams.

Every agent uses the group the onboarding script created, `Neologik User Group - <short name>`, unless you ask for another. To use a different group, or one group per agent, tell Neologik which existing group to attach. The platform does not create groups.

### Add a user

1. In the Azure portal, open **Microsoft Entra ID**, then **Groups**.
2. Search for `Neologik User Group` and open the group.
3. Select **Members**, then **Add members**.
4. Find the user, select them and confirm.

The user has access within a few minutes. No restart or redeployment is needed. If the user is still refused, ask them to close and reopen the agent in Teams.

### Remove a user

Open the group, select **Members**, select the user and select **Remove**.

### The other groups

The onboarding script created three further groups. Add your own staff to them only where they need the role:

| Group | Role |
|---|---|
| `Neologik NCE Contributors - <short name>` | Configures agents and Apps in the Neologik Context Engine |
| `Neologik NCE Admins - <short name>` | Administers the Neologik Context Engine |
| `Neologik Admin User Group - <short name>` | Administers the Azure resources in the resource group |

Group membership is yours to manage as people join, move and leave.

## Step 5: Give agent accounts access

This step applies only when an agent works unattended: it runs on a schedule, reads files from a SharePoint library, or reads or sends email from a shared mailbox. Such an agent has an agent account in your directory. Your administrators license the account and share the mailbox, site or team with it.

Follow [AGENT-ACCOUNT-ACCESS-GUIDE.md](AGENT-ACCOUNT-ACCESS-GUIDE.md).

## Checklist

| Check | Done |
|---|---|
| The host name resolves to the target Neologik supplied | |
| `https://<your host name>/nce` opens and asks for a sign-in | |
| Administrator consent is given for the Platform Sign-in application | |
| Administrator consent is given for each agent's sign-in application | |
| The Teams app is uploaded and allowed | |
| The Teams app is available to `Neologik User Group - <short name>` | |
| At least one test user is a member of each agent's access group | |
| The test user can find the app in Teams, send a message and receive a reply | |

When the checklist is complete, tell Neologik, test with a small group of users, and then plan the wider rollout.

## Later changes

After onboarding, Neologik may ask your Global Administrator to run `Update-NeologikEnvironmentAccess.ps1`, on one of two occasions:

| Occasion | What the script does |
|---|---|
| Before the environment moves to Neologik Platform version 5 | Reduces the access of the deployment identity to the roles it needs, and confirms the directory objects the platform uses |
| When an agent or App is to work unattended in Microsoft 365 | Applies the grants listed in the files Neologik supplies |

Neologik sends the complete command with every value filled in. [ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md](ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md) explains what the script checks and changes, what the sign-in asks you to approve, and what you receive at the end.

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| The host name does not resolve | The record has not reached your resolver, or it was created in the wrong zone | Check the record with your DNS provider and wait for the TTL to pass. On Windows, `ipconfig /flushdns` clears the local cache |
| The host name resolves to a different target | The record value is wrong | Correct the record |
| The browser reports a certificate error | The certificate was issued for a different host name, or its chain is incomplete | Check the certificate against [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md) and tell Neologik |
| A user sees "Need admin approval" | Administrator consent has not been given for that application | Open the consent link for the application, as in step 2 |
| A consent link reports an error | The link was opened before the host name resolved, or in the wrong tenant | Complete step 1, check the tenant you signed in to, and open the link again |
| A user is refused by the agent | The user is not a member of the agent's access group | Add the user to the group, as in step 4 |
| A user added a few minutes ago is still refused | The membership change has not reached the user's session | Ask the user to close and reopen the agent in Teams |
| The app does not appear in Teams | The app is not allowed by the permission policy, or is not available to the user's group | Check the policy and the availability, as in step 3 |

## Help

Email support@neologik.ai with:

- the step you have reached;
- the error message, or a screenshot of it;
- your organisation name and the environment's host name.
