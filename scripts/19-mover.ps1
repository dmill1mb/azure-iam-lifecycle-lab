<#
.SYNOPSIS
    Handles internal transfers: swaps department groups, updates department and title, moves the account to the new OU, and records the ticket.

.DESCRIPTION
    Reads a CSV list of movers (username, new department, new title, ticket). In dry-run mode it only reports what it would do.
    In real mode it removes the old department group, adds the new one, updates Department and Title, writes the ticket and
    date into the Description (keeping the old text), and moves the account to the new department OU.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01, after 11-onboard-users.ps1.

    RULES THIS SCRIPT FOLLOWS
    - DRY RUN IS THE DEFAULT. Set $dryRun to $false deliberately.
    - Access follows the role. The old department group is removed so the person does not keep access they no longer need.
    - Every change is traceable: the Description gets the ticket, the date, the old and new department, and the old text.
    - It checks that the target OU and group exist BEFORE changing anything, so a failure cannot leave a half-moved account.
    - It skips anyone not found, disabled, or already in the new department, so running it twice does nothing the second time.

    KNOWLEDGE
    - This is the "mover" step of joiner, mover, leaver. Movers are where access creep happens: people collect access as they change roles.
    - Only the old DEPARTMENT group is removed. Any other groups (project groups, special access) are left alone and reported,
      because they need a manager's review, not an automatic removal.
    - The move changes which Group Policy Objects (GPOs) apply, because GPOs are linked to OUs. In this lab, moving from Finance to IT removes
      the command prompt and PowerShell restrictions.
    - The move can change the password policy too. SG-IT carries the stricter fine-grained policy (PSO, Password Settings Object).
      Verified in the lab: after the move, Get-ADUserResultantPasswordPolicy showed PSO-IT-Admins (16 characters, lockout after 3).
    - The Description is written BEFORE the move, because the move changes the account's distinguished name.

    PITFALLS
    - The target department OU and its SG- group must exist (10-create-structure.ps1).
    - Nobody else is notified. Mailbox, application and file access are separate systems.
    - A user's department comes from the Department field. If that field is empty, the old group cannot be worked out and nothing is removed.

    EXPECTED OUTPUT
    Dry run: "DRY RUN: would remove SG-Finance, add SG-IT, move to OU=IT (keeps N other group(s))". Real run: "Moved Finance to IT".
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$dryRun      = $true                                       # CHANGE: $true = report only. Set $false to make the changes.
$domainDN    = (Get-ADDomain).DistinguishedName            # CHANGE: leave as is to use the current domain.
$staffOU     = "Staff"                                     # CHANGE: the top OU that holds the department OUs.
$groupPrefix = "SG-"                                       # CHANGE: your group naming prefix.
$notePrefix  = "Mover ticket"                              # CHANGE: text written at the start of the new Description.

# CHANGE: replace this list with your movers. For a file use: $movers = Import-Csv "C:\path\movers.csv"
$csv = @"
Username,NewDepartment,NewTitle,Ticket
ohaddad,IT,Help Desk Technician,INC-3001
"@
$movers = $csv | ConvertFrom-Csv
# ============================================================================================

Import-Module ActiveDirectory

$results = @()
$today = Get-Date -Format "yyyy-MM-dd"

foreach ($mover in $movers) {
    $user = Get-ADUser -Filter "SamAccountName -eq '$($mover.Username)'" -Properties Department, Title, Description, MemberOf

    if (-not $user) {
        $results += [pscustomobject]@{ Username = $mover.Username; Ticket = $mover.Ticket; Result = "Skipped (not found)" }
        continue
    }
    if (-not $user.Enabled) {
        $results += [pscustomobject]@{ Username = $mover.Username; Ticket = $mover.Ticket; Result = "Skipped (account is disabled)" }
        continue
    }

    $oldDept  = $user.Department
    $newDept  = $mover.NewDepartment
    $oldGroup = "$groupPrefix$oldDept"
    $newGroup = "$groupPrefix$newDept"
    $targetOU = "OU=$newDept,OU=$staffOU,$domainDN"

    if ($oldDept -eq $newDept) {
        $results += [pscustomobject]@{ Username = $mover.Username; Ticket = $mover.Ticket; Result = "Skipped (already in $newDept)" }
        continue
    }
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$targetOU'")) {
        $results += [pscustomobject]@{ Username = $mover.Username; Ticket = $mover.Ticket; Result = "Skipped (OU for $newDept not found)" }
        continue
    }
    if (-not (Get-ADGroup -Filter "Name -eq '$newGroup'")) {
        $results += [pscustomobject]@{ Username = $mover.Username; Ticket = $mover.Ticket; Result = "Skipped (group $newGroup not found)" }
        continue
    }

    $oldGroupObject = Get-ADGroup -Filter "Name -eq '$oldGroup'"
    $oldGroupDN     = if ($oldGroupObject) { $oldGroupObject.DistinguishedName } else { $null }
    $inOldGroup     = $oldGroupDN -and ($user.MemberOf -contains $oldGroupDN)
    $otherGroups    = @($user.MemberOf | Where-Object { $_ -ne $oldGroupDN }).Count

    if ($dryRun) {
        $removeText = if ($inOldGroup) { "remove $oldGroup, " } else { "" }
        $results += [pscustomobject]@{ Username = $mover.Username; Ticket = $mover.Ticket; Result = "DRY RUN: would ${removeText}add $newGroup, move to OU=$newDept (keeps $otherGroups other group(s))" }
        continue
    }

    if ($inOldGroup) {
        Remove-ADGroupMember -Identity $oldGroupDN -Members $user.DistinguishedName -Confirm:$false
    }
    Add-ADGroupMember -Identity $newGroup -Members $user.DistinguishedName

    Set-ADUser -Identity $user.DistinguishedName `
        -Department $newDept `
        -Title $mover.NewTitle `
        -Description "$notePrefix $($mover.Ticket) on ${today}: $oldDept to $newDept. Was: $($user.Description)"

    Move-ADObject -Identity $user.DistinguishedName -TargetPath $targetOU

    $results += [pscustomobject]@{ Username = $mover.Username; Ticket = $mover.Ticket; Result = "Moved $oldDept to $newDept" }
}

$results | Format-Table -AutoSize | Out-String -Width 200

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   Dry run first (default):
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@19-mover.ps1" --query "value[0].message" -o tsv
#   Or, with the common commands loaded (see the README):  Invoke-Lab 19-mover.ps1
#   Then change $dryRun to $false in the CONFIGURATION block and run the same command again.
# ANOTHER ENVIRONMENT: on a domain controller, open PowerShell as a Domain Admin, replace the CSV with the approved
# transfer list from your ticket, run once as a dry run, read the output, set $dryRun to $false, then run:
#   .\19-mover.ps1
# TO VERIFY: Get-ADUser -Identity <name> -Properties Department,Title,MemberOf,Description | Format-List
