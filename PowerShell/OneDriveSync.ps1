# powershell script to sync OneDrive files to a local folder
# requires the OneDrive client to be installed and configured on the machine
# set the source and destination paths
$sourcePath = "C:\Users\collinmr\OneDrive - NHS\PHU - D - Oncology Secretaries - oncology_exports"
$destinationPath = "C:\IDR\RAW\Onc_ref"

# get todays date string (matches filename pattern yyyy-mm-dd)
$dateString = Get-Date -Format "yyyy-MM-dd"

# Find todays file in the source directory
$todayFile = Get-ChildItem -Path $sourcePath -Filter "oncology_intake_$dateString*.csv" -File

if ($todayFile.count -gt 0) {
    # Pick the newest file if there are multiple matches
    $latestFile = $todayFile | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    # Copy the file to the destination path
    Copy-Item -Path $latestFile.FullName -Destination $destinationPath -Force
    Write-Host "Copied file: $($latestFile.FullName) to $destinationPath"
} else {
    Write-Host "No matching file found for date: $dateString"
}

# add some retry logic to handle potential issues with file access or network problems
$maxRetries = 6
$delaySeconds = 60

for ($i = 0; $i -lt $maxRetries; $i++) {
    try {
        # Attempt to copy the file again
        if ($todayFile.count -gt 0) {
            $latestFile = $todayFile | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Copy-Item -Path $latestFile.FullName -Destination $destinationPath -Force
            Write-Host "Successfully copied file on attempt $($i + 1)"
            break
        } else {
            Write-Host "No matching file found for date: $dateString on attempt $($i + 1)"
        }
    } catch {
        Write-Host "Error copying file on attempt $($i + 1): $_"
    }
    Start-Sleep -Seconds $delaySeconds
}