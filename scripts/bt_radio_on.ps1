$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Runtime.WindowsRuntime

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    return $netTask.Result
}

[Windows.Devices.Radios.Radio, Windows.Devices.Radios, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Radios.RadioAccessStatus, Windows.Devices.Radios, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Radios.RadioKind, Windows.Devices.Radios, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Radios.RadioState, Windows.Devices.Radios, ContentType=WindowsRuntime] | Out-Null

$access = Await ([Windows.Devices.Radios.Radio]::RequestAccessAsync()) ([Windows.Devices.Radios.RadioAccessStatus])
Write-Host "Radio access: $access"
if ($access -ne 'Allowed') {
    Write-Host 'Access not allowed — cannot control radio programmatically.'
    exit 2
}

$radios = Await ([Windows.Devices.Radios.Radio]::GetRadiosAsync()) ([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]])
foreach ($r in $radios) {
    Write-Host ("Radio: {0}  kind={1}  state={2}" -f $r.Name, $r.Kind, $r.State)
    if ($r.Kind -eq [Windows.Devices.Radios.RadioKind]::Bluetooth -and $r.State -ne [Windows.Devices.Radios.RadioState]::On) {
        $result = Await ($r.SetStateAsync([Windows.Devices.Radios.RadioState]::On)) ([Windows.Devices.Radios.RadioAccessStatus])
        Write-Host "SetStateAsync result: $result"
        Write-Host "New state: $($r.State)"
    }
}
