# RAG品質テストスクリプト
# テストケースを実行してRAGシステムの品質を評価

param(
    [Parameter(Mandatory=$true)]
    [string]$AppUrl
)

Write-Host "=== RAG Quality Test ===" -ForegroundColor Cyan
Write-Host "Application URL: $AppUrl`n"

# テストケースを読み込み
if (-not (Test-Path "tests/test-cases.json")) {
    Write-Error "Test cases file not found: tests/test-cases.json"
    exit 1
}

$testCases = Get-Content "tests/test-cases.json" | ConvertFrom-Json
$chatEndpoint = "https://$AppUrl/api/chat"
$headers = @{"Content-Type" = "application/json"}

$results = @()
$testNumber = 0

foreach ($test in $testCases) {
    $testNumber++
    Write-Host "`n--- Test Case $testNumber ---" -ForegroundColor Cyan
    Write-Host "Question: $($test.question)"
    
    $body = @{message = $test.question} | ConvertTo-Json
    
    try {
        $startTime = Get-Date
        $response = Invoke-RestMethod -Uri $chatEndpoint -Method Post -Headers $headers -Body $body
        $endTime = Get-Date
        $responseTime = ($endTime - $startTime).TotalMilliseconds
        
        # キーワードチェック
        $keywordsFound = 0
        $foundKeywords = @()
        foreach ($keyword in $test.expected_keywords) {
            if ($response.response -match $keyword) {
                $keywordsFound++
                $foundKeywords += $keyword
            }
        }
        
        # ソースチェック
        $sourcesCount = $response.sources.Count
        $hasSourcesCorrect = ($sourcesCount -gt 0) -eq $test.should_have_sources
        
        # 結果判定
        $keywordsPassed = $keywordsFound -gt 0
        $passed = $keywordsPassed -and $hasSourcesCorrect
        
        # 結果表示
        Write-Host "Response: $($response.response.Substring(0, [Math]::Min(150, $response.response.Length)))..."
        Write-Host "Keywords Found: $keywordsFound / $($test.expected_keywords.Count) ($($foundKeywords -join ', '))"
        Write-Host "Sources: $sourcesCount"
        Write-Host "Response Time: $([math]::Round($responseTime, 2))ms"
        
        if ($passed) {
            Write-Host "✅ PASSED" -ForegroundColor Green
        } else {
            Write-Host "❌ FAILED" -ForegroundColor Red
            if (-not $keywordsPassed) {
                Write-Host "  - Expected keywords not found" -ForegroundColor Yellow
            }
            if (-not $hasSourcesCorrect) {
                Write-Host "  - Source count mismatch (expected: $($test.should_have_sources), got: $($sourcesCount -gt 0))" -ForegroundColor Yellow
            }
        }
        
        $results += [PSCustomObject]@{
            TestId = $test.id
            Question = $test.question
            Passed = $passed
            KeywordsFound = $keywordsFound
            KeywordsTotal = $test.expected_keywords.Count
            SourcesCount = $sourcesCount
            ResponseTime = [math]::Round($responseTime, 2)
        }
        
    } catch {
        Write-Host "❌ ERROR: $_" -ForegroundColor Red
        $results += [PSCustomObject]@{
            TestId = $test.id
            Question = $test.question
            Passed = $false
            Error = $_.Exception.Message
        }
    }
}

# サマリー表示
Write-Host "`n" + ("=" * 50) -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan

$totalTests = $results.Count
$passedTests = ($results | Where-Object { $_.Passed }).Count
$failedTests = $totalTests - $passedTests
$passRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 2) } else { 0 }

Write-Host "`nTotal Tests: $totalTests"
Write-Host "Passed: $passedTests" -ForegroundColor Green
Write-Host "Failed: $failedTests" -ForegroundColor Red
Write-Host "Pass Rate: $passRate%"

if ($results | Where-Object { $_.ResponseTime }) {
    $avgResponseTime = ($results | Where-Object { $_.ResponseTime } | Measure-Object -Property ResponseTime -Average).Average
    Write-Host "`nAverage Response Time: $([math]::Round($avgResponseTime, 2))ms"
}

# 詳細結果をテーブル表示
Write-Host "`nDetailed Results:" -ForegroundColor Cyan
$results | Format-Table -Property TestId, Passed, KeywordsFound, SourcesCount, ResponseTime -AutoSize

# 結果をJSONで保存
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultFile = "tests/results/test-results-$timestamp.json"
New-Item -ItemType Directory -Force -Path "tests/results" | Out-Null
$results | ConvertTo-Json -Depth 10 | Out-File $resultFile
Write-Host "`nResults saved to: $resultFile" -ForegroundColor Yellow

# 終了コード
if ($passRate -eq 100) {
    Write-Host "`n🎉 All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n⚠️  Some tests failed. Please review the results." -ForegroundColor Yellow
    exit 1
}
