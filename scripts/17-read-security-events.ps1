<#
.SYNOPSIS
    Reads account-management events from the Security log and shows who did what to which account.

.DESCRIPTION
    Pulls recent events for account created, enabled, password reset, disabled and deleted, and for account lockout, from the
    Security log of this domain controller. It prints the time, event ID, a plain-English meaning, the account acted on, and the
    account that did it. An optional name narrows the list to one user.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01, after 16-audit-policy.ps1.

    RULES THIS SCRIPT FOLLOWS
    - It only reads. It changes nothing.
    - The event IDs and the meaning of each are listed in the configuration block, so a new event is a one-line change.
    - It limits the number of events so it does not pull a huge log.

    KNOWLEDGE
    - Event IDs: 4720 account created, 4722 enabled, 4724 password reset attempt, 4725 disabled, 4726 deleted, 4740 locked out.
    - Target = the account that was acted on (TargetUserName). By = the account that did it (SubjectUserName).
    - By shows DC01$ in the lab because az vm run-command runs as SYSTEM, the computer account. When an admin
      acts from their own session, By shows the admin's name. That is what an investigator wants to see.
    - To search for one user: set $targetUser. Per-user searching in production is usually done in the SIEM (Splunk) with
      the same IDs, or with Get-WinEvent -FilterXPath on the event data.
    - The log shows what happened AFTER auditing was enabled. Accounts created before script 16 have no creation event.
    - Event data is ordered. This script reads Properties[0] as the target and Properties[4] as the subject, which holds for
      these IDs.

    PITFALLS
    - Group events such as 4728 and 4738 have a different property layout, so this script does not handle them.
    - If the log is empty, auditing was not on at the time. Check 16-audit-policy.ps1.
    - Get-WinEvent throws "No events were found" when nothing matches. This script hides that error and prints an empty list.

    EXPECTED OUTPUT
    A table of up to 50 events, newest first, for example 4720 created, 4722 enabled, 4724 password reset, with By = DC01$.
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$eventIds   = 4720, 4722, 4724, 4725, 4726, 4740        # CHANGE: event IDs to read.
$maxEvents  = 50                                        # CHANGE: how many events to pull at most.
$targetUser = ""                                        # CHANGE: an account name to show only that user, or leave blank for all.
$meaning = @{                                           # CHANGE: plain-English label for each event ID.
    4720 = "Account created"
    4722 = "Account enabled"
    4724 = "Password reset attempt"
    4725 = "Account disabled"
    4726 = "Account deleted"
    4740 = "Account locked out"
}
# ============================================================================================

$events = Get-WinEvent -FilterHashtable @{ LogName = "Security"; Id = $eventIds } -MaxEvents $maxEvents -ErrorAction SilentlyContinue

$rows = foreach ($event in $events) {
    [pscustomobject]@{
        Time   = $event.TimeCreated
        Id     = $event.Id
        What   = $meaning[[int]$event.Id]
        Target = $event.Properties[0].Value
        By     = $event.Properties[4].Value
    }
}

if ($targetUser) {
    $rows = $rows | Where-Object { $_.Target -eq $targetUser }
}

$rows | Format-Table -AutoSize | Out-String -Width 200

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@17-read-security-events.ps1" --query "value[0].message" -o tsv
# ANOTHER ENVIRONMENT: on a domain controller, open PowerShell as Administrator (or a member of Event Log Readers), edit the
# CONFIGURATION block, then run:
#   .\17-read-security-events.ps1
# FOR ONE USER interactively:
#   Get-WinEvent -FilterHashtable @{LogName="Security";Id=4720,4722,4724,4725,4726,4740} | Where-Object { $_.Properties[0].Value -eq "kpark" }
