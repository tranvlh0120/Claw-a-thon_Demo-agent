# ============================================================
# ZaloPay Loyalty - Earn Narrative Report Agent
# Usage: .\earn_report_agent.ps1 -ApiKey "sk-ant-..."
#        (hoac set bien moi truong ANTHROPIC_API_KEY truoc)
# ============================================================
param(
    [string]$ApiKey     = "vn-ZIa-9aZvOLH-FTK_v86UnHKCudrj0I2608331a3e70411a81c13b0ebffebae4rSs0J-jNacdp-x_8_8iKU8-LO0V_2a1",
    [string]$CoinFile   = "C:\Users\LAP60817-local\Downloads\Earn Coin.csv",
    [string]$UserFile   = "C:\Users\LAP60817-local\Downloads\Earn User.csv",
    [string]$OutputDir  = $PSScriptRoot,
    [string]$Model      = "minimax/minimax-m2.5",
    [string]$Endpoint   = "https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1/chat/completions"
)

if (-not $ApiKey) {
    Write-Host "ERROR: Can khong tim thay API key." -ForegroundColor Red
    Write-Host "  Chay: .\earn_report_agent.ps1 -ApiKey 'vn-ZIa-...'" -ForegroundColor Yellow
    exit 1
}

$ErrorActionPreference = "Stop"

# ============================================================
# STEP 1: Load & Process Data
# ============================================================
Write-Host "[1/4] Loading data..." -ForegroundColor Cyan

$coinData = Import-Csv -Path $CoinFile -Delimiter "`t" -Encoding Unicode
$userData = Import-Csv -Path $UserFile -Delimiter "`t" -Encoding Unicode

$keyColumns = @("Action Type", "Action Source", "MKT Code", "User Segment", "Task Tag", "Task ID")
$months = $coinData[0].PSObject.Properties.Name | Where-Object { $keyColumns -notcontains $_ }
$latestMonth = $months[0]
$prevMonth   = $months[1]

Write-Host "   Months: $($months -join ' | ')" -ForegroundColor Gray

# Build user lookup
$userLookup = @{}
foreach ($row in $userData) {
    $key = ($keyColumns | ForEach-Object { $row.$_ }) -join "|"
    $userLookup[$key] = $row
}

# ============================================================
# STEP 2: Build Summary for AI
# ============================================================
Write-Host "[2/4] Calculating statistics..." -ForegroundColor Cyan

function Parse-Number($str) {
    $clean = $str -replace '[,\s]', ''
    if ($clean -match '^\d+$') { return [double]$clean } else { return $null }
}

function Get-MoM($current, $previous) {
    if ($current -ne $null -and $previous -ne $null -and $previous -gt 0) {
        return [math]::Round(($current - $previous) / $previous * 100, 1)
    }
    return $null
}

# Filter rows: Action Type != ALL, Action Source = ALL (de lay tong theo type), Segment khac ALL
$summaryRows = $coinData | Where-Object {
    $_."Action Type" -ne "ALL" -and $_."Action Source" -eq "ALL" -and
    $_."MKT Code" -eq "" -and $_."Task Tag" -eq "ALL" -and $_."Task ID" -eq "ALL"
}

$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add("=== DU LIEU EARN XU ZALOPAY ===")
$summaryLines.Add("Thoi gian: $($months -join ', ')")
$summaryLines.Add("Thang moi nhat: $latestMonth | Thang truoc: $prevMonth")
$summaryLines.Add("")
$summaryLines.Add("--- TONG QUAN THEO EARN SOURCE ---")

foreach ($coinRow in $summaryRows) {
    $key = ($keyColumns | ForEach-Object { $coinRow.$_ }) -join "|"
    $userRow = $userLookup[$key]

    $actionType = $coinRow."Action Type"
    $segment    = $coinRow."User Segment"

    $coinCur  = Parse-Number $coinRow.$latestMonth
    $coinPrev = Parse-Number $coinRow.$prevMonth
    $userCur  = if ($userRow) { Parse-Number $userRow.$latestMonth } else { $null }
    $userPrev = if ($userRow) { Parse-Number $userRow.$prevMonth } else { $null }

    $cpuCur  = if ($coinCur  -ne $null -and $userCur  -ne $null -and $userCur  -gt 0) { [math]::Round($coinCur  / $userCur,  1) } else { $null }
    $cpuPrev = if ($coinPrev -ne $null -and $userPrev -ne $null -and $userPrev -gt 0) { [math]::Round($coinPrev / $userPrev, 1) } else { $null }

    $coinMoM = Get-MoM $coinCur $coinPrev
    $userMoM = Get-MoM $userCur $userPrev
    $cpuMoM  = Get-MoM $cpuCur  $cpuPrev

    $line = "Source=$actionType | Segment=$segment"
    if ($coinCur  -ne $null) { $line += " | Coin($latestMonth)=$('{0:N0}' -f $coinCur)" }
    if ($coinMoM  -ne $null) { $line += " | Coin_MoM=${coinMoM}%" }
    if ($userCur  -ne $null) { $line += " | User=$('{0:N0}' -f $userCur)" }
    if ($userMoM  -ne $null) { $line += " | User_MoM=${userMoM}%" }
    if ($cpuCur   -ne $null) { $line += " | Coin/User=$cpuCur" }
    if ($cpuMoM   -ne $null) { $line += " | CPU_MoM=${cpuMoM}%" }

    $summaryLines.Add($line)
}

# Them du lieu ALL cho overview
$allRows = $coinData | Where-Object {
    $_."Action Type" -eq "ALL" -and $_."Action Source" -eq "ALL" -and
    $_."MKT Code" -eq "" -and $_."Task Tag" -eq "ALL" -and $_."Task ID" -eq "ALL"
}

$summaryLines.Add("")
$summaryLines.Add("--- TONG QUAN THEO SEGMENT (ALL SOURCES) ---")
foreach ($coinRow in $allRows) {
    $key = ($keyColumns | ForEach-Object { $coinRow.$_ }) -join "|"
    $userRow = $userLookup[$key]
    $segment = $coinRow."User Segment"

    $coinCur  = Parse-Number $coinRow.$latestMonth
    $coinPrev = Parse-Number $coinRow.$prevMonth
    $userCur  = if ($userRow) { Parse-Number $userRow.$latestMonth } else { $null }
    $cpuCur   = if ($coinCur -ne $null -and $userCur -ne $null -and $userCur -gt 0) { [math]::Round($coinCur / $userCur, 1) } else { $null }
    $coinMoM  = Get-MoM $coinCur $coinPrev

    $line = "Segment=$segment"
    if ($coinCur -ne $null) { $line += " | TotalCoin=$('{0:N0}' -f $coinCur)" }
    if ($coinMoM -ne $null) { $line += " | MoM=${coinMoM}%" }
    if ($userCur -ne $null) { $line += " | Users=$('{0:N0}' -f $userCur)" }
    if ($cpuCur  -ne $null) { $line += " | Coin/User=$cpuCur" }
    $summaryLines.Add($line)
}

$dataContext = $summaryLines -join "`n"

Write-Host "   Processed $($summaryRows.Count) source-segment combinations" -ForegroundColor Gray

# ============================================================
# STEP 3: Call Claude API
# ============================================================
Write-Host "[3/4] Calling Claude AI to generate narrative..." -ForegroundColor Cyan

$prompt = @"
Bạn là chuyên viên phân tích dữ liệu tại team Loyalty ZaloPay.
Dưới đây là dữ liệu thống kê xu earn của users theo từng source và segment.

$dataContext

Hãy viết một báo cáo tóm tắt bằng tiếng Việt theo cấu trúc sau:

## TỔNG QUAN THÁNG $latestMonth

### 1. Điểm nổi bật
(3-5 bullet points về những điểm đáng chú ý nhất trong tháng)

### 2. Phân tích Segment NU (New User)
(Tập trung phân tích kỹ segment NU: số lượng user, tổng xu earn, coin/user, MoM so với tháng trước, breakdown theo từng earn source — TRANSACTION, CHECK_IN, v.v.)

### 3. Phân tích các Segment còn lại
(CU, SU, SU30, SU60, NU30, NU60, UNDEFINED — so sánh coin/user, highlight segment nào nổi bật)

### 4. Phân tích theo Earn Source
(Cho từng source: tổng xu, MoM, segment nào đóng góp chính)

### 5. Điểm cần theo dõi
(2-3 điểm cảnh báo hoặc cần action, ưu tiên liên quan đến NU)

Viết súc tích, dùng số liệu cụ thể từ data, tránh chung chung. Đơn vị xu viết tắt là "xu", số lớn dùng "M xu" hoặc "B xu".
"@

$body = @{
    model      = $Model
    max_tokens = 2000
    messages   = @(
        @{ role = "user"; content = $prompt }
    )
} | ConvertTo-Json -Depth 5

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Content-Type"  = "application/json"
}

try {
    $rawResponse = Invoke-WebRequest -Uri $Endpoint -UseBasicParsing `
        -Method POST -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60
    $responseText = [System.Text.Encoding]::UTF8.GetString($rawResponse.RawContentStream.ToArray())
    $response = $responseText | ConvertFrom-Json
    $narrative = $response.choices[0].message.content
    if (-not $narrative) {
        Write-Host "   Raw response: $($response | ConvertTo-Json -Depth 5)" -ForegroundColor Yellow
        $narrative = "Loi: Khong nhan duoc noi dung tu AI. Vui long kiem tra API key va model name."
    }
    Write-Host "   AI narrative generated ($($narrative.Length) chars)" -ForegroundColor Gray
} catch {
    Write-Host "ERROR calling Claude API: $_" -ForegroundColor Red
    exit 1
}

# ============================================================
# STEP 4: Output to Text File
# ============================================================
Write-Host "[4/4] Saving report..." -ForegroundColor Cyan

$outputPath = Join-Path $OutputDir ("EarnReport_${latestMonth}_$(Get-Date -Format 'yyyyMMdd_HHmm').html")

# Convert markdown to basic HTML
$htmlBody = $narrative `
    -replace '&', '&amp;' `
    -replace '<', '&lt;' `
    -replace '>', '&gt;' `
    -replace '(?m)^## (.+)$', '<h2>$1</h2>' `
    -replace '(?m)^### (.+)$', '<h3>$1</h3>' `
    -replace '(?m)^[-•] (.+)$', '<li>$1</li>' `
    -replace '\*\*(.+?)\*\*', '<strong>$1</strong>' `
    -replace '(?m)^(?!<[hlip])(.+)$', '<p>$1</p>'

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Bao Cao Earn Xu - $latestMonth</title>
<style>
  body { font-family: Arial, sans-serif; max-width: 900px; margin: 40px auto; padding: 0 20px; color: #333; }
  h1 { color: #1F4E79; border-bottom: 2px solid #1F4E79; padding-bottom: 8px; }
  h2 { color: #2E75B6; margin-top: 30px; }
  h3 { color: #404040; }
  li { margin: 6px 0; }
  p { line-height: 1.6; }
  .header { background: #1F4E79; color: white; padding: 16px 24px; border-radius: 6px; margin-bottom: 24px; }
  .header p { color: #ccc; margin: 4px 0 0 0; font-size: 13px; }
</style>
</head>
<body>
<div class="header">
  <h1 style="color:white;border:none;margin:0">BAO CAO EARN XU - ZALOPAY LOYALTY</h1>
  <p>Tao tu dong boi Earn Report Agent | $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
</div>
$htmlBody
</body>
</html>
"@

[System.IO.File]::WriteAllText($outputPath, $html, (New-Object System.Text.UTF8Encoding $true))

Write-Host ""
Write-Host "DONE!" -ForegroundColor Green
Write-Host "Report saved to:" -ForegroundColor Green
Write-Host "  $outputPath" -ForegroundColor White
Write-Host ""
Write-Host "Nap data moi: thay duong dan CoinFile va UserFile, chay lai script la xong." -ForegroundColor Cyan
