# ====================================================================================
# CORTEX CMMS API — PowerShell curl Test Suite
# Usage: .\cortex_curl_tests.ps1
# ====================================================================================

$BASE = "https://cortex-api.onrender.com/api"
# $BASE   = "http://localhost:8000/api"    # local

$SUBDOMAIN = "acme"
$EMAIL = "admin@cortex.com"
$PASS = "password123"

function ShowPass($m) { Write-Host "  [PASS] $m" -ForegroundColor Green }
function ShowFail($m) { Write-Host "  [FAIL] $m" -ForegroundColor Red }
function ShowSkip($m) { Write-Host "  [SKIP] $m" -ForegroundColor Yellow }
function ShowHead($t) { Write-Host ("`n=== " + $t + " ===") -ForegroundColor Cyan }

function CurlStatus {
    param($Method, $Url, $Token, $Json)
    $a = [System.Collections.Generic.List[string]]::new()
    $a.AddRange([string[]]@("-s", "-o", "NUL", "-w", "%{http_code}", "-X", $Method, $Url, "-H", "Accept: application/json"))
    if ($Token) { $a.AddRange([string[]]@("-H", "Authorization: Bearer $Token")) }
    if ($Json) { $a.AddRange([string[]]@("-H", "Content-Type: application/json", "-d", $Json)) }
    return [int](& curl.exe ($a.ToArray()))
}

function CurlBody {
    param($Method, $Url, $Token, $Json)
    $tmp = [System.IO.Path]::GetTempFileName()
    $a = [System.Collections.Generic.List[string]]::new()
    $a.AddRange([string[]]@("-s", "-o", $tmp, "-X", $Method, $Url, "-H", "Accept: application/json"))
    if ($Token) { $a.AddRange([string[]]@("-H", "Authorization: Bearer $Token")) }
    if ($Json) { $a.AddRange([string[]]@("-H", "Content-Type: application/json", "-d", $Json)) }
    & curl.exe ($a.ToArray()) | Out-Null
    $r = Get-Content -Raw $tmp
    Remove-Item $tmp -Force
    return $r
}

function Chk {
    param($Label, $Got, $Want = 200)
    if ($Got -eq $Want) { ShowPass "$Label (HTTP $Got)" } else { ShowFail "$Label — expected $Want got $Got" }
}

$TOKEN = $null
$TENANT_ID = $null

# ─── HEALTH ──────────────────────────────────────────────────────────────────────────
ShowHead "HEALTH CHECK"
Chk "Health" (CurlStatus -Method GET -Url "$BASE/health")

# ─── LOGIN ───────────────────────────────────────────────────────────────────────────
ShowHead "AUTH — Login"
$loginJson = '{"email":"' + $EMAIL + '","password":"' + $PASS + '","subdomain":"' + $SUBDOMAIN + '"}'
$loginRaw = CurlBody -Method POST -Url "$BASE/auth/login" -Json $loginJson
try {
    $j = $loginRaw | ConvertFrom-Json
    $TOKEN = $j.data.token
    $TENANT_ID = $j.data.tenant.id
    ShowPass ("Token: " + $TOKEN.Substring(0, 20) + "...")
    ShowPass "Tenant ID: $TENANT_ID"
}
catch {
    ShowFail "Login failed. Response: $loginRaw"
    exit 1
}

# ─── ME ──────────────────────────────────────────────────────────────────────────────
ShowHead "AUTH — Me"
Chk "GET /auth/me" (CurlStatus -Method GET -Url "$BASE/auth/me" -Token $TOKEN)

# ─── ASSETS ──────────────────────────────────────────────────────────────────────────
ShowHead "ASSETS"
Chk "List assets" (CurlStatus -Method GET -Url "$BASE/assets?per_page=5" -Token $TOKEN)

$f = $BASE + "/assets?status=Operational&criticality=High"
Chk "Filter Operational+High" (CurlStatus -Method GET -Url $f -Token $TOKEN)

$cA = '{"name":"PS Test Pump","tag_number":"PS-CURL-001","asset_type_id":1,"location_id":1,"status":"Operational","criticality":"High"}'
$createAssetRaw = CurlBody -Method POST -Url "$BASE/assets" -Token $TOKEN -Json $cA
Chk "Create asset" (CurlStatus -Method POST -Url "$BASE/assets" -Token $TOKEN -Json $cA) -Want 201

try {
    $AID = ($createAssetRaw | ConvertFrom-Json).data.asset_id
    if ($null -ne $AID) {
        Chk "Get asset"    (CurlStatus -Method GET    -Url "$BASE/assets/$AID"                       -Token $TOKEN)
        Chk "Update asset" (CurlStatus -Method PUT    -Url "$BASE/assets/$AID" -Token $TOKEN -Json '{"status":"Maintenance"}')
        Chk "Delete asset" (CurlStatus -Method DELETE -Url "$BASE/assets/$AID"                       -Token $TOKEN)
    }
}
catch { ShowSkip "asset_id parse" }

# ─── ASSET KPIs ──────────────────────────────────────────────────────────────────────
ShowHead "ASSET KPIs (id=1)"
foreach ($ep in @("kpis", "mttr", "mtbf", "availability")) {
    Chk "GET /assets/1/$ep" (CurlStatus -Method GET -Url "$BASE/assets/1/$ep" -Token $TOKEN)
}

# ─── WORK ORDERS ─────────────────────────────────────────────────────────────────────
ShowHead "WORK ORDERS"
Chk "List WOs" (CurlStatus -Method GET -Url "$BASE/work-orders?per_page=5" -Token $TOKEN)

$cWO = '{"title":"curl Test WO","type":"Corrective","asset_id":1,"location_id":1,"priority":"Medium","status":"Open"}'
$createWoRaw = CurlBody -Method POST -Url "$BASE/work-orders" -Token $TOKEN -Json $cWO
Chk "Create WO" (CurlStatus -Method POST -Url "$BASE/work-orders" -Token $TOKEN -Json $cWO) -Want 201

try {
    $WID = ($createWoRaw | ConvertFrom-Json).data.wo_id
    if ($null -ne $WID) {
        Chk "Start WO"    (CurlStatus -Method POST   -Url "$BASE/work-orders/$WID/start"    -Token $TOKEN)
        Chk "Complete WO" (CurlStatus -Method POST   -Url "$BASE/work-orders/$WID/complete" -Token $TOKEN -Json '{"labor_cost":100,"material_cost":50}')
        Chk "Delete WO"   (CurlStatus -Method DELETE -Url "$BASE/work-orders/$WID"          -Token $TOKEN)
    }
}
catch { ShowSkip "wo_id parse" }

# ─── KPI DASHBOARD ───────────────────────────────────────────────────────────────────
ShowHead "KPI DASHBOARD"
foreach ($ep in @("summary", "critical", "top-performers", "by-type", "attention-needed")) {
    Chk "GET /kpis/$ep" (CurlStatus -Method GET -Url "$BASE/kpis/$ep" -Token $TOKEN)
}

# ─── CALENDAR ────────────────────────────────────────────────────────────────────────
ShowHead "CALENDAR"
$ce = $BASE + "/calendar/events?start=2025-01-01&end=2025-12-31"
Chk "GET calendar/events" (CurlStatus -Method GET -Url $ce -Token $TOKEN)
foreach ($ep in @("pm/unscheduled", "pm/overdue")) {
    Chk "GET calendar/$ep" (CurlStatus -Method GET -Url "$BASE/calendar/$ep" -Token $TOKEN)
}

# ─── BACKLOG ─────────────────────────────────────────────────────────────────────────
ShowHead "BACKLOG"
foreach ($ep in @("summary", "work-orders", "pm", "by-priority", "by-asset", "aging", "trend")) {
    Chk "GET /backlog/$ep" (CurlStatus -Method GET -Url "$BASE/backlog/$ep" -Token $TOKEN)
}

# ─── LOGOUT ──────────────────────────────────────────────────────────────────────────
ShowHead "LOGOUT"
Chk "POST /auth/logout" (CurlStatus -Method POST -Url "$BASE/auth/logout" -Token $TOKEN)

Write-Host "`n===========================================" -ForegroundColor Cyan
Write-Host "All tests done!" -ForegroundColor Green
