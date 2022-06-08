# Configuration
param (
    [string]$accountId = 'company-ABC1DE',
    [string]$ApiUser = 'BOOMI_TOKEN.someuser@somedomain.com',
    [string]$repo_path  = 'C:\atomsphere-repo',
    [string]$git_executable='C:\Program Files\Git\mingw64\libexec\git-core\git.exe'
)

$script:creds = Get-Credential $ApiUser
[string]$script:filename_format = '^(?<modifiedBy>.+)-(?<componentId>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})~(?<version>\d+)\.xml$';

function Format-AtomsphereHeaders {
    return @{
        'Content-Type' = 'application/json'
      }
}

function Format-MetadataAtomsphereHeaders {
    $headers = Format-AtomsphereHeaders
    $headers['Accept'] = 'application/json'
    return $headers
}

function Get-AtomSphereMetadata([String]$sinceDate = '1921-01-04T11:52:28Z'){
    $baseURL = "https://api.boomi.com/api/rest/v1/$accountId"
    $URL     = "$baseURL/ComponentMetadata/query"
    $filter = Format-AtomsphereAllMetaData($sinceDate)
    $call = 0
    do {
        
        if ($URL -cnotlike '*queryMore') {
            $res = Invoke-WebRequest -Credential $creds -Body $filter -Method POST -Headers $(Format-MetadataAtomsphereHeaders) -Uri $URL
        } else {
            Start-Sleep -Seconds 0.2            
            $res = Invoke-WebRequest -Credential $creds -Body $partial.queryToken -Method POST -Headers $(Format-MetadataAtomsphereHeaders) -Uri $URL
        }
        
        $partial = ConvertFrom-Json -InputObject $res.Content
        if ($partial.'@type' -eq 'Error') {
            Write-Error -Message "AtomSphere metadata search returned error: $($partial.'@type')" -ErrorAction Stop
        }
        $URL = "$baseURL/ComponentMetadata/queryMore"
        $outFile = Join-Path -Path $temp_path -ChildPath "$call.psout.json"
        New-Item $outFile >$null
        Set-Content -Path $outFile -Value $res.Content
        $call += 1
        Write-Debug "Found query token #$($partial.queryToken)#"
    } while ($partial.queryToken.length -gt 0)
}

function Format-AtomsphereAllMetaData([String]$sinceDate) {
    return '{"QueryFilter" : {"expression" : {"operator" : "and", "nestedExpression" : [{"argument" : ["mdm.domain"],"operator":"NOT_EQUALS","property":"Type"}, {"argument" : ["'+ $sinceDate +'"],"operator":"GREATER_THAN_OR_EQUAL","property":"modifiedDate"}]}}}'
}

function Format-AtomsphereGetComponents {
    param([Array]$componentIds)
    $components = @()
    $componentIds.foreach{
        $components += @{ id = $_ }
    }
    $req = @{
        type = 'GET'
        request = $components
    }
    return ConvertTo-Json -Depth 4 $req
}

function Get-AllComponents {
    $fileQueue = @()
    @(Get-ChildItem "$temp_path\*.psout.json") | Get-Content -Raw -Encoding UTF8  | ConvertFrom-Json | foreach-object { $_.result } | foreach-object {
        Write-Debug "This componentId: $($_.componentId)"
        $fileQueue += "$($_.componentId)~$($_.version)"
        if ($fileQueue.Count -eq 5) {
            Get-AtomsphereComponents -Id $call -Directory $temp_path -Components $fileQueue
            $call += 1
            $fileQueue = @()
        }
    }
    Get-AtomsphereComponents -Id $call -Directory $temp_path -Components $fileQueue
}

function Get-AtomsphereComponents([Array]$Components, [int]$Id, [String]$Directory) {
    if ($Components.Count -lt 1) {
        return
    }
    else {
        if ($Id -ne 0) {
            Start-Sleep -seconds 0.2
        }
        $URL = "https://api.boomi.com/api/rest/v1/$accountId/Component/bulk"
        $query = $(Format-AtomsphereGetComponents -componentIds $Components)
        $headers = Format-AtomsphereHeaders
        $headers['Accept'] = 'application/xml'
        $res = Invoke-WebRequest -Credential $creds -Body $query -Method POST -Headers $headers -Uri $URL
        Split-ComponentsBulk($res.Content)
    }
}


function Split-ComponentsBulk([xml]$bulkContent) {
    $bulkContent.BulkResult.response | Where-Object -Property statusCode -eq 200 | ConvertTo-SeparateResultFiles
    $bulkContent.BulkResult.response | Where-Object -Property statusCode -ne 200 | foreach-object {
        Write-Warning "Non-success from Atomsphere bulk retrieval: $_"
    }
}
    
function Join-GitHistory {
    $this_commit = @{};
    $this_user = '';
    $file=$null
    $stageDir = Get-ChildItem -Path $staging_directory 
    $stageDir = ($stageDir | Sort-Object -Property LastWriteTime,Name)
    for ($i=0 ; $i -lt $stageDir.Count; $i++){
        $file = $stageDir[$i]
        $file -Match $filename_format >$null
        if (($i -eq 0 -or $this_user -eq $Matches.modifiedBy) -and
            -not $this_commit.ContainsKey($Matches.componentId)
            )
        {
            $this_user = $Matches.modifiedBy #needed for the first iteration
            $this_commit.Add($Matches.componentId, $file)
        } else {
            $this_user = $Matches.modifiedBy #either outcome of the if but before the add-gitcommit
            Add-GitCommit -user_email $this_user -user_name $this_user -date $file.LastWriteTime -files $this_commit.Values
            $this_commit.Clear()
            $this_commit.Add($Matches.componentId, $file)
        }
    }
    if ($this_commit.Count -gt 0) {
        Add-GitCommit -user_email $this_user -user_name $this_user -date $file.LastWriteTime -files $this_commit.Values
    }
}

function ConvertTo-SeparateResultFiles {
    process{
        $componentId = $_.Result.componentId
        $version = $_.Result.version
        $modifiedBy = $_.Result.modifiedBy
        $modifiedDate = Get-date -Date $_.Result.modifiedDate
        $createdDate = Get-date -Date $_.Result.createdDate
        $outPath = Join-path -Path $staging_directory -ChildPath "$modifiedBy-$componentId~$version.xml"
        $resultXml = New-Object -TypeName XML
        $resultXml.AppendChild($resultXml.CreateXmlDeclaration("1.0","UTF-8",$null)) > $null
        $resultXml.AppendChild($resultXml.ImportNode($_.Result, $true)) > $null
        $resultXml.Save($outPath)
        $file = get-item($outPath)
        $file.CreationTimeUtc = $createdDate
        $file.LastWriteTimeUtc = $modifiedDate
    }
}

function Add-GitCommit( [String]$user_email, [String]$user_name, [DateTime]$date, [Array]$files ) {
    $repo = get-item -Path $component_directory
    foreach ($file in $files) {
        $file.FullName -match $filename_format >$null
        $id = $Matches.componentId
        $destination = join-path -path $repo -childpath "$id.xml"
        if (Test-Path $destination) {
            Remove-Item -Path $destination
        }
        Move-Item -Path $file.FullName -Destination $destination
    }
    
    $name_opt = "user.name=$user_email"
    $email_opt = "user.email=$user_email"
    $date_opt = Get-Date -Date $date -Format o
    $date_opt = "--date=$date"
    & $git_executable -C $repo add .
    & $git_executable -C $repo -c $name_opt -c $email_opt commit $date_opt '--allow-empty-message' '--message='
}

function New-Directories {
    $script:temp_path = Convert-Path (New-TempDir)
    New-Item -Path $repo_path -ItemType Directory -Force >$null
    $script:component_directory = Join-Path -Path $repo_path -ChildPath 'components'
    $script:staging_directory   = Join-Path -Path $temp_path -ChildPath 'components'
    New-Item -Path $component_directory -ItemType Directory -Force >$null
    New-Item -Path $staging_directory -ItemType Directory -Force >$null
}

function New-TempDir([string]$DirectorySuggestedName='boomi-git') {
    [string]$temp_dir_root = [system.io.path]::GetTempPath()
    $old_preference = $ErrorActionPreference
    [boolean]$try_again = $true
    while($try_again) {
        $temp_dir_path = Join-Path -Path $temp_dir_root -ChildPath $DirectorySuggestedName
        $ErrorActionPreference = "Stop" # Causes New-Item to throw an exception on failure
        try {
            $temp_dir = New-Item -Path $temp_dir_path -ItemType Directory
            $try_again = $false
        }
        catch [System.IO.IOException] {
            Write-Warning "Could not create new temp directory $temp_dir_path"
        }
        $ErrorActionPreference = $old_preference
        $DirectorySuggestedName = New-Guid
    }
    return $temp_dir
}


$clock = [system.diagnostics.stopwatch]::StartNew()
New-Directories
$clock.Elapsed.TotalMinutes
$gitdir = Join-Path -Path $repo_path -ChildPath '.git'
if (Test-Path $gitdir) {
    Write-Output "Found existing git repository"
    $git_author_datetime = & $git_executable -C $repo_path log -1 --format='format:%aI'
    $delta_datetime = Get-Date -Date $git_author_datetime
    $delta_datetime_utc = $delta_datetime.ToUniversalTime()
    $delta_datetime_iso = get-date -Date $delta_datetime_utc -Format "yyyy-MM-dd'T'HH:mm:ss'Z'"
    Get-AtomSphereMetadata -sinceDate $delta_datetime_iso
}
else {
    & $git_executable init $repo_path
    Get-AtomSphereMetadata
}
$clock.Elapsed.TotalMinutes
Get-AllComponents
$clock.Elapsed.TotalMinutes
Join-GitHistory
$clock.Elapsed.TotalMinutes
Remove-Item -Recurse -Path $temp_path