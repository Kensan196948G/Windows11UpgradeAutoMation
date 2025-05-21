# This PowerShell script checks if there is enough HDD space for the upgrade.
# It also contains a function to log HDD status.

function Log-HDDStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$LogFilePath,

        [Parameter(Mandatory=$true)]
        [string]$Header
    )

    try {
        # Ensure log directory exists
        $LogDirectory = Split-Path -Path $LogFilePath -Parent
        if (-not (Test-Path -Path $LogDirectory)) {
            try {
                New-Item -ItemType Directory -Path $LogDirectory -Force -ErrorAction Stop | Out-Null
                Write-Verbose "Log directory created: $LogDirectory"
            }
            catch {
                Write-Error "Failed to create log directory '$LogDirectory'. Error: $($_.Exception.Message)"
                return # Exit function if directory creation fails
            }
        }

        # Get HDD Info for C: drive
        $drive = Get-PSDrive C -ErrorAction Stop
        # Corrected totalSizeGB calculation
        $totalSizeGB = [Math]::Floor(($drive.Used + $drive.Free) / 1GB) 
        $usedSpaceGB = [Math]::Floor($drive.Used / 1GB)
        $freeSpaceGB = [Math]::Floor($drive.Free / 1GB)
        
        $usagePercentage = 0
        if (($drive.Used + $drive.Free) -gt 0) { # Avoid division by zero if drive is empty or inaccessible
            $usagePercentage = [Math]::Floor(($drive.Used / ($drive.Used + $drive.Free)) * 100)
        }


        # Get Hostname and Username
        $hostname = $env:COMPUTERNAME
        $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

        # Construct Log String
        # Using -join for better readability with multi-line strings
        $logLines = @(
            "$Header",
            "ホスト名：$hostname",
            "ユーザー名：$username",
            "全HDD容量：$totalSizeGB GB",
            "使用容量：$usedSpaceGB GB",
            "空き容量：$freeSpaceGB GB",
            "使用率　：$usagePercentage%"
        )
        $logContent = $logLines -join [System.Environment]::NewLine

        # Append to log file
        try {
            # Ensure the file has a header if it's new, or add a separator
            if (-not (Test-Path $LogFilePath)) {
                Add-Content -Path $LogFilePath -Value $logContent -Encoding UTF8 -ErrorAction Stop
            } else {
                # Add a newline separator if appending to an existing file that's not empty
                $existingContent = Get-Content $LogFilePath -Raw -ErrorAction SilentlyContinue
                if ($existingContent -and $existingContent.Length -gt 0) {
                    Add-Content -Path $LogFilePath -Value ([System.Environment]::NewLine + $logContent) -Encoding UTF8 -ErrorAction Stop
                } else {
                    Add-Content -Path $LogFilePath -Value $logContent -Encoding UTF8 -ErrorAction Stop
                }
            }
            Write-Verbose "Successfully logged HDD status to '$LogFilePath'"
        }
        catch {
            Write-Error "Failed to write to log file '$LogFilePath'. Error: $($_.Exception.Message)"
        }
    }
    catch {
        Write-Error "An error occurred in Log-HDDStatus. Error: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Log-HDDStatus

# Main script logic for CheckHDD.ps1 (legacy check)
# This part is kept for compatibility or direct execution checks but is not the primary function.
# The Log-HDDStatus function is designed to be called as a module.

Write-Host "Legacy HDD space check (informational, Log-HDDStatus is the primary export)..."

$requiredSpaceBytes = 20 * 1GB # Example: 20GB required
$driveInfo = Get-PSDrive C -ErrorAction SilentlyContinue

if ($driveInfo) {
    $availableSpaceBytes = $driveInfo.Free
    if ($availableSpaceBytes -lt $requiredSpaceBytes) {
        $requiredSpaceGB = [Math]::Round($requiredSpaceBytes / 1GB, 0)
        $availableSpaceGB = [Math]::Round($availableSpaceBytes / 1GB, 0)
        Write-Warning "Not enough HDD space. Required: $requiredSpaceGB GB, Available: $availableSpaceGB GB (Legacy Check)"
        # exit 1 # Exit commented out as this script is now more of a module
    } else {
        Write-Host "HDD space check passed (Legacy Check)."
        # exit 0 # Exit commented out
    }
} else {
    Write-Error "Failed to get drive information for C: (Legacy Check)."
    # exit 1
}
