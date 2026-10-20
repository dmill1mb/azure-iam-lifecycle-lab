<#
.SYNOPSIS
    Creates a GPO that blocks the command prompt and a list of programs (PowerShell) for standard users, and links it only to the OUs that need it.

.DESCRIPTION
    Creates a user-settings GPO, turns on the command prompt block, turns on a "do not run these programs" list and fills the
    list, then links the GPO to the department OUs you name. IT staff are left out by simply not linking it to their OU. It reads
    the settings and the links back.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01, after 10-create-structure.ps1.

    RULES THIS SCRIPT FOLLOWS
    - These are USER settings, so the GPO is linked to the OUs where the USER accounts live, not to computers.
    - Staff who need the tools (IT) are excluded by leaving their OU out of the link list.
    - It looks before it creates, so running it again does not fail or duplicate anything.
    - It reads the settings and links back so you can see what was applied.

    KNOWLEDGE
    - User settings live under HKCU and follow the person to any computer. Computer settings (script 14) follow the machine.
    - THE LINE THAT DECIDES WHAT IT APPLIES TO is the New-GPLink call in the loop. The list $targetDepartments feeds it.
    - DisableCMD = 1 turns off the command prompt. Value 2 also blocks cmd.exe. The exact difference for scripts was not
      confirmed in this lab. Check the policy help text before relying on either value.
    - DisallowRun = 1 switches the "do not run these programs" list on. The list is a subkey called DisallowRun with
      numbered values (1, 2, 3 ...), each one an executable name.
    - THIS IS A WEAK CONTROL. It only blocks launching by file name from Explorer and the shell. A renamed copy of
      powershell.exe or a call from another program gets around it. Real prevention uses AppLocker or WDAC (Windows
      Defender Application Control), which decide by publisher, path or hash.
    - Security filtering or a link to the Domain root would change who is covered. Linking to OUs is the cleaner pattern.

    PITFALLS
    - Staff users must be in the department OU. A user left in the default Users container gets nothing.
    - Settings arrive at the next refresh or after gpupdate /force and a sign-out and sign-in.
    - Blocking PowerShell can break logon scripts or tools that call it. Test with a pilot group first.

    EXPECTED OUTPUT
    DisableCMD 1, DisallowRun 1, and the three program names; a link table for Finance, HR and Operations; IT shows no link.
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$gpoName           = "GPO-Standard-User-Restrictions"                # CHANGE: GPO name (your naming standard).
$domainDN          = (Get-ADDomain).DistinguishedName                # CHANGE: leave as is to use the current domain.
$staffOU           = "Staff"                                         # CHANGE: the OU that holds the department OUs.
$targetDepartments = "Finance", "HR", "Operations"                   # CHANGE: OUs the restriction applies to.
$excludedDepartments = "IT"                                          # CHANGE: OUs shown in the check but NOT linked.
$disableCmd        = 1                                               # CHANGE: 1 = block the command prompt, 0 = allow.
$blockedPrograms   = "powershell.exe", "powershell_ise.exe", "pwsh.exe"   # CHANGE: programs users may not start.
# ============================================================================================

Import-Module ActiveDirectory
Import-Module GroupPolicy

if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoName | Out-Null
}

$explorerKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"

Set-GPRegistryValue -Name $gpoName -Key "HKCU\Software\Policies\Microsoft\Windows\System" -ValueName "DisableCMD" -Type DWord -Value $disableCmd | Out-Null
Set-GPRegistryValue -Name $gpoName -Key $explorerKey -ValueName "DisallowRun" -Type DWord -Value 1 | Out-Null

$number = 1
foreach ($program in $blockedPrograms) {
    Set-GPRegistryValue -Name $gpoName -Key "$explorerKey\DisallowRun" -ValueName "$number" -Type String -Value $program | Out-Null
    $number++
}

foreach ($dept in $targetDepartments) {
    $ouDN = "OU=$dept,OU=$staffOU,$domainDN"
    # THIS LINE decides what the GPO applies to: one link per OU in $targetDepartments.
    if (-not ((Get-GPInheritance -Target $ouDN).GpoLinks | Where-Object { $_.DisplayName -eq $gpoName })) {
        New-GPLink -Name $gpoName -Target $ouDN -LinkEnabled Yes | Out-Null
    }
}

"=== Settings read back ==="
"DisableCMD:  " + (Get-GPRegistryValue -Name $gpoName -Key "HKCU\Software\Policies\Microsoft\Windows\System" -ValueName "DisableCMD").Value
"DisallowRun: " + (Get-GPRegistryValue -Name $gpoName -Key $explorerKey -ValueName "DisallowRun").Value
"Blocked programs:"
for ($i = 1; $i -le $blockedPrograms.Count; $i++) {
    "  $i = " + (Get-GPRegistryValue -Name $gpoName -Key "$explorerKey\DisallowRun" -ValueName "$i").Value
}
""
"=== Where this GPO applies ==="
$rows = foreach ($dept in ($targetDepartments + $excludedDepartments)) {
    $ouDN = "OU=$dept,OU=$staffOU,$domainDN"
    $link = (Get-GPInheritance -Target $ouDN).GpoLinks | Where-Object { $_.DisplayName -eq $gpoName }
    [pscustomobject]@{ OU = $dept; Linked = [bool]$link; Enabled = $(if ($link) { $link.Enabled } else { "" }) }
}
$rows | Format-Table -AutoSize | Out-String

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@15-user-restrictions-gpo.ps1" --query "value[0].message" -o tsv
# ANOTHER ENVIRONMENT: on a domain controller, open PowerShell as a Domain Admin, edit the CONFIGURATION block
# (department OUs and the program list), then run:
#   .\15-user-restrictions-gpo.ps1
# THEN AS A STANDARD USER ON A COMPUTER: gpupdate /force, sign out and in, and try to open cmd.exe and powershell.exe.
