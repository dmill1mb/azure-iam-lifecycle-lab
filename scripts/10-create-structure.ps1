<#
.SYNOPSIS
    Builds the directory structure for a company: top-level OUs, one OU per department, and one security group per department.

.DESCRIPTION
    Creates the Staff, Groups and Disabled OUs, a child OU for each department under Staff, and a security
    group named SG-<department> for each department inside the Groups OU. Prints the OU table.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01.

    RULES THIS SCRIPT FOLLOWS
    - Structure first, people second. Users are created straight into the right OU by 11-onboard-users.ps1.
    - One group per department. Access is granted to groups, never to individuals.
    - It looks before it creates, so running it again does not fail and does not duplicate anything.
    - It finds the domain itself with Get-ADDomain, so no domain name is typed in.

    KNOWLEDGE
    - Staff holds the active people, Groups holds the security groups, and Disabled is where leavers are parked
      (see 18-leaver-offboarding.ps1). Disable first and delete later, after the retention period.
    - OU membership is not the same as group membership. The OU decides which Group Policy Objects and admin
      delegation apply. The group decides who gets access to resources.
    - SG means security group. Naming standards make audits and queries predictable.
    - ProtectedFromAccidentalDeletion stops an OU being deleted by mistake. The lab turns it off so the lab can be
      torn down easily. Production should turn it on.

    PITFALLS
    - If you move a user to a different OU, the Group Policy Objects change but their group membership does not.
    - Departments are a lab example. Use your real organization chart.

    EXPECTED OUTPUT
    A table of 7 OUs: Staff, Groups, Disabled, and Finance, HR, IT, Operations under Staff.
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$domainDN    = (Get-ADDomain).DistinguishedName      # CHANGE: leave as is to use the domain you are running in.
$topOUs      = "Staff", "Groups", "Disabled"         # CHANGE: top-level OUs (active people, groups, parked leavers).
$departments = "Finance", "HR", "IT", "Operations"   # CHANGE: your departments.
$staffOU     = "Staff"                               # CHANGE: the top OU that holds the department OUs.
$groupsOU    = "Groups"                              # CHANGE: the OU that holds the security groups.
$groupPrefix = "SG-"                                 # CHANGE: your group naming prefix.
$protectOUs  = $false                                # CHANGE: use $true in production.
# ============================================================================================

Import-Module ActiveDirectory

foreach ($ou in $topOUs) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -SearchBase $domainDN -SearchScope OneLevel)) {
        New-ADOrganizationalUnit -Name $ou -Path $domainDN -ProtectedFromAccidentalDeletion $protectOUs
    }
}

foreach ($dept in $departments) {
    $parent = "OU=$staffOU,$domainDN"
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$dept'" -SearchBase $parent -SearchScope OneLevel)) {
        New-ADOrganizationalUnit -Name $dept -Path $parent -ProtectedFromAccidentalDeletion $protectOUs
    }

    $groupName = "$groupPrefix$dept"
    if (-not (Get-ADGroup -Filter "Name -eq '$groupName'")) {
        New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security -Path "OU=$groupsOU,$domainDN"
    }
}

Get-ADOrganizationalUnit -Filter * -SearchBase $domainDN | Select-Object Name, DistinguishedName | Sort-Object DistinguishedName | Format-Table -AutoSize | Out-String -Width 200

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@10-create-structure.ps1" --query "value[0].message" -o tsv
# ANOTHER ENVIRONMENT: on a domain controller (or a server with RSAT), open PowerShell as a Domain Admin,
# edit the CONFIGURATION block (departments, OU names, prefix), then run:
#   .\10-create-structure.ps1
