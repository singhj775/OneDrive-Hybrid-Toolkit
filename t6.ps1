$TestFile = "$env:USERPROFILE\OneDrive\_TEST_CHURN_FILE.txt"
Write-Host "Simulating sync loop for 20 seconds..." -ForegroundColor Yellow
for ($i = 1; $i -le 20; $i++) {
    Add-Content -Path $TestFile -Value "Test iteration $i at $(Get-Date)"
    Start-Sleep -Seconds 1
}
Write-Host "Simulation complete. You can delete _TEST_CHURN_FILE.txt from your OneDrive." -ForegroundColor Green