[CmdletBinding(DefaultParameterSetName = "All")]
Param (
    [Parameter(HelpMessage = "Path to CSV file with column named SerialNumber", Position = 0)]
    [string] $CSVPath,

    [Parameter(HelpMessage = "Also remove devices from Autopilot and Azure AD (True or False)")]
    [switch] $AutopilotAAD,

    [Parameter(HelpMessage = "Interactive mode (True or False)")]
    [switch] $Interactive
)

# Function to get path of a CSV file using a graphical file picker
function Get-CsvPath {
    param (
        [string]$Title = "Choose .CSV file with SerialNumber column"
    )

    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath("Desktop") 
        Filter           = "CSV files (*.csv)|*.csv"
        Multiselect      = $False
        Title            = $Title
    }
    # Send to null to avoid "Cancel" or "OK" being prepended to return value
    $null = $FileBrowser.ShowDialog()

    Return $FileBrowser.FileName
}

# Open file picker if path is not specified
Add-Type -AssemblyName System.Windows.Forms
if (-Not $CSVPath -and -Not $Interactive) {
    $AutopilotAAD = $false
    $CSVPath = Get-CsvPath -Title "CSV to remove from Intune (or Cancel for Autopilot/AAD removal). Must have SerialNumber column."

    if (-Not $CSVPath) {
        $AutopilotAAD = $true
        $CSVPath = Get-CsvPath -Title "CSV to remove from Intune, Autopilot, and AzureAD. Must have SerialNumber column."
    }
}

# Import CSV
if (-Not $Interactive) {
    Try {
        $ImportedData = Import-Csv $CSVPath

        # Output type of removal
        Write-Host "Import succesful. Devices will be removed from " -NoNewline
        if ($AutopilotAAD) {
            Write-Host "Intune, Autopilot, and Azure AD" -ForegroundColor Cyan -NoNewline
        }
        Else {
            Write-Host "Intune" -ForegroundColor Cyan -NoNewline
        }
        Write-Host "."
    }
    Catch {
        Write-Host "Error importing CSV" -ForegroundColor Red
        $Interactive = $true
    }
}

# Get serial numbers from user interactively
if ($Interactive) {
    # Interactive mode
    Write-Host "Interactive mode. Enter serial numbers to remove from Intune. Enter a blank line when finished."
    $ImportedData = @()
    $SerialNumber = "-"

    # Get serial numbers until user enters blank line
    while ($SerialNumber -ne "") {
        $SerialNumber = Read-Host "Enter serial number"
        if ($SerialNumber -ne "") {
            $ImportedData += [PSCustomObject]@{
                SerialNumber = $SerialNumber
            }
        }
    }
}

# Make sure CSV contains proper column
if ("SerialNumber" -notin ($ImportedData[0].psobject.Properties).name) {
    Write-Host "CSV does not contain column SerialNumber" -ForegroundColor Red
    Exit
}

# Set logging path and output to terminal
try {
    $LogPath = $(Split-Path $(Resolve-Path $CSVPath)) + "\Log_" + $(Get-Date -Format "yyyy-MM-dd_hh-mm-ss") + ".csv"
}
catch {
    $LogPath = $PSScriptRoot + "\Log_" + $(Get-Date -Format "yyyy-MM-dd_hh-mm-ss") + ".csv"
}
Write-Host "Results will be logged to " -NoNewline
Write-Host $LogPath -ForegroundColor Cyan

# Load required modules
Write-Host "Importing Graph..."
Import-Module Microsoft.Graph.Intune –ErrorAction Stop

# Authenticate with Intune
Write-Host "Authenticating with MS Graph..."
Connect-MgGraph -Scopes "DeviceManagementServiceConfig.ReadWrite.All", "DeviceManagementManagedDevices.ReadWrite.All", "Directory.AccessAsUser.All" -ErrorAction Stop

# Iterate through computers
foreach ($CurrentComputer in $ImportedData) {
    $SerialNumber = $CurrentComputer.SerialNumber.ToUpper()

    # Info for logging
    $DeviceLog = [PSCustomObject]@{
        SerialNumber = $SerialNumber
        Intune       = "Not attempted"
        Autopilot    = "Not attempted"
        AzureAD      = "Not attempted"
    }

    Write-Host "Processing " -NoNewline
    Write-Host $($SerialNumber) –ForegroundColor Cyan -NoNewline
    Write-Host "..."

    # Delete from Intune
    Try {

        # Find device/s in Intune
        $DeviceLog.Intune = "Not found"
        $IntuneDevices = Get-MgDeviceManagementManagedDevice –Filter "SerialNumber eq '$SerialNumber'" –ErrorAction SilentlyContinue

        # Delete from Intune
        foreach ($IntuneDevice in $IntuneDevices) {
            $DeviceLog.Intune = "Found"
            Try {
                Remove-MgDeviceManagementManagedDevice –ManagedDeviceId $IntuneDevice.Id –ErrorAction SilentlyContinue
                $DeviceLog.Intune = "Deleted"
                Write-Host "Deleted $($IntuneDevice.deviceName) from Intune" –ForegroundColor Green
            }
            Catch {
                $DeviceLog.Intune = "Error deleting"
                Write-Host "Error deleting $($IntuneDevice.deviceName) from Intune" –ForegroundColor Red
                $_
            }
        }
    }
    Catch {
        $DeviceLog.Intune = "Error finding"
        Write-Host "Error finding $SerialNumber in Intune" –ForegroundColor Red
        $_
    }

    # Delete from Autopilot and AAD if -AutopilotAAD
    if ($AutopilotAAD) {
        Try {

            # Find in Autopilot
            $DeviceLog.Autopilot = "Not found"
            $AutopilotDevices = Get-MgDeviceManagementWindowAutopilotDeviceIdentity -Filter "contains(SerialNumber,'$SerialNumber')"

            # Remove from Autopilot if found; also attempts AAD removal
            foreach ($AutopilotDevice in $AutopilotDevices) {
                $DeviceLog.Autopilot = "Found"
                Try {
                    Remove-MgDeviceManagementWindowAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $AutopilotDevice.Id -ErrorAction SilentlyContinue
                    $DeviceLog.Autopilot = "Deleted"
                    Write-Host "Deleted $($AutopilotDevice.Id) from Autopilot" -ForegroundColor Green
                }
                Catch {
                    $DeviceLog.Autopilot = "Error deleting"
                    Write-Host "Error deleting $($AutopilotDevice.Id) from Autopilot" -ForegroundColor Red
                    $_
                }

                # Look for device in AAD
                $DeviceLog.AzureAD = "Not found"
                $AADDevice = Get-MgDevice -Filter "DeviceId eq '$($AutopilotDevice.AzureActiveDirectoryDeviceId)'"

                # Delete device if found
                if ($AADDevice) {
                    $DeviceLog.AzureAD = "Found"
                    Try {
                        Remove-MgDevice -DeviceId $AADDevice.Id -ErrorAction SilentlyContinue
                        $DeviceLog.AzureAD = "Deleted"
                        Write-Host "Deleted $($AADDevice.Id) from Azure AD" -ForegroundColor Green
                    }
                    Catch {
                        $DeviceLog.AzureAD = "Error deleting"
                        Write-Host "Error deleting $($AADDevice.Id) from Azure AD" -ForegroundColor Red
                        $_
                    }
                }
            }
        }
        Catch {
            $DeviceLog.Autopilot = "Error finding"
            Write-Host "Error finding $SerialNumber in Autopilot"
            $_
        }
    }

    # Add to log file
    Export-Csv -Path $LogPath -InputObject $DeviceLog -Append -NoTypeInformation
}