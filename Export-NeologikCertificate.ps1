<#
.SYNOPSIS
    Creates a PFX certificate file for Neologik deployment.

.DESCRIPTION
    Combines a private key, server certificate, and CA bundle into a PFX file
    ready for upload to Azure Key Vault. Expects input files in the cert\ subfolder.

.PARAMETER KeyFile
    Path to the private key file. Defaults to cert\private.key.

.PARAMETER CertFile
    Path to the server certificate file. Defaults to cert\server.crt.

.PARAMETER BundleFile
    Path to the CA bundle file (.pem or .p7b). Defaults to cert\ca-bundle.pem.

.PARAMETER OutFile
    Output PFX path. Defaults to cert\certificate.pfx.

.PARAMETER Password
    Password to protect the PFX. Prompted securely if not provided.

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

# ── OpenSSL install (if missing) ─────────────────────────────────────────────
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
    Write-Host "    OpenSSL not found — attempting install via winget..." -ForegroundColor Yellow
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install --id ShiningLight.OpenSSL.Light --silent --accept-package-agreements --accept-source-agreements
        # Refresh PATH for the current session
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

# ── Resolve input files ───────────────────────────────────────────────────────
Write-Step "Checking input files"
foreach ($f in @($KeyFile, $CertFile, $BundleFile)) {
    if (-not (Test-Path $f)) {
        Write-Fail "Not found: $f — drop your files in the cert\ folder and re-run."
        exit 1
    }
    Write-Ok "Found: $f"
}

# ── Password ──────────────────────────────────────────────────────────────────
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

# ── Convert .p7b bundle to .pem if needed ────────────────────────────────────
$resolvedBundle = $BundleFile
if ($BundleFile -match '\.p7b$') {
    Write-Step "Converting .p7b bundle to .pem"
    $pemBundle = [IO.Path]::ChangeExtension($BundleFile, '.pem')
    & openssl pkcs7 -print_certs -in $BundleFile -out $pemBundle 2>&1 | Out-Null

    # If the bundle contains the server cert, strip the first entry
    $subjects = (& openssl pkcs7 -print_certs -in $BundleFile 2>&1 | Select-String "subject=").Count
    if ($subjects -gt 1) {
        Write-Host "    Bundle contains server cert — removing duplicate" -ForegroundColor Yellow
        $content = Get-Content $pemBundle -Raw
        $certs   = $content -split '(?=-----BEGIN CERTIFICATE-----)' | Where-Object { $_ -match 'BEGIN CERTIFICATE' }
        ($certs[1..($certs.Count - 1)] -join '') | Set-Content $pemBundle
    }
    $resolvedBundle = $pemBundle
    Write-Ok "Bundle ready: $resolvedBundle"
}

# ── Clean private key (strip any CSR section) ─────────────────────────────────
Write-Step "Preparing private key"
$cleanKey = [IO.Path]::Combine([IO.Path]::GetDirectoryName($KeyFile), "private-clean.key")
& openssl rsa -in $KeyFile -out $cleanKey 2>&1 | Out-Null
if (-not (Test-Path $cleanKey)) {
    Write-Fail "Could not extract private key from $KeyFile"
    exit 1
}
Write-Ok "Key ready: $cleanKey"

# ── Build PFX ────────────────────────────────────────────────────────────────
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

# ── Verify ───────────────────────────────────────────────────────────────────
Write-Step "Verifying PFX"
$verify = & openssl pkcs12 -in $OutFile -passin "pass:$p1" -noout 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "PFX verification failed: $verify"
    exit 1
}

$certCount = (& openssl pkcs12 -in $OutFile -passin "pass:$p1" -nokeys 2>&1 | Select-String "BEGIN CERTIFICATE").Count
Write-Ok "PFX valid — $certCount certificate(s) included"

if ($certCount -lt 2) {
    Write-Host "    WARNING: expected at least 2 certificates (server + CA). Chain may be incomplete." -ForegroundColor Yellow
}

# ── Clean up intermediate files ───────────────────────────────────────────────
Remove-Item $cleanKey -ErrorAction SilentlyContinue
if ($resolvedBundle -ne $BundleFile) {
    Remove-Item $resolvedBundle -ErrorAction SilentlyContinue
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "PFX created: $OutFile" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: upload $OutFile and its password to your Azure Key Vault with the name ''keyvault-neo-ingress''." -ForegroundColor Cyan
Write-Host "Do NOT send the PFX file or password to Neologik." -ForegroundColor Yellow
