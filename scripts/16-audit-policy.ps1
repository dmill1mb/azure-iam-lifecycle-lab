<#
.SYNOPSIS
    Turns on auditing for account management, logon, Kerberos and directory changes so the Security log records who did what.

.DESCRIPTION
    Uses auditpol to enable success and failure auditing on eight subcategories, then prints the current setting
    for the Account Management and Logon/Logoff categories.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01.

    RULES THIS SCRIPT FOLLOWS
    - Both Success and Failure are audited, because attacks show up as failures.
    - The audit list is a table in the configuration block, so a change is made in one place.
    - It prints the policy afterward so you can read it. A message that said "success" is not proof.

    KNOWLEDGE
    - Events are only written after auditing is on. The accounts created before this script have no creation events.
      This is why a log search for old changes finds nothing.
    - Four areas are covered: Account Management (4720 created, 4722 enabled, 4724 password reset, 4725 disabled, 4726 deleted,
      4728 added to a group), Logon/Logoff (4740 lockout), Account Logon with Kerberos (ticket requests) and DS Access
      (directory object changes).
    - The subcategories used: User Account Management, Security Group Management, Computer Account Management, Logon,
      Account Lockout, Special Logon, Kerberos Authentication Service, Directory Service Changes.
    - THIS SETS THE LOCAL POLICY of the machine it runs on. Production does it with a GPO under
      Computer Configuration, Policies, Windows Settings, Security Settings, Advanced Audit Policy Configuration, linked to
      the Domain Controllers OU, so every domain controller gets it and it cannot drift.
    - Send the logs to a SIEM such as Splunk. A log on a single machine can be cleared by an attacker.

    PITFALLS
    - Subcategory names depend on the Windows language. On a non-English server use the GUID forms.
    - If both a local setting and a GPO exist, the GPO wins at the next refresh.
    - Turning on too many subcategories fills the log. Size the Security log and forward it.

    EXPECTED OUTPUT
    Two auditpol tables where the subcategories listed above show "Success and Failure".
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$subcategories = @(                     # CHANGE: add or remove subcategories to match your audit standard.
    "User Account Management",
    "Security Group Management",
    "Computer Account Management",
    "Logon",
    "Account Lockout",
    "Special Logon",
    "Kerberos Authentication Service",
    "Directory Service Changes"
)
$showCategories = "Account Management", "Logon/Logoff"    # CHANGE: categories printed at the end.
# ============================================================================================

foreach ($subcategory in $subcategories) {
    auditpol /set /subcategory:"$subcategory" /success:enable /failure:enable | Out-Null
}

foreach ($category in $showCategories) {
    auditpol /get /category:"$category" | Out-String
}

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@16-audit-policy.ps1" --query "value[0].message" -o tsv
# ANOTHER ENVIRONMENT: prefer a GPO linked to the Domain Controllers OU (Advanced Audit Policy Configuration).
# To use this script on a single server, open PowerShell as Administrator, edit the CONFIGURATION block, then run:
#   .\16-audit-policy.ps1
