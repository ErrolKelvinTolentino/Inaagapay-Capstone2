$web1 = [System.IO.File]::ReadAllText("admin-web/pages/inventory.html")
$web2 = [System.IO.File]::ReadAllText("admin-web2/pages/inventory.html")

$getFunctions = {
    param($text)
    $m1 = [regex]::Matches($text, 'function\s+([a-zA-Z0-9_$]+)\s*\(') | % { $_.Groups[1].Value }
    $m2 = [regex]::Matches($text, 'window\.([a-zA-Z0-9_$]+)\s*=') | % { $_.Groups[1].Value }
    return ($m1 + $m2) | Select-Object -Unique | Sort-Object
}

$f1 = &$getFunctions $web1
$f2 = &$getFunctions $web2

Write-Host "=== FUNCTIONS IN WEB 1 ONLY ==="
$f1 | Where-Object { $_ -notin $f2 } | ForEach-Object { Write-Host "  - $_" }

Write-Host "`n=== FUNCTIONS IN WEB 2 ONLY ==="
$f2 | Where-Object { $_ -notin $f1 } | ForEach-Object { Write-Host "  - $_" }

$getIds = {
    param($text)
    return [regex]::Matches($text, 'id=["'']([^"'']+)["'']') | % { $_.Groups[1].Value } | Select-Object -Unique | Sort-Object
}

$id1 = &$getIds $web1
$id2 = &$getIds $web2

Write-Host "`n=== IDs IN WEB 1 ONLY ==="
$id1 | Where-Object { $_ -notin $id2 } | ForEach-Object { Write-Host "  - $_" }

Write-Host "`n=== IDs IN WEB 2 ONLY ==="
$id2 | Where-Object { $_ -notin $id1 } | ForEach-Object { Write-Host "  - $_" }
