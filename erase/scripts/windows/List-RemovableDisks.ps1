param()

Get-Disk |
  Where-Object { $_.BusType -ne 'RAID' -and $_.PartitionStyle -ne 'RAW' -or $_.IsBoot -eq $false } |
  Where-Object { $_.BusType -in @('USB') -or $_.IsRemovable -eq $true } |
  Select-Object Number, FriendlyName, BusType, IsRemovable,
                @{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}},
                OperationalStatus |
  Format-Table -AutoSize
