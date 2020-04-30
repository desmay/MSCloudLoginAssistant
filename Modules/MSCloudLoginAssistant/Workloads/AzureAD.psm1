function Connect-MSCloudLoginAzureAD
{
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.String]
        $ApplicationId,

        [Parameter()]
        [System.String]
        $TenantId,

        [Parameter()]
        [System.String]
        $CertificateThumbprint
    )

    if (-not [String]::IsNullOrEmpty($ApplicationId) -and `
        -not [String]::IsNullOrEmpty($TenantId) -and `
        -not [String]::IsNullOrEmpty($CertificateThumbprint))
    {
        Write-Verbose -Message "Connecting to AzureAD using Application {$ApplicationId}"
        try
        {
            Connect-AzureAD -ApplicationId $ApplicationId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint | Out-Null
        }
        catch
        {
            throw $_
        }
    }
    else
    {
        try
        {
            Connect-AzureAD -Credential $Global:o365Credential -ErrorAction Stop | Out-Null
            $Global:IsMFAAuth = $false
            $Global:MSCloudLoginAzureADConnected = $true
        }
        catch
        {
            if ($_.Exception -like '*unknown_user_type: Unknown User Type*')
            {
                try
                {
                    Connect-AzureAD -Credential $Global:o365Credential -AzureEnvironmentName AzureGermanyCloud -ErrorAction Stop | Out-Null
                    $Global:IsMFAAuth = $false
                    $Global:MSCloudLoginAzureADConnected = $true
                    $Global:CloudEnvironment = 'Germany'
                }
                catch
                {
                    if ($_.Exception -like '*AADSTS50076*')
                    {
                        Connect-MSCloudLoginAzureADMFA
                    }
                    elseif ($_.Exception -like '*unknown_user_type*')
                    {
                        $Global:CloudEnvironment = 'GCCHigh'
                        Connect-MSCloudLoginAzureADMFA
                    }
                    else
                    {
                        $Global:MSCloudLoginAzureADConnected = $false
                        throw $_
                    }
                }
            }
            elseif ($_.Exception -like '*AADSTS50076*')
            {
                Connect-MSCloudLoginAzureADMFA
            }
            else
            {
                $Global:MSCloudLoginAzureADConnected = $false
                throw $_
            }
        }
    }
    return
}

function Connect-MSCloudLoginAzureADMFA
{
    [CmdletBinding()]
    param()

    # We are using an MFA enabled account. Need to call Azure AD
    try
    {
        if ($null -ne $Global:o365Credential)
        {
            if ($Global:o365Credential.UserName.Split('@')[1] -like '*.de')
            {
                $EnvironmentName = 'AzureGermanyCloud'
                $Global:CloudEnvironment = 'Germany'
            }
            else
            {
                $EnvironmentName = 'AzureCloud'
            }
            Connect-AzureAD -AccountId $Global:o365Credential.UserName -AzureEnvironmentName $EnvironmentName -ErrorAction Stop | Out-Null
            $Global:IsMFAAuth = $true
            $Global:MSCloudLoginAzureADConnected = $true
        }
        else
        {
            Connect-AzureAD -ErrorAction Stop | Out-Null
            $Global:MSCloudLoginAzureADConnected = $true
        }
    }
    catch
    {
        try
        {
            Connect-AzureAD -AccountId $Global:o365Credential.UserName -AzureEnvironmentName AzureUSGovernment -ErrorAction Stop | Out-Null
            $Global:IsMFAAuth = $true
            $Global:MSCloudLoginAzureADConnected = $true

            if ($Global:CloudEnvironment -ne 'GCCHigh')
            {
                $Global:CloudEnvironment = 'USGovernment'
            }
        }
        catch
        {
            $Global:MSCloudLoginAzureADConnected = $false
            throw $_
        }
    }
    return
}

function Get-MSCloudLoginAADToken
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param (
        [Parameter()]
        [System.Management.Automation.PSCredential]
        $GlobalAdminAccount,

        [Parameter()]
        [System.String]
        $TenantID,

        [Parameter()]
        [System.String]
        $ApplicationId,

        [Parameter()]
        [System.String]
        $ApplicationSecret
    )
    try
    {
        $resourceAppIdURI = 'https://management.core.windows.net/'

        if (-not [System.String]::IsNullOrEMpty($ApplicationId) -and `
            -not [System.String]::IsNullOrEMpty($TenantID) -and `
            -not [System.String]::IsNullOrEMpty($ApplicationSecret))
        {
            $authority = 'https://login.windows.net/' + $TenantId
            $ClientCred = [Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential]::new($ApplicationId, $ApplicationSecret)
            $authContext = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::new($authority)
            $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI,$ClientCred)
            $Token = $authResult.Result.CreateAuthorizationHeader()
        }
        elseif ($null -ne $GlobalAdminAccount)
        {
            # Set well-known client ID for Azure PowerShell
            $clientId = '1950a258-227b-4e31-a9cf-717495945fc2'
            Test-MSCloudLogin -Platform AzureAD -CloudCredential $GlobalAdminAccount
            $tenantDetails = Get-AzureADTenantDetail
            $TenantID = $tenantDetails.ObjectId
            $authority = 'https://login.windows.net/' + $TenantId
            $ClientCred = [Microsoft.IdentityModel.Clients.ActiveDirectory.UserCredential]::new($GlobalAdminAccount.UserName, $GlobalAdminAccount.Password)
            $authContext = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::new($authority)
            $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI, $clientId, $ClientCred)
            $Token = $authResult.Result.CreateAuthorizationHeader()
        }

    }
    catch
    {
      throw $_
    }
    return $Token
}
