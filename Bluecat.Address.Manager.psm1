function Convert-BamProperty {
  param (
    [parameter(
      mandatory = $true,
      valueFromPipeline = $true
    )]
    [psobject] $bamObject
  )
  begin {}
  process {
    $prop = $bamObject.properties.trim("|") -split "\|"
    foreach ($p in $prop) {
      $member = $p -split "="
      $bamObject | Add-Member -NotePropertyName $member[0] -NotePropertyValue $member[1]
    }
    $bamObject | select -property * -excludeproperty properties
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
    $fqdn,
    $ip,
    $ttl,
    $bam = $defaultBam
  )
  $bam.addHostRecord($viewId, $fqdn, $ip, $ttl, "reverseRecord=true")
}

function Add-BamDnsAliasRecord {
  param(
    $viewId,
    $fqdn,
    $targetFqdn,
    $ttl,
    $bam = $defaultBam
  )
  $bam.addAliasRecord($viewId, $fqdn, $targetFqdn, $ttl, "")
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
