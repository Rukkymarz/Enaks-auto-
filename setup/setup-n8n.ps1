# setup-n8n.ps1 — install pinned n8n, pull audited workflows from GitHub, import them (all OFF).
# Run: powershell -ExecutionPolicy Bypass -File .\setup\setup-n8n.ps1
# Safe to re-run: workflows have fixed IDs, so re-import updates them in place (and switches them OFF again).
$ErrorActionPreference = "Stop"
$N8nVersion = "2.48.6"                       # pinned; change deliberately
$Repo       = "$HOME\Documents\Enaks-auto"
function Run($exe,[string[]]$a){ & $exe @a; if($LASTEXITCODE -ne 0){ throw "$exe $($a -join ' ') failed ($LASTEXITCODE)" } }

# 1. Prereqs
$nv = (node -v); Write-Host "node $nv"
if($nv -notmatch '^v(2[4-9]|[3-9]\d)\.'){ throw "n8n $N8nVersion needs Node 24+ (have $nv). Install Node 24 LTS from nodejs.org first." }
Run git @('--version')

# 2. Install n8n (pinned)
$have = (& n8n --version 2>$null)
if($have -ne $N8nVersion){ Run npm @('install','-g',"n8n@$N8nVersion",'--no-audit','--no-fund') }
Write-Host "n8n $(& n8n --version)"

# 3. Get workflows from GitHub (source of truth)
if(Test-Path "$Repo\.git"){ Run git @('-C',$Repo,'pull','--ff-only','-q') }
else { Run git @('clone','-q','https://github.com/Rukkymarz/Enaks-auto-',$Repo) }
Write-Host "workflows @ $(& git -C $Repo rev-parse --short HEAD)"

# 4. Audit gate (same check as GitHub Actions); refuse to import if anything is blocked
$py = @('python','py') | ? { Get-Command $_ -EA SilentlyContinue } | select -First 1
if($py){ & $py -I "$Repo\tools\n8n_audit.py" "$Repo\workflows"; if($LASTEXITCODE -ne 0){ throw "Audit blocked a workflow - not importing." } }
else { Write-Host "python not found - relying on the GitHub Actions audit result" -ForegroundColor Yellow }

# 5. Hardened environment, then import (workflows arrive switched OFF)
. "$Repo\setup\n8n-env.ps1"
Run n8n @('import:workflow','--separate',"--input=$Repo\workflows")
Write-Host "`nImported. Start n8n with:  powershell -ExecutionPolicy Bypass -File `"$Repo\setup\start-n8n.ps1`"" -ForegroundColor Green
Write-Host "Then open http://localhost:5678 , create your owner account, add credentials, and test each workflow manually before activating."
