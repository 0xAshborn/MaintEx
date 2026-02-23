@echo off
setlocal EnableDelayedExpansion
REM ====================================================================================
REM CORTEX CMMS API — Windows Batch curl Test Suite
REM Usage: cortex_curl_tests.bat
REM Requires: curl.exe (built-in Windows 10+)
REM ====================================================================================

set BASE=https://cortex-api.onrender.com/api
REM set BASE=http://localhost:8000/api

set SUBDOMAIN=acme
set EMAIL=admin@cortex.com
set PASS=password123
set TOKEN=

echo.
echo === HEALTH CHECK ===
curl -s -o NUL -w "  Health: HTTP %%{http_code}\n" %BASE%/health

echo.
echo === AUTH Login ===
curl -s -X POST "%BASE%/auth/login" ^
  -H "Content-Type: application/json" ^
  -H "Accept: application/json" ^
  -d "{\"email\":\"%EMAIL%\",\"password\":\"%PASS%\",\"subdomain\":\"%SUBDOMAIN%\"}" ^
  -o cortex_login_response.tmp

type cortex_login_response.tmp
echo.

REM Extract token using findstr + more (simple, no jq required)
REM For full token extraction you'd need PowerShell or jq — see note below
for /f "tokens=2 delims=:," %%a in ('type cortex_login_response.tmp ^| findstr /i "token"') do (
    set TOKEN_RAW=%%a
)
REM Token is now in TOKEN_RAW but needs cleanup — easier to set manually:
echo NOTE: Copy the "token" value from the response above and set it below:
echo set TOKEN=your_token_here
echo.
echo For automated token extraction, use the .sh script (Git Bash) or the one-liner below.
echo.

REM ─────────────────────────────────────────────────────────────────────────────────────
REM After login, manually copy your token and run the lines below one by one,
REM OR use the interactive test script further down.
REM ─────────────────────────────────────────────────────────────────────────────────────

echo === QUICK REFERENCE: Copy-paste curl commands ===
echo.
echo # 1. Login
echo curl -s -X POST "%BASE%/auth/login" -H "Content-Type: application/json" -H "Accept: application/json" -d "{\"email\":\"%EMAIL%\",\"password\":\"%PASS%\",\"subdomain\":\"%SUBDOMAIN%\"}"
echo.
echo # 2. After login, set TOKEN=your_token_here, then:
echo curl -s "%BASE%/auth/me" -H "Authorization: Bearer %%TOKEN%%"
echo curl -s "%BASE%/assets" -H "Authorization: Bearer %%TOKEN%%"
echo curl -s "%BASE%/work-orders" -H "Authorization: Bearer %%TOKEN%%"
echo curl -s "%BASE%/kpis/summary" -H "Authorization: Bearer %%TOKEN%%"
echo curl -s "%BASE%/kpis/critical" -H "Authorization: Bearer %%TOKEN%%"
echo curl -s "%BASE%/backlog/summary" -H "Authorization: Bearer %%TOKEN%%"
echo curl -s "%BASE%/calendar/events?start=2025-01-01^&end=2025-12-31" -H "Authorization: Bearer %%TOKEN%%"

del cortex_login_response.tmp 2>NUL
endlocal
