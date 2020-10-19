function Convert-BamProperty {
  param (
    [parameter(
      valueFromPipeline = $true
    )]
    [psobject] $bamObject
  )
  begin {}
  process {
    if ($bamObject.properties) {
      $newObject = $bamObject | select -property * -excludeproperty properties
      $prop = $bamObject.properties.trim("|") -split "\|"
      foreach ($p in $prop) {
        $member = $p -split "="
        $newObject | Add-Member -NotePropertyName "_$($member[0])" -NotePropertyValue $member[1]
      }
      $newObject
    } else {
      $bamObject
    }
  }
  end {}
}

function Connect-Bam {
  param(
    [Parameter(Mandatory = $true)]
    [string] 
      $uri,
    [Parameter(Mandatory = $true)]
    [pscredential] 
      $credential
  )
  
  [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
  $proxy = New-WebServiceProxy -uri $uri
  $proxy.CookieContainer = New-Object System.Net.CookieContainer
  $proxy.login($Credential.UserName, ($Credential.GetNetworkCredential()).Password)
  $Global:defaultBam = $proxy
  return $proxy
}

function Get-BamConfiguration {
  param(
    $name,
    $bam = $defaultBam
  )
  $bam.getentitybyname(0,$name,"Configuration")
}

function Get-BamDnsZone {
  param(
    $ConfigurationName,
    $ZoneName,
    $bam = $defaultBam
  )
  $cfg = get-BamConfiguration $ConfigurationName $bam
  $bam.getZonesByHint($cfg.id, 0, 10, "hint=$ZoneName")
}

function Get-BamDnsView {
  param(
    $ConfigurationName,
    $ViewName,
    $bam = $defaultBam
  )
  $cfg = get-BamConfiguration $ConfigurationName
  $bam.getentitybyname($cfg.id,$ViewName,"View")
}

function Get-BamServer {
  param(
    $ConfigurationName,
    $bam = $defaultBam
  )
  $cfg = get-BamConfiguration $ConfigurationName $bam
  $bam.getentities($cfg.id, "Server", 0, [int32]::MaxValue)
}

function Get-BamDevice {
  param(
    $ConfigurationName,
    $bam = $defaultBam
  )
  $cfg = get-BamConfiguration $ConfigurationName $bam
  $bam.getentities($cfg.id, "Device", 0, [int32]::MaxValue)
}

function Get-BamMac {
  param(
    $ConfigurationName,
    $bam = $defaultBam
  )
  $cfg = get-BamConfiguration $ConfigurationName $bam
  $bam.getentities($cfg.id, "MACAddress", 0, [int32]::MaxValue)
}

function Get-BamDnsRecord {
  param(
    $ZoneId,
    [ValidateSet(
      "HostRecord",
      "AliasRecord",
      "MXRecord",
      "TXTRecord",
      "SRVRecord",
      "GenericRecord",
      "HINFORecord",
      "NAPTRRecord"
    )]
    $type,
    $bam = $defaultBam
  )
  $bam.getEntities($zoneId, $type, 0, [int32]::MaxValue)
}

function Add-BamDnsHostRecord {
  param(
    $viewId,
    $name,
    $zoneName,
    $ip,
    $ttl,
    $prop = "reverseRecord=true|parentZoneName=$zoneName",
    $bam = $defaultBam
  )
  try {
    $bam.addHostRecord($viewId, "$name.$zoneName", $ip, $ttl, $prop)
  } catch {
    $err = $_.exception.message
    switch -regex ($err) {
      "IP Address doesn't belong to a Network" {
        Add-BamDnsGenericRecord -viewId $viewId `
          -name $name `
          -zonename $zoneName `
          -type "A" `
          -rdata $ip `
          -ttl $ttl `
          -bam $bam
        break
      }
      "Duplicate of another item" {
        $zone = $bam.getZonesByHint($viewid, 0, 1, "hint=$zonename")
        $record = $bam.getEntityByName($zone.id,$name,'HostRecord')
        $r = $record | Convert-BamProperty
        if ($ip -notin $r._addresses) {
          $record.properties = $record.properties -replace "addresses=", "addresses=$ip,"
          try {
            $bam.update($record)
          } catch {
            $err = $_.exception.message
            switch -regex ($err) {
              "Some of the specified addresses are reserved" {
                write-host "cannot update $name because $ip is reserved"
                break
              }
              default {
                write-host "$name.$zoneName"
                write-error $err
              }
            }
          }
        }
        $record.id
        break        
      }
      "Some of the specified addresses are reserved" {
        write-host "cannot add $name because $ip is reserved"
        break
      }
      default {
        write-host "$name.$zoneName"
        write-error $err
      }
    }
  }
}

function Add-BamDnsAliasRecord {
  param(
    $viewId,
    $name,
    $zoneName,
    $targetFqdn,
    $ttl,
    $prop = "parentZoneName=$zoneName",
    $bam = $defaultBam
  )
  try {
    $bam.addAliasRecord($viewId, "$name.$zoneName", $targetFqdn, $ttl, $prop)
  } catch {
    $err = $_.exception.message
    switch -regex ($err) {
      "Object was not found" {
        if ($targetFqdn -notmatch $zoneName) {
          Add-BamDnsExternalRecord $viewId $targetFqdn $bam
          Add-BamDnsAliasRecord $viewId $name $zonename $targetFqdn $ttl $bam
        }
        break
      }
      default {
        "$name.$zoneName"
        write-error $err
      }
    }
  }
}

function Add-BamDnsExternalRecord {
  param(
    $viewId,
    $fqdn,
    $prop = '',
    $bam = $defaultBam
  )
  $bam.addExternalHostRecord($viewId, $fqdn, $prop)
}

function Add-BamDnsSrvRecord {
  param(
    $viewId,
    $name,
    $zoneName,
    $priority,
    $port,
    $weight,
    $linkedRecordName,
    $ttl,
    $prop = "parentZoneName=$zoneName",
    $bam = $defaultBam
  )
  try {
    $bam.addSrvRecord($viewId, "$name.$zoneName", $priority, $port, $weight, $linkedRecordName, $ttl, $prop)
  } catch {
    $err = $_.exception.message
    switch -regex ($err) {
      "Duplicate of another item" {
        $zone = $bam.getZonesByHint($viewid, 0, 1, "hint=$zonename")
        $record = $bam.getEntityByName($zone.id,$name,'SRVRecord')
        $record.id
        break        
      }
      default {
        "$name.$zoneName"
        write-error $err
      }
    }
  }
}

function Add-BamDnsGenericRecord {
  param(
    $viewId,
    $name,
    $zoneName,
    [ValidateSet(
      "A", "A6", "AAAA", "AFSDB", "APL", "CAA", "CERT", "DHCID", "DNAME", 
      "DNSKEY", "DS", "ISDN", "KEY", "KX", "LOC", "MB", "MG", "MINFO", "MR", 
      "NS", "NSAP", "PX", "RP", "RT", "SINK", "SSHFP", "TLSA", "WKS", "X25"
    )]
    $type,
    $rdata,
    $ttl,
    $prop = "parentZoneName=$zoneName",
    $bam = $defaultBam
  )
  try {
    $bam.addGenericRecord($viewId, "$name.$zoneName", $type, $rdata, $ttl, $prop)
  } catch {
    $err = $_.exception.message
    switch -regex ($err) {
      "Duplicate of another item" {
        $zone = $bam.getZonesByHint($viewid, 0, 1, "hint=$zonename")
        $record = $bam.getEntityByName($zone.id,$name,'GenericRecord')
        $record.id
        break        
      }
      default {
        "$name.$zoneName"
        write-error $err
      }
    }
  }
}

Function Get-BamIPv4Block {
  param(
    [parameter(
      mandatory = $true,
      ValueFromPipelineByPropertyName,
      helpmessage = 'Container ID or container object'
    )]
    $id,
    [switch]
    $recurse = $false,
    $bam = $defaultBam
  )
  begin {}
  process {
    $subBlock = $bam.getEntities($id, 'IP4Block', 0, [int32]::MaxValue)
    $subBlock
    if ($recurse) { $subBlock | Get-BamIPv4Block -recurse -bam $bam }
  }
  end {}
}

Function Get-BamIPv4Network {
  param(
    [parameter(
      mandatory = $true,
      ValueFromPipelineByPropertyName,
      helpmessage = 'Container ID or container object'
    )]
    $id,
    $bam = $defaultBam
  )
  begin {}
  process {
    try {
      $bam.getEntities($id, 'IP4Network', 0, [int32]::MaxValue)
    } catch {
      write-verbose "Failed to get network in block $id"
    }
  }
  end {}
}
