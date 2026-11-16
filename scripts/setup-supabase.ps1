<#
One-shot Supabase setup for Kiraya. Safe to re-run: it reuses an existing "kiraya" project.
  1. creates the project (free plan, Mumbai) with a random DB password
  2. auth: no email confirmation, public sign-up off (logins are created by the owner via manage-login)
  3. pushes migrations + seed, deploys the manage-login edge function
  4. stores URL / keys / DB URL as GitHub repo secrets, and locally in $SecretsDir

Needs a Supabase personal access token: env SUPABASE_ACCESS_TOKEN, or a DPAPI file written by
  Read-Host -AsSecureString | ConvertFrom-SecureString | Set-Content $SecretsDir\supabase-token.dpapi
Usage: .\scripts\setup-supabase.ps1 [-Repo himanshusurya/kiraya] [-GhUser himanshusurya]
#>
param(
  [string] $Repo = 'himanshusurya/kiraya',
  [string] $GhUser = 'himanshusurya',
  [string] $ProjectName = 'kiraya',
  [string] $Region = 'ap-south-1',
  [string] $SecretsDir = "$env:USERPROFILE\Secrets\kiraya",
  [string] $Cli = "$env:USERPROFILE\tools\supabase\supabase.exe"
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$api = 'https://api.supabase.com/v1'

function Get-Plain([securestring] $s) { [Net.NetworkCredential]::new('', $s).Password }
function New-Password([int] $n) {
  $c = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  -join (1..$n | ForEach-Object { $c[[Security.Cryptography.RandomNumberGenerator]::GetInt32($c.Length)] })
}
function Save-Secret([string] $name, [string] $value) {
  # DPAPI (current Windows user only); also used for reruns.
  ConvertTo-SecureString $value -AsPlainText -Force | ConvertFrom-SecureString | Set-Content "$SecretsDir\$name.dpapi"
}
function Read-Secret([string] $name) {
  $f = "$SecretsDir\$name.dpapi"
  if (Test-Path $f) { Get-Plain (Get-Content $f | ConvertTo-SecureString) }
}

$token = $env:SUPABASE_ACCESS_TOKEN
if (-not $token) { $token = Read-Secret 'supabase-token' }
if (-not $token) { throw "No Supabase token. Set SUPABASE_ACCESS_TOKEN or create $SecretsDir\supabase-token.dpapi" }
$h = @{ Authorization = "Bearer $token" }

# 1. Project
$proj = Invoke-RestMethod "$api/projects" -Headers $h | Where-Object name -eq $ProjectName | Select-Object -First 1
$dbPass = Read-Secret 'db-password'
if (-not $proj) {
  $org = Invoke-RestMethod "$api/organizations" -Headers $h | Select-Object -First 1
  if (-not $org) { throw 'No Supabase organization found. Create one in the dashboard first.' }
  $dbPass = New-Password 32; Save-Secret 'db-password' $dbPass
  Write-Host "Creating project '$ProjectName' in $Region (org $($org.name))..."
  $body = @{ name = $ProjectName; organization_id = $org.id; region = $Region; db_pass = $dbPass; plan = 'free' } | ConvertTo-Json
  $proj = Invoke-RestMethod -Method Post "$api/projects" -Headers $h -ContentType 'application/json' -Body $body
}
elseif (-not $dbPass) { throw "Project '$ProjectName' exists but its DB password is not in $SecretsDir\db-password.dpapi. Reset it in the dashboard and save it there." }
$ref = $proj.id
Write-Host "Project ref: $ref - waiting until it is healthy..."
for ($i = 0; $i -lt 90; $i++) {
  $st = (Invoke-RestMethod "$api/projects/$ref" -Headers $h).status
  if ($st -eq 'ACTIVE_HEALTHY') { break }
  Start-Sleep 10
}
if ($st -ne 'ACTIVE_HEALTHY') { throw "Project status is still $st; re-run this script in a few minutes." }

# 2. Auth config
$auth = @{ mailer_autoconfirm = $true; disable_signup = $true } | ConvertTo-Json
Invoke-RestMethod -Method Patch "$api/projects/$ref/config/auth" -Headers $h -ContentType 'application/json' -Body $auth | Out-Null
Write-Host 'Auth: email confirmation off, public sign-up off.'

# 3. Schema, seed, edge function
$env:SUPABASE_ACCESS_TOKEN = $token; $env:SUPABASE_DB_PASSWORD = $dbPass
Push-Location $root
try {
  & $Cli link --project-ref $ref --yes; if ($LASTEXITCODE) { throw 'supabase link failed' }
  & $Cli db push --remote --include-seed --password $dbPass --yes; if ($LASTEXITCODE) { throw 'supabase db push failed' }
  & $Cli functions deploy manage-login --project-ref $ref --use-api --yes; if ($LASTEXITCODE) { throw 'functions deploy failed' }
}
finally { Pop-Location; Remove-Item Env:SUPABASE_DB_PASSWORD -ErrorAction SilentlyContinue }

# 4. Keys and secrets
$keys = Invoke-RestMethod "$api/projects/$ref/api-keys?reveal=true" -Headers $h
$anon = ($keys | Where-Object { $_.name -eq 'anon' } | Select-Object -First 1).api_key
$service = ($keys | Where-Object { $_.name -eq 'service_role' } | Select-Object -First 1).api_key
if (-not $anon) { $anon = ($keys | Where-Object { $_.type -eq 'publishable' } | Select-Object -First 1).api_key }
if (-not $service) { $service = ($keys | Where-Object { $_.type -eq 'secret' } | Select-Object -First 1).api_key }
if (-not $anon -or -not $service) { throw 'Could not read the project API keys.' }
$url = "https://$ref.supabase.co"
# Session pooler (IPv4): GitHub runners have no IPv6, so the direct db.<ref>.supabase.co host would fail.
$pool = Invoke-RestMethod "$api/projects/$ref/config/database/pooler" -Headers $h | Select-Object -First 1
$dbUrl = ($pool.connection_string -replace '\[YOUR-PASSWORD\]', $dbPass) -replace ':6543/', ':5432/'

Save-Secret 'supabase-anon-key' $anon; Save-Secret 'supabase-service-key' $service; Save-Secret 'supabase-db-url' $dbUrl
Set-Content "$SecretsDir\supabase-url.txt" $url

$env:GH_TOKEN = (gh auth token -u $GhUser)
try {
  gh secret set SUPABASE_URL -R $Repo --body $url
  gh secret set SUPABASE_ANON_KEY -R $Repo --body $anon
  gh secret set SUPABASE_SERVICE_ROLE_KEY -R $Repo --body $service
  gh secret set SUPABASE_DB_URL -R $Repo --body $dbUrl
}
finally { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }

# Smoke test: the public API answers with the anon key (RLS returns no rows when not signed in).
$r = Invoke-WebRequest "$url/rest/v1/room?select=id&limit=1" -Headers @{ apikey = $anon } -UseBasicParsing
Write-Host "REST check: HTTP $($r.StatusCode)"
Write-Host ''
Write-Host "Done. URL: $url" -ForegroundColor Green
Write-Host 'Next: .\scripts\create-owner.ps1 -Url <url> -ServiceKey <service key> -Name "Papa" -Phone 98xxxxxxxx'
