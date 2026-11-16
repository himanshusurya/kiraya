<#
.SYNOPSIS
  Creates an OWNER login (phone + 6-digit PIN) using the service-role key. Run once per owner.
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

$body = @{ action = 'create_owner'; name = $Name; phone = $Phone; pin = $plain } | ConvertTo-Json
$res = Invoke-RestMethod -Method Post -Uri "$($Url.TrimEnd('/'))/functions/v1/manage-login" `
  -Headers @{ Authorization = "Bearer $ServiceKey"; apikey = $ServiceKey } -ContentType 'application/json' -Body $body
$res | ConvertTo-Json
