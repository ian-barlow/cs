param(
    [Parameter()][String]$subsRequest
)

If ($subsRequest -eq "") {
    $context = Get-AzContext
    $env:SUB_NAME = $context.Name.split(' ')[0]
    $env:SUB_ID = $context.Subscription
    $env:SUB_SHORT = $(Get-AzTag -ResourceId ("/subscriptions/"+$context.Subscription)).Properties.TagsProperty['shortname']

    Write-Host $env:SUB_NAME $env:SUB_ID $env:SUB_SHORT
}
Else {
    
    $cachefile = join-path -path $HOME -ChildPath ".azure" -AdditionalChildPath "script_cs.json"
    $subsAll = Get-AzSubscription | Where-Object {$_.State -eq "Enabled"} | Select-Object Id,Name

    # Don't make a new cache file unless command line flagged - todo
    $cacheNew = $false

    # Make a new cache file if we don't have one
    if (!(test-path $cachefile)) {
        $cacheNew = $true
    }

    # Create, or zero cache file, and add dummy record to empty file
    if ($cacheNew -eq $true) {
        New-Item -ItemType File -Path $cachefile -force -ErrorAction Stop | Out-Null
        $subObject = [PSCustomObject]@{
            Id = ""
            Name = ""
            Shortname = ""
        }
        $cache += $subObject
        $cache | ConvertTo-Json -Depth 1 | Set-Content -Path $cachefile -ErrorAction Stop
    }

    $cache = Get-Content -path $cachefile | ConvertFrom-Json

    # Find list of subs mising from cachefile, and subs in cachefile that don't exist
    $cacheMisses = Compare-Object $cache.Id $subsAll.Id | where-object {$_.SideIndicator -eq "=>"} | Select-Object InputObject
    
    # Find list cached record without matching subscriptions (removed subs & dummy record)
    # $cacheExtra = Compare-Object $cache.Id $subsAll.Id | where-object {$_.SideIndicator -eq "<="} | Select-Object InputObject

    # Add cache misses to the cachefile
    foreach ($sub in $subsAll) {
        if ($cacheMisses -match $sub.Id) {
            $subTags = Get-AzTag -ResourceId ("/subscriptions/"+$sub.Id)
            if ($null -ne $subTags.Properties.TagsProperty) { 
                $Shortname = $subTags.Properties.TagsProperty['shortname'] 
            } 
            else { 
                $Shortname = $null
            }
            $subObject = [PSCustomObject]@{
                Id = $sub.Id
                Name = $sub.Name
                Shortname = $Shortname
            }
            $cache = [array]$cache + $subObject
        }
    }

    $cache | ConvertTo-Json -Depth 1 | Set-Content -Path $cachefile -ErrorAction Stop | Out-Null
    
    $subsMatched = $cache -match $subsRequest
    switch ($subsMatched.count) {
        0 {  
            # bailout, nothing matched
            Write-Host "No subscription found matching your query:", $subsRequest
        }
        1 {  
            # One (exact?) match, this must be what we wanted
            $env:SUB_NAME = $subsMatched[0].Name
            $env:SUB_ID = $subsMatched[0].Id
            $env:SUB_SHORT = $subsMatched[0].Shortname
            Set-AzContext -SubscriptionId $subsMatched[0].Id | Out-Null
            Write-host "Found matching subscription, setting context, setting environment variables:"
            Write-Host
            Write-Host "  (env:SUB_NAME)  Name      :", $subsMatched[0].Name
            Write-Host "  (env:SUB_ID)    Id        :", $subsMatched[0].Id
            Write-Host "  (env:SUB_SHORT) Shortname :", $subsMatched[0].Shortname
        }
        Default {
            # Many matches, print list, maybe allow selection from list
            write-host "Potentially matching subscriptions found:" 
            $subsMatched
        }
    }
}