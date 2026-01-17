$inputFile = "addictive.jsonl"
$outputDir = "./output_json"

if (!(Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# --- Helpers ---

function Convert-UrlToSafeFileName([string]$url, [int]$lineNumber) {
    $baseName = "entry_$lineNumber"
    if ($url) {
        try {
            $uri = [System.Uri]$url
            $baseName = ($uri.Host + $uri.AbsolutePath).TrimEnd("/")
        } catch { }
    }

    $safe = $baseName `
        -replace "^https?://", "" `
        -replace "[\\\/:*?""<>|]", "_" `
        -replace "\s+", "_" `
        -replace "_{2,}", "_"

    if ($safe.Length -gt 180) { $safe = $safe.Substring(0, 180) }
    return $safe
}

# Fixes strings like "GonzÃ¡lez" -> "González" and "â€“" -> "–"
function Repair-Mojibake([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return $s }

    # Heuristic: only try repair when common mojibake markers appear
    if ($s -match "Ã.|â€|Â") {
        $cp1252 = [System.Text.Encoding]::GetEncoding(1252)
        return [System.Text.Encoding]::UTF8.GetString($cp1252.GetBytes($s))
    }
    return $s
}

# Recursively repairs all string values in an object (including arrays / nested objects)
function Repair-ObjectStrings($obj) {
    if ($null -eq $obj) { return $null }

    if ($obj -is [string]) {
        return (Repair-Mojibake $obj)
    }

    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [System.Collections.IDictionary]) -and -not ($obj -is [string])) {
        $arr = @()
        foreach ($item in $obj) { $arr += (Repair-ObjectStrings $item) }
        return $arr
    }

    if ($obj -is [System.Collections.IDictionary]) {
        foreach ($k in @($obj.Keys)) { $obj[$k] = Repair-ObjectStrings $obj[$k] }
        return $obj
    }

    # PSCustomObject: iterate properties
    $props = $obj.PSObject.Properties
    foreach ($p in $props) {
        $obj.$($p.Name) = Repair-ObjectStrings $p.Value
    }
    return $obj
}

# --- Main ---

$usedNames = @{}
$lineNumber = 0

# IMPORTANT: force UTF-8 read (fixes many cases on Windows PowerShell 5.1)
Get-Content -Path $inputFile -Encoding UTF8 | ForEach-Object {

    $lineNumber++
    $line = $_.Trim()
    if ($line -eq "") { return }

    try {
        $jsonObj = $line | ConvertFrom-Json
    } catch {
        Write-Warning "Skipping invalid JSON at line $lineNumber"
        return
    }

    # OPTIONAL but recommended: repair mojibake in all string fields
    $jsonObj = Repair-ObjectStrings $jsonObj

    $safeName = Convert-UrlToSafeFileName -url $jsonObj.url -lineNumber $lineNumber

    # de-dupe filenames
    if ($usedNames.ContainsKey($safeName)) {
        $usedNames[$safeName]++
        $safeName = "$safeName-$($usedNames[$safeName])"
    } else {
        $usedNames[$safeName] = 1
    }

    $outPath = Join-Path $outputDir "$safeName.json"

    # Write as UTF-8 (PS 5.1 uses BOM; PS 7 generally no BOM).
    # If you want *no BOM* in PS 7, replace Out-File with Set-Content -Encoding utf8NoBOM.
    $jsonObj | ConvertTo-Json -Depth 50 | Out-File -FilePath $outPath -Encoding UTF8
}

Write-Host "Finished. Files created in '$outputDir'"
