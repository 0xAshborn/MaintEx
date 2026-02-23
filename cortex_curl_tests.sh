#!/usr/bin/env bash
# ====================================================================================
# CORTEX CMMS API — curl Test Suite
# Usage: bash cortex_curl_tests.sh
# Requires: curl, jq (brew install jq / apt install jq)
# ====================================================================================

BASE_URL="https://cortex-api.onrender.com/api"
# LOCAL_URL="http://localhost:8000/api"
# BASE_URL=$LOCAL_URL  # uncomment to test locally

SUBDOMAIN="acme"       # ← change to your tenant subdomain
ADMIN_EMAIL="admin@cortex.com"
ADMIN_PASS="password123"

# ─── Colors ──────────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
pass() { echo -e "${GREEN}✅ PASS${NC} — $1"; }
fail() { echo -e "${RED}❌ FAIL${NC} — $1"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ─── Helper ──────────────────────────────────────────────────────────────────────────
check_status() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then pass "$label (HTTP $actual)";
    else fail "$label — expected HTTP $expected, got HTTP $actual"; fi
}

TOKEN=""
TENANT_ID=""

# ====================================================================================
section "HEALTH CHECK"
# ====================================================================================

HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
check_status "Health check" 200 "$HEALTH_STATUS"

HEALTH_BODY=$(curl -s "$BASE_URL/health")
echo "   Response: $HEALTH_BODY"

# ====================================================================================
section "AUTH — Login"
# ====================================================================================

LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{
    \"email\": \"$ADMIN_EMAIL\",
    \"password\": \"$ADMIN_PASS\",
    \"subdomain\": \"$SUBDOMAIN\"
  }")

LOGIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\",\"subdomain\":\"$SUBDOMAIN\"}")

check_status "Login" 200 "$LOGIN_STATUS"

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.token // empty')
TENANT_ID=$(echo "$LOGIN_RESPONSE" | jq -r '.data.tenant.id // empty')

if [ -n "$TOKEN" ]; then
    pass "Token extracted: ${TOKEN:0:20}..."
    pass "Tenant ID: $TENANT_ID"
else
    fail "Could not extract token — check credentials and subdomain"
    echo "   Response: $LOGIN_RESPONSE"
    exit 1
fi

# ====================================================================================
section "AUTH — Get Current User"
# ====================================================================================

ME_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/auth/me" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json")

check_status "Get current user (me)" 200 "$ME_STATUS"

# ====================================================================================
section "ASSETS — CRUD"
# ====================================================================================

# List assets
LIST_ASSETS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/assets?per_page=5" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json")
check_status "List assets" 200 "$LIST_ASSETS_STATUS"

# Create asset
CREATE_ASSET_RESPONSE=$(curl -s -X POST "$BASE_URL/assets" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "name": "Test Pump #99",
    "tag_number": "TEST-PUMP-099",
    "asset_type_id": 1,
    "location_id": 1,
    "status": "Operational",
    "criticality": "High",
    "manufacturer": "Flowserve",
    "model": "PVXM-100"
  }')

CREATE_ASSET_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/assets" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"name":"Test Pump #99","tag_number":"TEST-PUMP-099","asset_type_id":1,"location_id":1,"status":"Operational","criticality":"High"}')

check_status "Create asset" 201 "$CREATE_ASSET_STATUS"

ASSET_ID=$(echo "$CREATE_ASSET_RESPONSE" | jq -r '.data.asset_id // .data.id // empty')
echo "   Created asset_id: $ASSET_ID"

# Get single asset (if we got an ID)
if [ -n "$ASSET_ID" ] && [ "$ASSET_ID" != "null" ]; then
    GET_ASSET_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/assets/$ASSET_ID" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/json")
    check_status "Get single asset" 200 "$GET_ASSET_STATUS"

    # Update asset
    UPDATE_ASSET_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$BASE_URL/assets/$ASSET_ID" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -d '{"status":"Maintenance","criticality":"Medium"}')
    check_status "Update asset" 200 "$UPDATE_ASSET_STATUS"

    # Delete (cleanup)
    DELETE_ASSET_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/assets/$ASSET_ID" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/json")
    check_status "Delete asset (cleanup)" 200 "$DELETE_ASSET_STATUS"
fi

# Filter tests
FILTER_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "$BASE_URL/assets?status=Operational&criticality=High&per_page=10" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json")
check_status "Filter assets (Operational + High)" 200 "$FILTER_STATUS"

# ====================================================================================
section "WORK ORDERS — CRUD"
# ====================================================================================

# List work orders
LIST_WO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/work-orders?per_page=5" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json")
check_status "List work orders" 200 "$LIST_WO_STATUS"

# Create work order
CREATE_WO_RESPONSE=$(curl -s -X POST "$BASE_URL/work-orders" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{
    "title": "curl Test WO — Replace Seal",
    "description": "Automated curl test — safe to delete",
    "type": "Corrective",
    "asset_id": 1,
    "location_id": 1,
    "priority": "Medium",
    "status": "Open"
  }')

CREATE_WO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/work-orders" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"title":"curl Test WO","type":"Corrective","asset_id":1,"location_id":1,"priority":"Medium","status":"Open"}')

check_status "Create work order" 201 "$CREATE_WO_STATUS"

WO_ID=$(echo "$CREATE_WO_RESPONSE" | jq -r '.data.wo_id // .data.id // empty')
echo "   Created wo_id: $WO_ID"

if [ -n "$WO_ID" ] && [ "$WO_ID" != "null" ]; then
    # Start WO
    START_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/work-orders/$WO_ID/start" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/json")
    check_status "Start work order" 200 "$START_STATUS"

    # Complete WO
    COMPLETE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/work-orders/$WO_ID/complete" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -d '{"labor_cost":100.00,"material_cost":50.00}')
    check_status "Complete work order" 200 "$COMPLETE_STATUS"

    # Delete (cleanup)
    DELETE_WO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/work-orders/$WO_ID" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/json")
    check_status "Delete work order (cleanup)" 200 "$DELETE_WO_STATUS"
fi

# ====================================================================================
section "KPI DASHBOARD"
# ====================================================================================

for ENDPOINT in summary critical top-performers by-type attention-needed; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/kpis/$ENDPOINT" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/json")
    check_status "GET /kpis/$ENDPOINT" 200 "$STATUS"
done

# ====================================================================================
section "CALENDAR"
# ====================================================================================

for ENDPOINT in "events?start=2025-01-01&end=2025-12-31" "pm/unscheduled" "pm/overdue"; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/calendar/$ENDPOINT" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/json")
    check_status "GET /calendar/$ENDPOINT" 200 "$STATUS"
done

# ====================================================================================
section "BACKLOG"
# ====================================================================================

for ENDPOINT in summary work-orders pm by-priority by-asset aging trend; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/backlog/$ENDPOINT" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: application/json")
    check_status "GET /backlog/$ENDPOINT" 200 "$STATUS"
done

# ====================================================================================
section "AUTH — Logout"
# ====================================================================================

LOGOUT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/auth/logout" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json")
check_status "Logout" 200 "$LOGOUT_STATUS"

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Test run complete!${NC}"
echo ""
