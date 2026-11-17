<#
.SYNOPSIS
  Creates an OWNER login (phone + 6-digit PIN) using the service-role key. Run once per owner.
  Talks to the Auth admin API and REST directly (same result as manage-login's create_owner).
.EXAMPLE
  .\scripts\create-owner.ps1 -Url https://abcd.supabase.co -ServiceKey $env:SUPABASE_SERVICE_ROLE_KEY -Name "Papa" -Phone 98xxxxxxxx
#>
param(
  [Parameter(Mandatory)] [string] $Url,
  [Parameter(Mandatory)] [string] $ServiceKey,
  [Parameter(Mandatory)] [string] $Name,
  [Parameter(Mandatory)] [string] $Phone,
  [securestring] $Pin
)
$ErrorActionPreference = 'Stop'
if (-not $Pin) { $Pin = Read-Host -AsSecureString 'New 6-digit PIN' }
$plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Pin))
if ($plain -notmatch '^\d{6}$') { throw 'PIN must be exactly 6 digits' }
$digits = $Phone -replace '\D', ''
if ($digits.Length -gt 10) { $digits = $digits.Substring($digits.Length - 10) }
if ($digits.Length -ne 10) { throw 'A 10-digit mobile number is needed' }

$base = $Url.TrimEnd('/')
$h = @{ Authorization = "Bearer $ServiceKey"; apikey = $ServiceKey }
$property = Invoke-RestMethod -Uri "$base/rest/v1/property?select=id&order=created_at&limit=1" -Headers $h
if (-not $property) { throw 'No property row found - apply the seed first' }

# Must match phoneToEmail() in supabase/functions/manage-login/index.ts
$user = Invoke-RestMethod -Method Post -Uri "$base/auth/v1/admin/users" -Headers $h -ContentType 'application/json' -Body (@{
  email = "p$digits@login.kiraya.app"; password = $plain; email_confirm = $true; user_metadata = @{ phone = $digits }
} | ConvertTo-Json)
try {
  Invoke-RestMethod -Method Post -Uri "$base/rest/v1/app_user" -Headers ($h + @{ Prefer = 'return=minimal' }) -ContentType 'application/json' -Body (@{
    id = $user.id; property_id = $property[0].id; role = 'OWNER'; name = $Name; phone = $digits
  } | ConvertTo-Json) | Out-Null
} catch {
  Invoke-RestMethod -Method Delete -Uri "$base/auth/v1/admin/users/$($user.id)" -Headers $h | Out-Null
  throw
}
[pscustomobject]@{ ok = $true; user_id = $user.id; phone = $digits } | ConvertTo-Json
