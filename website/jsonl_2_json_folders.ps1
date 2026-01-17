# Split JSONL into 1 JSON file per line, using URL-based routing into subfolders.
# - Categorized folders use "remaining part after matched regex" as filename
# - _other keeps the original "host + path" name
# - Forces UTF-8 input and writes UTF-8 output
# - Repairs common mojibake in strings (e.g., GonzÃ¡lez -> González)

$inputFile  = "addictive.jsonl"
$outputRoot = "./output_json_subfolders"

if (!(Test-Path $outputRoot)) {
    New-Item -ItemType Directory -Path $outputRoot | Out-Null
}

function Ensure-Dir([string]$path) {
    if (!(Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
}

function Sanitize-FileStem([string]$name, [int]$lineNumber) {
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "entry_$lineNumber" }

    $name = $name.Trim("/")

    $safe = $name `
        -replace "[\\\/:*?""<>|]", "_" `
        -replace "\s+", "_" `
        -replace "_{2,}", "_"

    if ($safe.Length -gt 180) { $safe = $safe.Substring(0, 180) }
    return $safe
}

function Repair-Mojibake([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return $s }

    # Heuristic: only try repair when common mojibake markers appear
    if ($s -match "Ã.|â€|Â") {
        $cp1252 = [System.Text.Encoding]::GetEncoding(1252)
        return [System.Text.Encoding]::UTF8.GetString($cp1252.GetBytes($s))
    }
    return $s
}

function Repair-ObjectStrings($obj) {
    if ($null -eq $obj) { return $null }

    if ($obj -is [string]) {
        return (Repair-Mojibake $obj)
    }

    if ($obj -is [System.Collections.IEnumerable] -and
        -not ($obj -is [System.Collections.IDictionary]) -and
        -not ($obj -is [string])) {

        $arr = @()
        foreach ($item in $obj) { $arr += (Repair-ObjectStrings $item) }
        return $arr
    }

    if ($obj -is [System.Collections.IDictionary]) {
        foreach ($k in @($obj.Keys)) { $obj[$k] = Repair-ObjectStrings $obj[$k] }
        return $obj
    }

    foreach ($p in $obj.PSObject.Properties) {
        $obj.$($p.Name) = Repair-ObjectStrings $p.Value
    }
    return $obj
}

function Get-OriginalStemFromUrl([string]$url, [int]$lineNumber) {
    if ([string]::IsNullOrWhiteSpace($url)) { return "entry_$lineNumber" }
    try {
        $uri = [System.Uri]$url
        return (($uri.Host + $uri.AbsolutePath).TrimEnd("/"))
    } catch {
        return "entry_$lineNumber"
    }
}

function Classify-ByUrl([string]$url, [int]$lineNumber) {
    # Default: _other keeps the ORIGINAL stem (host + path)
    $result = @{
        folder = "_other"
        stem   = (Get-OriginalStemFromUrl -url $url -lineNumber $lineNumber)
    }

    if ([string]::IsNullOrWhiteSpace($url)) { return $result }

    try {
        $uri = [System.Uri]$url
    } catch {
        return $result
    }

    # Build string like: gafasaddictive.com/gafas-deportivas
    $hostPath = $uri.Host + $uri.AbsolutePath.TrimEnd("/")

    # Categorized folders: stem is the remaining part after the matched regex
    if ($hostPath -match '^gafasaddictive\.com/addictive-(.+)$') {
        $result.folder = "addictive"; $result.stem = $Matches[1]; return $result
    }

    if ($hostPath -match '^gafasaddictive\.com/colaboradores/(.+)$') {
        $result.folder = "colaboradores"; $result.stem = $Matches[1]; return $result
    }

    if ($hostPath -match '^gafasaddictive\.com/comprar_(.+)$') {
        $result.folder = "comprar"; $result.stem = $Matches[1]; return $result
    }

    if ($hostPath -match '^gafasaddictive\.com/gafas-(.+)$') {
        $result.folder = "gafas"; $result.stem = $Matches[1]; return $result
    }

    if ($hostPath -match '^gafasaddictive\.com/producto/addictive-(.+)$') {
        $result.folder = "producto"; $result.stem = $Matches[1]; return $result
    }

    return $result
}

# Track used names per folder to avoid collisions
$usedNames  = @{}  # key: "folder|stem" -> count
$lineNumber = 0

# Force UTF-8 read (important on Windows PowerShell 5.1)
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

    # Repair mojibake in all string fields
    $jsonObj = Repair-ObjectStrings $jsonObj

    $classification = Classify-ByUrl -url $jsonObj.url -lineNumber $lineNumber
    $folderName = $classification.folder
    $stemRaw    = $classification.stem

    $stem = Sanitize-FileStem -name $stemRaw -lineNumber $lineNumber

    $outDir = Join-Path $outputRoot $folderName
    Ensure-Dir $outDir

    # Deduplicate within folder
    $dedupeKey = "$folderName|$stem"
    if ($usedNames.ContainsKey($dedupeKey)) {
        $usedNames[$dedupeKey]++
        $stem = "$stem-$($usedNames[$dedupeKey])"
    } else {
        $usedNames[$dedupeKey] = 1
    }

    $outPath = Join-Path $outDir "$stem.json"

    # Write pretty JSON as UTF-8
    $jsonObj | ConvertTo-Json -Depth 50 | Out-File -FilePath $outPath -Encoding UTF8
}

Write-Host "Finished. Files created under '$outputRoot' (folders: addictive, colaboradores, comprar, gafas, producto, _other)"
