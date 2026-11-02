$ErrorActionPreference = 'Continue'

Write-Host '== Bluetooth radios on this PC =='
Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
    Select-Object Status, FriendlyName | Format-Table -AutoSize

Write-Host '== Starting BLE scan (14s) =='

# Load WinRT BLE advertisement watcher (single-line type literal required)
[Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementWatcher, Windows.Devices.Bluetooth, ContentType=WindowsRuntime] | Out-Null

$script:found = @{}
$action = {
    param($sender, $eventArgs)
    try {
        $addr = $eventArgs.BluetoothAddress
        $name = $eventArgs.Advertisement.LocalName
        $svcs = ($eventArgs.Advertisement.ServiceUuids | ForEach-Object { $_.ToString() }) -join ', '
        $key = ('{0:X12}' -f $addr)
        $script:found[$key] = [PSCustomObject]@{
            Mac      = $key
            Name     = if ($name) { $name } else { '(no name)' }
            Services = $svcs
        }
    } catch { }
}

$watcher = New-Object Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementWatcher
$watcher.ScanningMode = [Windows.Devices.Bluetooth.Advertisement.BluetoothLEScanningMode]::Active
$sub = Register-ObjectEvent -InputObject $watcher -EventName Received -Action $action
$watcher.Start()
Start-Sleep -Seconds 14
$watcher.Stop()
Start-Sleep -Milliseconds 500
Unregister-Event -SourceIdentifier $sub.Name -ErrorAction SilentlyContinue

$script:found.Values | Sort-Object Mac | Format-Table -AutoSize
Write-Host ("Total distinct BLE devices seen: {0}" -f $script:found.Count)
