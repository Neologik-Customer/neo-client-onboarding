# How to Create a PFX Certificate File on Windows

This guide will help you create a PFX (PKCS#12) certificate file using OpenSSL on Windows.

## Background

### What You Need

Before starting, gather these files from your certificate provider:

1. **Private Key** (`.key` file) - Generated when you created the Certificate Signing Request (CSR)
2. **Server Certificate** (`.crt` or `.cer` file) - Received from your certificate authority
3. **Certificate Chain/Bundle** (`.p7b`, `.pem`, or `.crt` file) - Contains intermediate and root CA certificates

### What these files are for

Your Neologik deployment is accessed over HTTPS at the hostname you registered (e.g. `neologik.contoso.com`). For that to work, the platform needs a TLS certificate that proves to browsers and clients that the server is genuine. That certificate must be issued by a trusted Certificate Authority (CA) — typically whoever manages your organisation's domain certificates (e.g. DigiCert, Sectigo, Let's Encrypt, or your DNS/hosting provider).

When you request a certificate from a CA, you generate a **Certificate Signing Request (CSR)** on your end. The CA signs it and sends back your **server certificate**. Alongside that, you keep the **private key** you generated with the CSR — it never leaves your control. The CA also provides a **bundle** of their own intermediate and root certificates, which browsers use to verify the chain of trust back to a known root.

The Neologik deployment requires all three combined into a single **PFX file** (also called PKCS#12). The script below handles that combination automatically.

**Where to find your files — common providers:**

| Provider | Where to download |
|----------|------------------|
| DigiCert | Certificate Centre → Orders → Download → "As separate files" |
| Sectigo / Comodo | Your order confirmation email, or portal → Certificates |
| GoDaddy | My Products → SSL Certificates → Manage → Download → "Other" format |
| Let's Encrypt (Certbot) | `/etc/letsencrypt/live/<domain>/` — `privkey.pem` (key), `cert.pem` (server cert), `chain.pem` (bundle) |
| Azure App Service Certificates | Export from Key Vault as PFX — skip this guide entirely |
| Internal / corporate CA | Contact your IT/PKI team; ask for the private key, end-entity cert, and full chain |

If you are unsure which files to use, ask your certificate provider for: *"the private key, the server/end-entity certificate, and the full intermediate CA bundle, in PEM or P7B format."*

# Using the Script (Recommended)

`Export-NeologikCertificate.ps1` automates the steps below. If you prefer to run it manually or need to troubleshoot, skip to [Manual Steps](#manual-steps).

1. Copy your private key, server certificate, and CA bundle into the `cert\` folder alongside this script.
   - Rename them to `private.key`, `server.crt`, and `ca-bundle.pem` (or pass the actual filenames as parameters — see below).
2. Open PowerShell in the repository root and run:
   ```powershell
   .\Export-NeologikCertificate.ps1
   ```
   The script will install OpenSSL automatically if it is not already present, prompt you to set a password, and output `cert\keyvault-neo-ingress.pfx`.
3. Upload `cert\keyvault-neo-ingress.pfx` to your Azure Key Vault as a certificate named `keyvault-neo-ingress`. In the Azure Portal, navigate to your Key Vault → Certificates → Generate/Import, select "Import", and upload the file.
4. Store the PFX password securely (e.g. in your organisation's password manager). **Do not send the PFX file or its password to Neologik.**

**Custom file names:**
```powershell
.\Export-NeologikCertificate.ps1 -KeyFile cert\mysite.key -CertFile cert\mysite.crt -BundleFile cert\chain.pem
```

---

## Manual Steps

### Step 1: Install OpenSSL

1. Download OpenSSL for Windows from: https://slproweb.com/products/Win32OpenSSL.html
2. Choose "Win64 OpenSSL v3.x.x Light" (recommended)
3. Run the installer and accept defaults
4. When prompted, select "The OpenSSL binaries (/bin) directory"

**Verify Installation:**
```powershell
openssl version
```
You should see something like: `OpenSSL 3.x.x`

### Step 2: Organize Your Files

Copy your certificate files to `cert`:
- Your private key (e.g., `private.key`)
- Your server certificate (e.g., `server.crt`)
- Your CA bundle (e.g., `ca-bundle.pem` or `ca-bundle.p7b`)

Open a new PowerShell window in the `cert` folder.

### Step 3: Prepare the Certificate Chain

#### If you have a .p7b file:

Extract the certificates from the bundle:
```powershell
openssl pkcs7 -print_certs -in ca-bundle.p7b -out ca-bundle.pem
```

**Important:** The .p7b file might include your server certificate. You need to remove it to avoid duplicates.

Check what's in the bundle:
```powershell
openssl pkcs7 -print_certs -in ca-bundle.p7b | Select-String "subject="
```

If you see your server certificate listed, extract only the CA certificates:
```powershell
# Extract all certificates
openssl pkcs7 -print_certs -in ca-bundle.p7b -out all-certs.pem

# Remove the first certificate (server cert) and keep only CA certificates
$content = Get-Content all-certs.pem -Raw
$certs = $content -split '(?=-----BEGIN CERTIFICATE-----)' | Where-Object {$_ -match 'BEGIN CERTIFICATE'}
$certs[1..($certs.Count-1)] -join '' | Set-Content ca-bundle.pem
```

#### If your private key file has extra content:

Some private key files contain both a CSR and the private key. You need only the key:

```powershell
openssl rsa -in private.key -out private-clean.key
```

### Step 4: Create the PFX File

Now create the PFX file using this command:

```powershell
openssl pkcs12 -export -out keyvault-neo-ingress.pfx `
  -inkey private-clean.key `
  -in server.crt `
  -certfile ca-bundle.pem `
  -passout pass:YourPasswordHere `
  -keypbe PBE-SHA1-3DES `
  -certpbe PBE-SHA1-3DES `
  -maciter
```

**Replace:**
- `private-clean.key` - Your private key file name
- `server.crt` - Your server certificate file name
- `ca-bundle.pem` - Your CA bundle file name
- `YourPasswordHere` - Choose a strong password for the PFX

**Note:** The `-keypbe` and `-certpbe` options use legacy encryption required by Azure Key Vault.

### Step 5: Verify the PFX File

Check the PFX file is valid:
```powershell
openssl pkcs12 -in keyvault-neo-ingress.pfx -passin pass:YourPasswordHere -noout
```

No output means it's valid!

Count the certificates (should be 3+):
```powershell
(openssl pkcs12 -in keyvault-neo-ingress.pfx -passin pass:YourPasswordHere -nokeys 2>&1 | Select-String "BEGIN CERTIFICATE").Count
```

Check what certificates are included:
```powershell
openssl pkcs12 -in keyvault-neo-ingress.pfx -passin pass:YourPasswordHere -nokeys 2>&1 | Select-String "subject="
```

You should see:
- Your server certificate (e.g., `CN=*.yourdomain.com`)
- Intermediate CA certificate(s)
- Root CA certificate

### Common Issues

#### "More than one certificate with private key found"
- Your CA bundle includes your server certificate
- Follow Step 3 to remove the duplicate server certificate

#### "Unable to load private key"
- Your private key file contains a CSR section
- Extract just the key using: `openssl rsa -in private.key -out private-clean.key`

#### "Certificate chain incomplete"
- You're missing the intermediate or root CA certificates
- Get the full CA bundle from your certificate provider

#### "Bad password" errors
- Make sure your password doesn't contain special characters that PowerShell interprets
- Try wrapping the password in single quotes: `-passout pass:'YourPasswordHere'`

### Quick Reference Command

Once you have all files prepared, this single command creates the PFX:

```powershell
openssl pkcs12 -export -out keyvault-neo-ingress.pfx -inkey private.key -in server.crt -certfile ca-bundle.pem -passout pass:YourPassword -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -maciter
```

## Summary

A PFX file combines:
- ✅ Private key (keeps your certificate secure)
- ✅ Server certificate (proves your domain identity)
- ✅ Certificate chain (proves your certificate authority is trusted)

Store your PFX file securely - it contains your private key!
