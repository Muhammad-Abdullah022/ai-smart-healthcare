# Prints this PC's Wi-Fi / LAN IPv4 address (the one with a default gateway), e.g. 192.168.1.10
$c = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
if ($c) { $c.IPv4Address[0].IPAddress }
