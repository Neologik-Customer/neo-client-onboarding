# Preparing the TLS Certificate

## Overview

Your users reach the Neologik environment over HTTPS at the host name of the environment, for example `neologik.contoso.com`. The environment needs a TLS certificate for that host name.

| Requirement | Detail |
|---|---|
| Issuer | A certificate authority that the devices of your users trust |
| Name | The host name of the environment, or a wildcard name that includes the host name |
| Format | One PFX file, protected by a password. A PFX file is also called a PKCS#12 file |

This guide explains three tasks:

1. which files you need
2. how to build the PFX file with the script `Export-NeologikCertificate.ps1`
3. how to import the PFX file into the Key Vault of the environment

Keep the PFX file and the password of the PFX file. Do not send the PFX file or the password to Neologik. After the import, Neologik copies the certificate, private key included, into Neologik's central Key Vault.

You may already hold a PFX file that contains the private key and the full certificate chain. In that case, go to [Import the PFX file into the Key Vault](#import-the-pfx-file-into-the-key-vault).

## Contents

1. [The files you need](#the-files-you-need)
2. [Create the PFX file with the script](#create-the-pfx-file-with-the-script)
3. [Import the PFX file into the Key Vault](#import-the-pfx-file-into-the-key-vault)
4. [Create the PFX file by hand](#create-the-pfx-file-by-hand)
5. [Troubleshooting](#troubleshooting)

## The files you need

| File | Usual extension | Source |
|---|---|---|
| Private key | `.key` | You generate the private key together with the certificate signing request. The PFX file holds the private key. After the import, Neologik copies the certificate, with the private key, into Neologik's central Key Vault |
| Server certificate | `.crt` or `.cer` | The certificate authority issues the server certificate in answer to the certificate signing request |
| Certificate authority bundle | `.pem`, `.crt` or `.p7b` | The certificate authority provides the bundle. The bundle holds the intermediate certificates and the root certificate of the certificate authority |

When you do not know which files to request, ask your certificate provider. Ask for the private key, the server certificate and the full intermediate bundle. Ask for PEM format or P7B format.

## Create the PFX file with the script

1. Copy the three files into the `cert` folder of the onboarding kit. Give the files these names:

   | File | Name |
   |---|---|
   | Private key | `private.key` |
   | Server certificate | `server.crt` |
   | Certificate authority bundle | `ca-bundle.pem` |

2. Open PowerShell 7 in the folder of the onboarding kit. Allow the script to run in this session, then run the script:

   ```powershell
   Unblock-File .\Export-NeologikCertificate.ps1
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\Export-NeologikCertificate.ps1
   ```

   To keep your own file names, name each file in the command:

   ```powershell
   .\Export-NeologikCertificate.ps1 -KeyFile cert\mysite.key -CertFile cert\mysite.crt -BundleFile cert\chain.pem
   ```

3. Enter a password for the PFX file when the script asks. Enter the password a second time to confirm. The script hides the characters that you type.

The script then does three things:

1. writes the file `cert\certificate.pfx`
2. checks that the PFX file opens with the password
3. reports the number of certificates in the PFX file

The script shows a warning when the PFX file holds fewer than two certificates. Fewer than two certificates means that the certificate chain is incomplete.

### A bundle in P7B format

Name the P7B file with the parameter `-BundleFile`. The script converts the P7B file to PEM format.

A P7B file from a certificate authority usually holds the server certificate first. For that reason, the script removes the first certificate when the P7B file holds more than one certificate.

When your P7B file holds only the certificates of the certificate authority, convert the P7B file to PEM format yourself. [Prepare the files](#2-prepare-the-files) shows the command. Then name the PEM file with the parameter `-BundleFile`.

### OpenSSL

The script uses OpenSSL. When OpenSSL is not installed, the script installs OpenSSL with `winget`. The script accepts the package agreement and the source agreement of `winget` for you.

To install OpenSSL yourself before the run, follow [Install OpenSSL](#1-install-openssl).

## Import the PFX file into the Key Vault

1. In the Azure portal, open the Key Vault of the environment. The completion summary of the onboarding script shows the name of the Key Vault.
2. Select **Certificates**, then **Generate/Import**.
3. Select **Import** and enter these values:

   | Field | Value |
   |---|---|
   | Certificate name | `keyvault-neo-ingress` |
   | Upload certificate file | The `.pfx` file |
   | Password | The password of the PFX file |

4. Select **Create**.

The Key Vault uses the password for the import only and does not store the password.

Neologik then copies the certificate, private key included, from the Key Vault of the environment into Neologik's central Key Vault. Each deployment of the ingress reads the certificate from Neologik's central Key Vault. Azure role-based access control protects Neologik's central Key Vault.

After the import, keep the PFX file and the password in a secure place, or delete the PFX file.

When you cannot import the PFX file into the Key Vault, follow [The TLS certificate](TECHNICAL-REFERENCE.md#the-tls-certificate) in the technical reference. That section describes how to upload the certificate files to the deployment storage account.

## Create the PFX file by hand

Follow these steps in two cases:

- you prefer not to run the script
- the script rejects a file and you want to find the reason

### 1. Install OpenSSL

1. Download OpenSSL for Windows from https://slproweb.com/products/Win32OpenSSL.html. The edition "Win64 OpenSSL Light" is enough.
2. Run the OpenSSL installer and accept the default settings.
3. Open a new PowerShell window and confirm the installation:

   ```powershell
   openssl version
   ```

### 2. Prepare the files

Copy the three files into the `cert` folder. Open PowerShell in the `cert` folder.

**When the bundle is in P7B format**, convert the bundle to PEM format:

```powershell
openssl pkcs7 -print_certs -in ca-bundle.p7b -out ca-bundle.pem
```

Some bundles also hold the server certificate. The PFX file must hold the server certificate once only. List the certificates in the bundle:

```powershell
openssl pkcs7 -print_certs -in ca-bundle.p7b | Select-String "subject="
```

When the list shows the server certificate first, remove the first certificate from the converted bundle:

```powershell
$content = Get-Content ca-bundle.pem -Raw
$certs = $content -split '(?=-----BEGIN CERTIFICATE-----)' | Where-Object { $_ -match 'BEGIN CERTIFICATE' }
$certs[1..($certs.Count - 1)] -join '' | Set-Content ca-bundle.pem
```

**When the private key file also holds the certificate signing request**, write the private key to a separate file:

```powershell
openssl rsa -in private.key -out private-clean.key
```

The file `private-clean.key` holds the private key without encryption. Delete `private-clean.key` after you create the PFX file.

### 3. Create the PFX file

```powershell
openssl pkcs12 -export -out certificate.pfx `
  -inkey private.key `
  -in server.crt `
  -certfile ca-bundle.pem `
  -keypbe PBE-SHA1-3DES `
  -certpbe PBE-SHA1-3DES `
  -maciter
```

OpenSSL asks for the password of the PFX file twice. When you created `private-clean.key` in the previous step, replace `private.key` with `private-clean.key` in the command.

The options `-keypbe` and `-certpbe` select encryption algorithms that the import into Azure Key Vault accepts. The PFX file is only a container for the transfer to the Key Vault. After the import, the Key Vault protects the certificate and the private key with the encryption of the Key Vault.

### 4. Check the PFX file

Confirm that the PFX file opens:

```powershell
openssl pkcs12 -in certificate.pfx -noout
```

OpenSSL asks for the password. When OpenSSL prints nothing further, the PFX file is valid.

List the certificates in the PFX file:

```powershell
openssl pkcs12 -in certificate.pfx -nokeys | Select-String "subject="
```

The list shows the server certificate first, then each intermediate certificate. The list also shows the root certificate when the bundle holds the root certificate.

## Troubleshooting

| Message or symptom | Cause | Action |
|---|---|---|
| The script reports "Not found" for a file | The file is not in the `cert` folder under the expected name | Rename the file, or name the file in the command |
| "Passwords do not match" | The two passwords that you entered were different | Run the script again |
| "PFX was not created" | The private key and the server certificate do not belong together, or a file is not in PEM format | Check that the private key is the private key from the certificate signing request for this server certificate |
| The script warns that the certificate chain is incomplete | The bundle does not hold the intermediate certificates | Ask your certificate provider for the full bundle |
| OpenSSL reports "Unable to load private key" | The private key file also holds the certificate signing request | Write the private key to a separate file, as described in [Prepare the files](#2-prepare-the-files) |
| The Key Vault refuses the PFX file | The PFX file uses other encryption options, or the password is wrong | Create the PFX file again with the script, or with the options in [Create the PFX file](#3-create-the-pfx-file) |
| The browser reports a certificate error after the deployment | The TLS certificate is for another host name, or the certificate chain is incomplete | Check the names on the TLS certificate. Check the certificates in the PFX file, as described in [Check the PFX file](#4-check-the-pfx-file) |
