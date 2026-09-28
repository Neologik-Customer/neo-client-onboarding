<#
.SYNOPSIS
    Builds the PFX file of the TLS certificate for a Neologik Platform environment.

.DESCRIPTION
    The script builds one PFX file from three files: a private key, a server
    certificate and a certificate authority bundle. A password protects the PFX file.
    An administrator then imports the PFX file into the Azure Key Vault of the
    environment.

    The script runs on the workstation with OpenSSL. The script signs in to no service
    and sends nothing.

    Run the script from the folder of the onboarding kit. Each default path starts
    from the current folder.

.PARAMETER KeyFile
    The private key, in PEM format. Default: cert\private.key.

.PARAMETER CertFile
    The server certificate, in PEM format. Default: cert\server.crt.

.PARAMETER BundleFile
    The certificate authority bundle, in PEM format or P7B format. Default:
    cert\ca-bundle.pem.

.PARAMETER OutFile
    The PFX file that the script writes. Default: cert\certificate.pfx.

.PARAMETER Password
    The password of the PFX file, as a secure string. Without this parameter, the
    script asks for the password.

.EXAMPLE
    .\Export-NeologikCertificate.ps1

.EXAMPLE
    .\Export-NeologikCertificate.ps1 -KeyFile cert\mysite.key -CertFile cert\mysite.crt -BundleFile cert\chain.pem

.NOTES
    Version: 1.1
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

# -- Install OpenSSL when OpenSSL is absent -----------------------------------
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
    Write-Host "    OpenSSL is not installed. The script now installs OpenSSL with winget..." -ForegroundColor Yellow
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
        Write-Fail "The script could not install OpenSSL."
        Write-Host "    Install OpenSSL yourself from https://slproweb.com/products/Win32OpenSSL.html. The edition Win64 OpenSSL Light is enough." -ForegroundColor Yellow
        Write-Host "    Then run this script again." -ForegroundColor Yellow
        exit 1
    }
}

# -- Check the input files ----------------------------------------------------
Write-Step "Checking the input files"
foreach ($f in @($KeyFile, $CertFile, $BundleFile)) {
    if (-not (Test-Path $f)) {
        Write-Fail "Not found: $f. Copy the file into the cert\ folder and run the script again."
        exit 1
    }
    Write-Ok "Found: $f"
}

# -- Password -----------------------------------------------------------------
if (-not $Password) {
    $Password = Read-Host "Enter the password of the PFX file" -AsSecureString
    $confirm  = Read-Host "Enter the password of the PFX file again" -AsSecureString
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
    $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirm))
    if ($p1 -ne $p2) {
        Write-Fail "Passwords do not match."
        exit 1
    }
} else {
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
}

# -- Convert a P7B bundle to PEM, prepare the key, build and check the PFX file --
# The finally block deletes the temporary files after success and after a failure, so
# that the private key without encryption never stays on disk.
$resolvedBundle = $BundleFile
$cleanKey = [IO.Path]::Combine([IO.Path]::GetDirectoryName($KeyFile), "private-clean.key")
try {
    if ($BundleFile -match '\.p7b$') {
        Write-Step "Converting the P7B bundle to PEM format"
        $pemBundle = [IO.Path]::ChangeExtension($BundleFile, '.pem')
        & openssl pkcs7 -print_certs -in $BundleFile -out $pemBundle 2>&1 | Out-Null

        # A P7B file from a certificate authority usually holds the server certificate first.
        # The script removes the first certificate when the bundle holds more than one certificate.
        $subjects = (& openssl pkcs7 -print_certs -in $BundleFile 2>&1 | Select-String "subject=").Count
        if ($subjects -gt 1) {
            Write-Host "    The bundle holds more than one certificate. The script removes the first certificate, which is the server certificate." -ForegroundColor Yellow
            $content = Get-Content $pemBundle -Raw
            $certs   = $content -split '(?=-----BEGIN CERTIFICATE-----)' | Where-Object { $_ -match 'BEGIN CERTIFICATE' }
            ($certs[1..($certs.Count - 1)] -join '') | Set-Content $pemBundle
        }
        $resolvedBundle = $pemBundle
        Write-Ok "Bundle ready: $resolvedBundle"
    }

    # -- Write the private key without the certificate signing request --------
    Write-Step "Preparing the private key"
    & openssl rsa -in $KeyFile -out $cleanKey 2>&1 | Out-Null
    if (-not (Test-Path $cleanKey)) {
        Write-Fail "The script could not read the private key from $KeyFile"
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
        Write-Fail "PFX was not created. Check the private key, the server certificate and the certificate authority bundle."
        exit 1
    }

    # -- Check the PFX file -------------------------------------------------------
    Write-Step "Verifying PFX"
    $verify = & openssl pkcs12 -in $OutFile -passin "pass:$p1" -noout 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "The check of the PFX file failed: $verify"
        exit 1
    }

    $certCount = (& openssl pkcs12 -in $OutFile -passin "pass:$p1" -nokeys 2>&1 | Select-String "BEGIN CERTIFICATE").Count
    Write-Ok "The PFX file is valid. Number of certificates in the PFX file: $certCount"

    if ($certCount -lt 2) {
        Write-Host "    Warning: the script expected at least 2 certificates, the server certificate and one certificate of the certificate authority. The certificate chain may be incomplete." -ForegroundColor Yellow
    }
}
finally {
    # -- Delete the temporary files -------------------------------------------
    Remove-Item $cleanKey -ErrorAction SilentlyContinue
    if ($resolvedBundle -ne $BundleFile) {
        Remove-Item $resolvedBundle -ErrorAction SilentlyContinue
    }
}

# -- Done ---------------------------------------------------------------------
Write-Host ""
Write-Host "PFX file created: $OutFile" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: import $OutFile into the Azure Key Vault of the environment. Name the certificate 'keyvault-neo-ingress'. Enter the password of the PFX file when the import asks." -ForegroundColor Cyan
Write-Host "Do not send the PFX file or the password of the PFX file to Neologik." -ForegroundColor Yellow
