<#
.SYNOPSIS
    Offboards leavers safely: disables the account, removes group memberships, notes the ticket, and moves it to the Disabled OU. Never deletes.

.DESCRIPTION
    Reads a CSV list of leavers (username and ticket). In dry-run mode it only reports what it would do. In real mode it disables each
    account, removes it from every group, writes the ticket and date into the Description (keeping the old description), and moves
    it to the Disabled OU. Prints a result table.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01, after 11-onboard-users.ps1.

    RULES THIS SCRIPT FOLLOWS
    - DRY RUN IS THE DEFAULT. $dryRun = $true shows what would happen and changes nothing. Set it to $false deliberately.
    - Disable first, delete later. The script never deletes an account. Deletion happens after the retention period, by a separate decision.
    - Every change is traceable: the Description gets the ticket number, the date, and what the description used to say.
    - It skips anyone not found, and anyone already processed, so running it twice does not repeat work.
    - Group memberships are removed so that a re-enabled account does not quietly regain old access.

    KNOWLEDGE
    - This is the "leaver" step of joiner, mover, leaver. Leavers are the biggest audit finding in most companies: accounts left active.
    - Order inside the script matters: the Description is written BEFORE the move, because the move changes the account's distinguished
      name (its full path).
    - Domain Users is the primary group and does not appear in MemberOf, so it is not removed.
    - Disabling blocks new sign-ins. Existing Kerberos tickets can work until they expire, so for urgent cases also reset the password
      and revoke sessions in cloud apps.
    - The change is logged by the domain controller as event 4725 (disabled). Check it with 17-read-security-events.ps1.
    - Recovery: because the account was only disabled and moved, you can re-enable it and move it back. A deleted account would need the Recycle Bin.

    PITFALLS
    - The Disabled OU must exist (10-create-structure.ps1). If it does not, the move fails after the disable.
    - Mailboxes, home folders and cloud accounts are separate systems. This script covers the directory only.
    - An account marked as already processed is recognized by the text "Leaver ticket" at the start of its Description.

    EXPECTED OUTPUT
    Dry run: "DRY RUN: would disable, remove N group(s), move to Disabled OU" for each leaver. Real run: "Disabled, removed N group(s), moved to Disabled OU".
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$dryRun      = $true                                           # CHANGE: $true = report only. Set $false to make the changes.
$domainDN    = (Get-ADDomain).DistinguishedName                # CHANGE: leave as is to use the current domain.
$disabledOU  = "OU=Disabled,$domainDN"                         # CHANGE: where leavers are parked.
$notePrefix  = "Leaver ticket"                                 # CHANGE: text that marks an account as processed.

# CHANGE: replace this list with your leavers. For a file use: $leavers = Import-Csv "C:\path\leavers.csv"
$csv = @"
Username,Ticket
lortega,INC-2001
dwhitfield,INC-2002
"@
$leavers = $csv | ConvertFrom-Csv
# ============================================================================================

Import-Module ActiveDirectory

$results = @()
$today = Get-Date -Format "yyyy-MM-dd"

foreach ($leaver in $leavers) {
    $user = Get-ADUser -Filter "SamAccountName -eq '$($leaver.Username)'" -Properties MemberOf, Description

    if (-not $user) {
        $results += [pscustomobject]@{ Username = $leaver.Username; Ticket = $leaver.Ticket; Result = "Skipped (not found)" }
        continue
    }
    if ($user.Description -like "$notePrefix*") {
        $results += [pscustomobject]@{ Username = $leaver.Username; Ticket = $leaver.Ticket; Result = "Skipped (already processed)" }
        continue
    }

    $groups = @($user.MemberOf)

    if ($dryRun) {
        $results += [pscustomobject]@{ Username = $leaver.Username; Ticket = $leaver.Ticket; Result = "DRY RUN: would disable, remove $($groups.Count) group(s), move to Disabled OU" }
        continue
    }

    Disable-ADAccount -Identity $user.DistinguishedName

    foreach ($group in $groups) {
        Remove-ADGroupMember -Identity $group -Members $user.DistinguishedName -Confirm:$false
    }

    Set-ADUser -Identity $user.DistinguishedName -Description "$notePrefix $($leaver.Ticket) on $today. Was: $($user.Description)"

    Move-ADObject -Identity $user.DistinguishedName -TargetPath $disabledOU

    $results += [pscustomobject]@{ Username = $leaver.Username; Ticket = $leaver.Ticket; Result = "Disabled, removed $($groups.Count) group(s), moved to Disabled OU" }
}

$results | Format-Table -AutoSize | Out-String -Width 200

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   Dry run first (default):
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@18-leaver-offboarding.ps1" --query "value[0].message" -o tsv
#   Then change $dryRun to $false in the CONFIGURATION block and run the same command again.
# ANOTHER ENVIRONMENT: on a domain controller, open PowerShell as a Domain Admin, replace the CSV with the approved leaver
# list from your ticket, run once as a dry run, read the output, set $dryRun to $false, then run:
#   .\18-leaver-offboarding.ps1
# TO VERIFY: Get-ADUser -Identity <name> -Properties Enabled, MemberOf, Description | Format-List Enabled, MemberOf, Description, DistinguishedName
