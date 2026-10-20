<#
.SYNOPSIS
    Audits user accounts against rules for least privilege, correct group membership, and documentation. Read-only.

.DESCRIPTION
    Checks the Staff and Disabled OUs, the privileged groups and the default Users container, and records every
    problem as a finding (area, check, account, detail). Prints a summary by check and a detail table. With
    $outputCsv set to $true it prints CSV only, so you can save it on your computer.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01, after the joiner, mover and leaver scripts.

    RULES THIS SCRIPT FOLLOWS
    - It only reads. It changes nothing in the directory.
    - Built-in accounts (Guest, krbtgt, DefaultAccount) are excluded so they do not drown real findings.
    - A finding is a lead for a person to review, not a verdict.
    - The output contains usernames. Do not commit saved CSV files to a public repository.

    KNOWLEDGE
    - Areas: Least privilege (NIST AC-6), Right group, Organized (documented), Stale. NIST AC-2 covers account management in general.
    - Privileged groups are checked recursively, so a user hidden inside a nested group is still found.
    - The approved list ($approvedPrivileged) is yours to maintain. Anyone else in a privileged group is a finding.
    - LastLogonTimestamp is only updated about every 14 days, so a stale threshold below about 14 days gives false alarms.
    - New accounts get a grace period: a "never logged on" finding only appears once the account is older than $staleDays.
    - Expected after the lab work so far: a clean result. Plant a problem on purpose to see a finding.

    PITFALLS
    - If the department OUs are named differently from the Department field, every user is flagged. Keep them aligned.
    - A user in a nested group that is not privileged is not a finding. The check follows the named privileged groups only.
    - CSV mode prints nothing when there are no findings.

    EXPECTED OUTPUT
    "Accounts checked", "Findings: N", then a table of findings by check and a detail table.
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$domainDN           = (Get-ADDomain).DistinguishedName      # CHANGE: leave as is to audit the current domain.
$staffOU            = "Staff"                               # CHANGE: top OU that holds the department OUs.
$disabledOU         = "Disabled"                            # CHANGE: OU where leavers are parked.
$groupPrefix        = "SG-"                                 # CHANGE: your department group prefix.
$staleDays          = 30                                    # CHANGE: days without a logon before an account is stale.
$ticketPattern      = "INC-\d+"                             # CHANGE: how your ticket numbers look (regular expression).
$privilegedGroups   = "Domain Admins", "Enterprise Admins", "Schema Admins", "Administrators", "Account Operators", "Backup Operators"   # CHANGE
$approvedPrivileged = "Administrator", "labadmin"           # CHANGE: accounts allowed in the privileged groups.                  
$builtInAccounts    = "Guest", "krbtgt", "DefaultAccount"   # CHANGE: built-in accounts to leave out.
$outputCsv          = $false                                # CHANGE: $true prints CSV only, for saving.
# ============================================================================================

Import-Module ActiveDirectory

$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param([string]$Area, [string]$Check, [string]$Account, [string]$Detail)
    $findings.Add([pscustomobject]@{ Area = $Area; Check = $Check; Account = $Account; Detail = $Detail })
}

$props      = "Department", "Title", "Description", "MemberOf", "PasswordNeverExpires", "LastLogonTimestamp", "Enabled", "whenCreated"
$staffDN    = "OU=$staffOU,$domainDN"
$disabledDN = "OU=$disabledOU,$domainDN"
$now        = Get-Date

$staff    = @(Get-ADUser -Filter * -SearchBase $staffDN -Properties $props)
$parked   = @(Get-ADUser -Filter * -SearchBase $disabledDN -Properties Enabled)
$deptNames = @(Get-ADOrganizationalUnit -Filter * -SearchBase $staffDN -SearchScope OneLevel | Select-Object -ExpandProperty Name)

# ---- Per-user checks on everyone in Staff ----
foreach ($user in $staff) {
    $sam        = $user.SamAccountName
    $dept       = $user.Department
    $groupNames = @($user.MemberOf | ForEach-Object { ($_ -split ",")[0] -replace "^CN=" })

    # Least privilege
    if ($user.PasswordNeverExpires) {
        Add-Finding "Least privilege" "Password never expires" $sam "PasswordNeverExpires is set"
    }

    # Right group
    if (-not $dept) {
        Add-Finding "Organized" "Missing department" $sam "Department field is empty"
    }
    else {
        if ($user.DistinguishedName -notlike "*,OU=$dept,$staffDN") {
            Add-Finding "Right group" "Department and OU differ" $sam "Department is $dept but the account is in $($user.DistinguishedName)"
        }
        if ($groupNames -notcontains "$groupPrefix$dept") {
            Add-Finding "Right group" "Missing department group" $sam "Not a member of $groupPrefix$dept"
        }
        foreach ($other in $deptNames) {
            if ($other -ne $dept -and $groupNames -contains "$groupPrefix$other") {
                Add-Finding "Right group" "Also in another department group" $sam "Member of $groupPrefix$other"
            }
        }
    }

    # Documented and organized
    if (-not $user.Title) {
        Add-Finding "Organized" "Missing title" $sam "Title field is empty"
    }
    if (-not $user.Description -or $user.Description -notmatch $ticketPattern) {
        Add-Finding "Organized" "No ticket in Description" $sam "Description is: $($user.Description)"
    }

    # Stale accounts
    if ($user.Enabled) {
        $accountAge = ($now - $user.whenCreated).Days
        if (-not $user.LastLogonTimestamp) {
            if ($accountAge -gt $staleDays) {
                Add-Finding "Stale" "Never logged on" $sam "Created $accountAge days ago, no logon recorded"
            }
        }
        else {
            $lastLogon = [DateTime]::FromFileTime($user.LastLogonTimestamp)
            $daysSince = ($now - $lastLogon).Days
            if ($daysSince -gt $staleDays) {
                Add-Finding "Stale" "No recent logon" $sam "Last logon $daysSince days ago"
            }
        }
    }
}

# ---- Leavers parked in the Disabled OU should be disabled ----
foreach ($user in $parked) {
    if ($user.Enabled) {
        Add-Finding "Organized" "Enabled account in the Disabled OU" $user.SamAccountName "The account is enabled but sits in OU=$disabledOU"
    }
}

# ---- Disabled accounts that are not in the Disabled OU ----
$allDisabled = @(Get-ADUser -Filter 'Enabled -eq $false')
foreach ($user in $allDisabled) {
    if ($builtInAccounts -notcontains $user.SamAccountName -and $user.DistinguishedName -notlike "*$disabledDN") {
        Add-Finding "Organized" "Disabled account outside the Disabled OU" $user.SamAccountName $user.DistinguishedName
    }
}

# ---- Privileged groups ----
foreach ($groupName in $privilegedGroups) {
    $members = @(Get-ADGroupMember -Identity $groupName -Recursive -ErrorAction SilentlyContinue | Where-Object { $_.objectClass -eq "user" })
    foreach ($member in $members) {
        if ($approvedPrivileged -notcontains $member.SamAccountName) {
            Add-Finding "Least privilege" "Unapproved privileged member" $member.SamAccountName "Member of $groupName"
        }
    }
}

# ---- Empty department groups ----
$deptGroups = @(Get-ADGroup -Filter "Name -like '$groupPrefix*'")
foreach ($group in $deptGroups) {
    if (@(Get-ADGroupMember -Identity $group).Count -eq 0) {
        Add-Finding "Organized" "Empty group" $group.Name "The group has no members"
    }
}

# ---- Accounts left in the default Users container ----
$defaultContainer = @(Get-ADUser -Filter * -SearchBase "CN=Users,$domainDN" -SearchScope OneLevel)
foreach ($user in $defaultContainer) {
    if ($builtInAccounts -notcontains $user.SamAccountName -and $approvedPrivileged -notcontains $user.SamAccountName) {
        Add-Finding "Organized" "Account in the default Users container" $user.SamAccountName $user.DistinguishedName
    }
}

# ---- Output ----
if ($outputCsv) {
    $findings | ConvertTo-Csv -NoTypeInformation
    return
}

"Accounts checked: $($staff.Count) in $staffOU, $($parked.Count) in $disabledOU"
"Findings: $($findings.Count)"
if ($findings.Count -gt 0) {
    ""
    "=== Findings by check ==="
    $findings | Group-Object Check | Sort-Object Count -Descending | Select-Object Count, Name | Format-Table -AutoSize | Out-String
    "=== Details ==="
    $findings | Sort-Object Area, Check, Account | Format-Table -AutoSize -Wrap | Out-String -Width 250
}

# ===================== HOW TO RUN =====================
# LAB (from your laptop, inside the scripts folder, after az login and Set-Lab):
#   Invoke-Lab 20-user-audit.ps1
#   To save a CSV: set $outputCsv to $true in the CONFIGURATION block, then run
#   Invoke-Lab 20-user-audit.ps1 | Out-File .\user-audit.csv -Encoding utf8
#   (do not commit the CSV to a public repository; it contains usernames)
# ANOTHER ENVIRONMENT: on a domain controller (or a server with RSAT), open PowerShell as a Domain Admin,
# edit the CONFIGURATION block (OU names, ticket pattern, approved privileged accounts), then run:
#   .\20-user-audit.ps1
