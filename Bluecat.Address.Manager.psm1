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
  $cfg = get-BamConfiguration $ConfigurationName
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
  $cfg = get-BamConfiguration $ConfigurationName
  $bam.getentities($cfg.id, "Server", 0, [int32]::MaxValue)
}

function Get-BamDnsRecord {
  param(
    $Zone,
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
  $bam.getEntities($zone.id, $type, 0, [int32]::MaxValue)
}

function Add-BamDnsHostRecord {
  param(
    $view,
    $fqdn,
    $ip,
    $ttl,
    $bam = $defaultBam
  )
  $bam.addHostRecord($view.id, $fqdn, $ip, $ttl, "reverseRecord=true")
}

function Add-BamDnsAliasRecord {
  param(
    $view,
    $fqdn,
    $targetFqdn,
    $ttl,
    $bam = $defaultBam
  )
  $bam.addAliasRecord($view.id, $fqdn, $targetFqdn, $ttl, "")
}
