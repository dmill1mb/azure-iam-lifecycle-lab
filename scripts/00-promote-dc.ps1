<#
.SYNOPSIS
    Promotes a Windows Server to the first domain controller of a brand-new Active Directory forest and installs DNS.

.DESCRIPTION
    Installs the AD DS (Active Directory Domain Services) role, loads the promotion commands, then
    creates a new forest and domain and installs DNS in the same operation. The server restarts
    itself when the promotion finishes.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01.

    RULES THIS SCRIPT FOLLOWS
    - The recovery password arrives as a parameter. It is never written in this file.
    - Run it once, on a fresh server that is not yet in any domain.
    - Verify the result after the restart. Do not trust the success message alone.

    KNOWLEDGE
    - Installing the AD DS role only adds the software. Promotion is what makes the server a domain controller.
    - A forest is the top-level security boundary. One forest can hold many domain controllers and many domains.
      Twelve domain controllers still only need one forest unless you need separate security boundaries.
    - The NetBIOS name is the short legacy name (the IAMLAB in IAMLAB\user). It is 15 characters at most.
    - The SafeModeAdministratorPassword is the DSRM (Directory Services Restore Mode) password, the only
      way into the DC for offline repair or an authoritative restore. Keep it in a vault.
    - Every later IAM script (10 to 18) assumes this domain exists and that it runs on this domain controller.

    PITFALLS
    - The copy of this script that sat in the lab project had the defaults IAM.local and IAM. The domain that was
      actually deployed was iamlab.local and IAMLAB, so those are the defaults here. Check the name you
      really deployed before relying on this.
    - Run-command may report a timeout because the VM restarts mid-run. Wait, then check.
    - Running it on a server that is already a domain controller fails.

    EXPECTED OUTPUT
    Status Success, then the server restarts. Afterward, (Get-ADDomain).DNSRoot returns your domain name.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SafeModePassword      # Secret. Supply it at run time. Never type it into this file.
)

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$DomainName        = "iamlab.local"   # CHANGE: the DNS name of the new domain. Production: a subdomain you own.
$DomainNetbiosName = "IAMLAB"         # CHANGE: short legacy name, 15 characters or fewer.
# ============================================================================================

$secureSafeModePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Import-Module ADDSDeployment

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $DomainNetbiosName `
    -SafeModeAdministratorPassword $secureSafeModePassword `
    -InstallDns `
    -Force

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   Load the password from Key Vault into $env:TF_VAR_admin_password first. Never paste it into a command.
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@00-promote-dc.ps1" --parameters "SafeModePassword=$env:TF_VAR_admin_password" --query "value[0].message" -o tsv
# ANOTHER ENVIRONMENT: sign in as a local Administrator on the new server, open PowerShell as Administrator,
# edit the CONFIGURATION block, then run:
#   $sec = Read-Host "Recovery (DSRM) password" -AsSecureString
#   .\00-promote-dc.ps1 -SafeModePassword ([System.Net.NetworkCredential]::new("", $sec).Password)
# TO VERIFY AFTER THE RESTART:
#   (Get-ADDomain).DNSRoot ; Get-Service DNS
