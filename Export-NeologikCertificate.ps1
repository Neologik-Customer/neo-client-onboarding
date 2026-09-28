<#
.SYNOPSIS
    Creates the PFX file of the TLS certificate for a Neologik Platform environment.

.DESCRIPTION
    Combines a private key, a server certificate and a certificate authority bundle into
    one password-protected PFX file, ready to import into the environment's Azure Key
    Vault. The script runs on the workstation with OpenSSL. It signs in to nothing and
    sends nothing. Run it from the kit folder: the default paths are relative to the
    current folder.

.PARAMETER KeyFile
    The private key, in PEM format. Default: cert\private.key.

.PARAMETER CertFile
    The server certificate, in PEM format. Default: cert\server.crt.

.PARAMETER BundleFile
    The certificate authority bundle, in PEM or P7B format. Default: cert\ca-bundle.pem.

.PARAMETER OutFile
    The PFX file to write. Default: cert\certificate.pfx.

.PARAMETER Password
    The password of the PFX file, as a secure string. Asked for when omitted.

.EXAMPLE
    .\Export-NeologikCertificate.ps1

.EXAMPLE
    .\Export-NeologikCertificate.ps1 -KeyFile cert\mysite.key -CertFile cert\mysite.crt -BundleFile cert\chain.pem
#>
[CmdletBinding()]
param(
    [string]$KeyFile    = "cert\private.key",
    [string]$CertFile   = "cert\server.crt",
    [string]$BundleFile = "cert\ca-bundle.pem",
    [string]$OutFile    = "cert\certificate.pfx",
    [SecureString]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Fail([string]$msg) { Write-Host "    ERROR: $msg" -ForegroundColor Red }

# -- Install OpenSSL if it is absent ------------------------------------------
Write-Step "Checking OpenSSL"
$opensslOk = $false
try {
    $ver = & openssl version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok $ver
        $opensslOk = $true
    }
} catch { }

if (-not $opensslOk) {
    Write-Host "    OpenSSL not found - attempting install via winget..." -ForegroundColor Yellow
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install --id ShiningLight.OpenSSL.Light --silent --accept-package-agreements --accept-source-agreements
        # Refresh the path of the current session
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [System.Environment]::GetEnvironmentVariable('Path', 'User')
        try {
            $ver = & openssl version 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Installed: $ver"
                $opensslOk = $true
            }
        } catch { }
    }

    if (-not $opensslOk) {
        Write-Fail "Could not install OpenSSL automatically."
        Write-Host "    Please install manually: https://slproweb.com/products/Win32OpenSSL.html (Win64 Light build)" -ForegroundColor Yellow
        Write-Host "    Then re-run this script." -ForegroundColor Yellow
        exit 1
    }
}

# -- Check the input files ----------------------------------------------------
Write-Step "Checking input files"
foreach ($f in @($KeyFile, $CertFile, $BundleFile)) {
    if (-not (Test-Path $f)) {
        Write-Fail "Not found: $f - place your files in the cert\ folder and run the script again."
        exit 1
    }
    Write-Ok "Found: $f"
}

# -- Password -----------------------------------------------------------------
if (-not $Password) {
    $Password = Read-Host "Enter PFX password" -AsSecureString
    $confirm  = Read-Host "Confirm PFX password" -AsSecureString
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
    $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirm))
    if ($p1 -ne $p2) {
        Write-Fail "Passwords do not match."
        exit 1
    }
} else {
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
}

# -- Convert a P7B bundle to PEM ----------------------------------------------
$resolvedBundle = $BundleFile
if ($BundleFile -match '\.p7b$') {
    Write-Step "Converting .p7b bundle to .pem"
    $pemBundle = [IO.Path]::ChangeExtension($BundleFile, '.pem')
    & openssl pkcs7 -print_certs -in $BundleFile -out $pemBundle 2>&1 | Out-Null

    # Where the bundle holds more than one certificate, remove the first: in a P7B
    # file from a certificate authority the first certificate is the server certificate.
    $subjects = (& openssl pkcs7 -print_certs -in $BundleFile 2>&1 | Select-String "subject=").Count
    if ($subjects -gt 1) {
        Write-Host "    The bundle holds more than one certificate - removing the first (the server certificate)" -ForegroundColor Yellow
        $content = Get-Content $pemBundle -Raw
        $certs   = $content -split '(?=-----BEGIN CERTIFICATE-----)' | Where-Object { $_ -match 'BEGIN CERTIFICATE' }
        ($certs[1..($certs.Count - 1)] -join '') | Set-Content $pemBundle
    }
    $resolvedBundle = $pemBundle
    Write-Ok "Bundle ready: $resolvedBundle"
}

# -- Prepare the private key (remove any signing request) ---------------------
Write-Step "Preparing private key"
$cleanKey = [IO.Path]::Combine([IO.Path]::GetDirectoryName($KeyFile), "private-clean.key")
& openssl rsa -in $KeyFile -out $cleanKey 2>&1 | Out-Null
if (-not (Test-Path $cleanKey)) {
    Write-Fail "Could not extract private key from $KeyFile"
    exit 1
}
Write-Ok "Key ready: $cleanKey"

# -- Build the PFX file -------------------------------------------------------
Write-Step "Creating PFX"
& openssl pkcs12 -export `
    -out $OutFile `
    -inkey $cleanKey `
    -in $CertFile `
    -certfile $resolvedBundle `
    -passout "pass:$p1" `
    -keypbe PBE-SHA1-3DES `
    -certpbe PBE-SHA1-3DES `
    -maciter 2>&1 | Out-Null

if (-not (Test-Path $OutFile)) {
    Write-Fail "PFX was not created. Check that your key, cert, and bundle files are correct."
    exit 1
}

# -- Check the PFX file -------------------------------------------------------
Write-Step "Verifying PFX"
$verify = & openssl pkcs12 -in $OutFile -passin "pass:$p1" -noout 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "PFX verification failed: $verify"
    exit 1
}

$certCount = (& openssl pkcs12 -in $OutFile -passin "pass:$p1" -nokeys 2>&1 | Select-String "BEGIN CERTIFICATE").Count
Write-Ok "PFX valid - $certCount certificate(s) included"

if ($certCount -lt 2) {
    Write-Host "    Warning: at least 2 certificates were expected (the server certificate and the certificate authority). The chain may be incomplete." -ForegroundColor Yellow
}

# -- Delete the intermediate files --------------------------------------------
Remove-Item $cleanKey -ErrorAction SilentlyContinue
if ($resolvedBundle -ne $BundleFile) {
    Remove-Item $resolvedBundle -ErrorAction SilentlyContinue
}

# -- Done ---------------------------------------------------------------------
Write-Host ""
Write-Host "PFX created: $OutFile" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: import $OutFile into your Azure Key Vault as a certificate named 'keyvault-neo-ingress'. Enter the password when the import asks for it." -ForegroundColor Cyan
Write-Host "Do not send the PFX file or its password to Neologik." -ForegroundColor Yellow
