<#
.SYNOPSIS
    Creates a Workstations OU and a computer-security GPO (Group Policy Object): USB block, screen lock after 15 minutes, no auto restart while someone is logged on.

.DESCRIPTION
    Installs the Group Policy management tools, creates the OU for workstations, creates a GPO, writes three
    computer settings into it, and links it to that OU. It then reads the settings and the link back.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01.

    RULES THIS SCRIPT FOLLOWS
    - A baseline GPO is linked to an OU of workstations, not to the whole domain, so servers and domain controllers are not hit.
    - Every setting is a named value in the configuration block, so a change is made in one place.
    - It looks before it creates, so running it again does not fail or duplicate anything.
    - It reads the settings and the link back so you can see what was applied.

    KNOWLEDGE
    - Scope = where a GPO is linked (site, domain or OU) plus inheritance. Security filtering can narrow it further.
      THE LINE THAT DECIDES WHAT IT APPLIES TO is the New-GPLink line near the bottom, and the -Target value on it.
    - Order of application is LSDOU: Local, Site, Domain, OU. The last one applied wins on a conflict.
    - Computer settings live under HKLM and apply to the machine at startup, whoever signs in. User settings live under HKCU.
      These three are computer settings, so they follow the computer.
    - The three settings:
        Removable storage: Deny_All = 1 blocks all removable storage classes (USB sticks, external drives).
        InactivityTimeoutSecs = 900 locks the screen after 900 seconds (15 minutes).
        NoAutoRebootWithLoggedOnUsers = 1 stops Windows Update restarting the machine while someone is signed in.
    - Linking to the domain root would also reach DC01 and block USB on the domain controller. In this lab we chose the OU.
    - Production: edit these in Group Policy Management, test in a pilot OU first, and use GPO backups.

    PITFALLS
    - A computer only gets the GPO when its account sits in the linked OU. A new computer lands in the default Computers
      container, so move it into the Workstations OU (or redirect new computers with redircmp).
    - Settings arrive at the next policy refresh (about 90 minutes) or when you run gpupdate /force on the computer.
    - Deny_All can lock you out of a backup drive. Warn users before rolling it out.

    EXPECTED OUTPUT
    The three values read back (1, 900, 1) and a link table showing the GPO linked to the Workstations OU, enabled.
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$ouName       = "Workstations"                                # CHANGE: OU that holds the computers this GPO applies to.
$ouParentDN   = (Get-ADDomain).DistinguishedName              # CHANGE: leave as is for the domain root, or give another parent DN.
$gpoName      = "GPO-Workstation-Security-Baseline"           # CHANGE: GPO name (your naming standard).
$blockUsb     = 1                                             # CHANGE: 1 = block all removable storage, 0 = allow.
$lockSeconds  = 900                                           # CHANGE: seconds of inactivity before the screen locks.
$noAutoReboot = 1                                             # CHANGE: 1 = no auto restart while a user is signed in.
$protectOU    = $true                                         # CHANGE: protect the OU from accidental deletion.
# ============================================================================================

Import-Module ActiveDirectory
Install-WindowsFeature GPMC | Out-Null
Import-Module GroupPolicy

$ouDN = "OU=$ouName,$ouParentDN"

if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouDN'")) {
    New-ADOrganizationalUnit -Name $ouName -Path $ouParentDN -ProtectedFromAccidentalDeletion $protectOU
}

if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoName | Out-Null
}

Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices" -ValueName "Deny_All" -Type DWord -Value $blockUsb | Out-Null
Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "InactivityTimeoutSecs" -Type DWord -Value $lockSeconds | Out-Null
Set-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "NoAutoRebootWithLoggedOnUsers" -Type DWord -Value $noAutoReboot | Out-Null

# THIS LINE decides what the GPO applies to. Change -Target to link it somewhere else.
if (-not ((Get-GPInheritance -Target $ouDN).GpoLinks | Where-Object { $_.DisplayName -eq $gpoName })) {
    New-GPLink -Name $gpoName -Target $ouDN -LinkEnabled Yes | Out-Null
}

"=== Settings read back ==="
"USB block (Deny_All):  " + (Get-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices" -ValueName "Deny_All").Value
"Lock after (seconds):  " + (Get-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "InactivityTimeoutSecs").Value
"No auto reboot:        " + (Get-GPRegistryValue -Name $gpoName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "NoAutoRebootWithLoggedOnUsers").Value
""
"=== Links on $ouDN ==="
(Get-GPInheritance -Target $ouDN).GpoLinks | Select-Object DisplayName, Enabled, Enforced, Target | Format-Table -AutoSize | Out-String -Width 200

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@14-workstation-gpo.ps1" --query "value[0].message" -o tsv
# ANOTHER ENVIRONMENT: on a domain controller, open PowerShell as a Domain Admin, edit the CONFIGURATION block
# (OU name, GPO name and the three values), then run:
#   .\14-workstation-gpo.ps1
# THEN ON A WORKSTATION IN THAT OU, TO CHECK:
#   gpupdate /force
#   gpresult /r /scope computer
