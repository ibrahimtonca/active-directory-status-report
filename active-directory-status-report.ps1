<#
Script Adı  : Active Directory Detaylı Durum Raporu
Hazırlayan  : İbrahim TONCA
Web         : www.ibrahimtonca.com
Açıklama    : Active Directory ve Domain Controller sağlık durumunu HTML rapor olarak oluşturur.

Yasal Uyarı :
Bu script kaynak gösterilmeden paylaşılamaz, çoğaltılamaz veya farklı platformlarda yayınlanamaz.
Scriptin kullanımı ve doğabilecek sonuçlar tamamen kullanıcının sorumluluğundadır.
#>

Import-Module ActiveDirectory
Add-Type -AssemblyName System.Web

# ============================================================
# KULLANICI TARAFINDAN DUZENLENECEK ALANLAR
# ============================================================

# SMTP ayarlari
# Mevcut SMTP sunucunuzu veya kuracaginiz SMTP relay server adresini yazin.
$SmtpServer = "SMTP_SERVER_IP_OR_HOSTNAME"
$SmtpPort   = 25
$From       = "rapor@firma.com"

# Test modu
# Ilk denemede $true kullanin. Rapor sadece $TestRecipient adresine gider.
# Canli/toplu gonderim icin $false yapin.
$TestMode      = $true
$TestRecipient = "test.kullanici@firma.com"

# Toplu rapor alicilari
# $TestMode = $false oldugunda rapor bu listedeki adreslere gonderilir.
$BulkRecipients = @(
    "sistem.yoneticisi@firma.com",
    "altyapi.ekibi@firma.com"
)

# Raporun kaydedilecegi klasor
$ReportDir = "C:\Temp"

# DCDiag ayarlari
# $RunDcDiag = $true oldugunda kapsamli dcdiag /v kontrolu calisir.
# Buyuk ortamlarda test uzun surerse timeout degerini artirabilirsiniz.
$RunDcDiag = $true
$DcDiagTimeoutSeconds = 600

# ============================================================
# BU SATIRDAN SONRASINI DEGISTIRMENIZE GEREK YOKTUR
# ============================================================

if ($TestMode) {
    $To = @($TestRecipient)
    $SubjectPrefix = "[TEST] "
} else {
    $To = $BulkRecipients
    $SubjectPrefix = ""
}

New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

function HtmlEncode {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return [System.Web.HttpUtility]::HtmlEncode($Text)
}

function SafeCount {
    param($Value)
    if ($null -eq $Value) { return 0 }
    try {
        $Number = [int]$Value
        if ($Number -lt 0) { return 0 }
        return $Number
    } catch {
        return 0
    }
}


function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory=$true)][string]$FileName,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 30
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = ($Arguments -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    try {
        [void]$p.Start()
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch {}
            return [PSCustomObject]@{
                ExitCode = -999
                Output   = @()
                Error    = "Zaman aşımı ($TimeoutSeconds sn)"
                TimedOut = $true
            }
        }

        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()

        return [PSCustomObject]@{
            ExitCode = $p.ExitCode
            Output   = @($stdout -split "`r?`n" | Where-Object { $_ -ne "" })
            Error    = $stderr
            TimedOut = $false
        }
    } catch {
        return [PSCustomObject]@{
            ExitCode = -1
            Output   = @()
            Error    = $_.Exception.Message
            TimedOut = $false
        }
    } finally {
        if ($p) { $p.Dispose() }
    }
}



function Get-DcDiagImportantLines {
    param([string[]]$Lines)

    $Important = New-Object System.Collections.Generic.List[string]
    $Patterns = @(
        'failed test',
        'failed on the test',
        'error',
        'warning',
        'fatal',
        'fail(ed|ure)?',
        'ldap bind failed',
        'cannot',
        'unable',
        'not advertising',
        'The host .* could not be resolved',
        'DsBind',
        'RPC',
        'Access is denied',
        'is not running',
        'replication.*fail',
        'KDC',
        'NetLogon',
        'Advertising',
        'Services',
        'Replications'
    )

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $Line = [string]$Lines[$i]
        foreach ($Pattern in $Patterns) {
            if ($Line -match $Pattern) {
                $From = [Math]::Max(0, $i - 2)
                $To   = [Math]::Min($Lines.Count - 1, $i + 4)
                for ($j = $From; $j -le $To; $j++) {
                    $Candidate = ([string]$Lines[$j]).TrimEnd()
                    if (-not [string]::IsNullOrWhiteSpace($Candidate) -and -not $Important.Contains($Candidate)) {
                        [void]$Important.Add($Candidate)
                    }
                }
                break
            }
        }
    }

    return @($Important)
}

function Invoke-DcDiagFull {
    param(
        [Parameter(Mandatory=$true)][string]$Server,
        [int]$TimeoutSeconds = 600
    )

    $AllOutput = @()

    try {
        # Doğru/kapsamlı kontrol için hızlı /test filtreleri kaldırıldı.
        # /v ayrıntılı çıktı verir. Çıktı büyük olabileceği için geçici dosyaya yazdırılır;
        # böylece StandardOutput pipe dolup scripti bekletmez.
        $SafeServer = ($Server -replace '[^a-zA-Z0-9_.-]', '_')
        $OutFile = Join-Path $env:TEMP ("dcdiag_{0}_{1}.out.txt" -f $SafeServer, ([Guid]::NewGuid().ToString('N')))
        $ErrFile = Join-Path $env:TEMP ("dcdiag_{0}_{1}.err.txt" -f $SafeServer, ([Guid]::NewGuid().ToString('N')))

        $ArgLine = "dcdiag.exe /s:$Server /v > `"$OutFile`" 2> `"$ErrFile`""
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c $ArgLine"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()

        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch {}
            return [PSCustomObject]@{
                Status = "KONTROL EDİLEMEDİ"
                Text   = HtmlEncode("DCDiag $TimeoutSeconds saniye içinde bitmedi. Bu, DC tarafında DNS/RPC/LDAP/replikasyon beklemesi olabileceğini gösterir. Timeout artırılabilir fakat mail raporu bu sürede bekler.")
            }
        }

        $ExitCode = $p.ExitCode
        $p.Dispose()

        $Lines = @()
        if (Test-Path $OutFile) { $Lines += Get-Content -Path $OutFile -Encoding UTF8 -ErrorAction SilentlyContinue }
        if (Test-Path $ErrFile) { $Lines += Get-Content -Path $ErrFile -Encoding UTF8 -ErrorAction SilentlyContinue }

        $ImportantLines = @(Get-DcDiagImportantLines -Lines $Lines)

        $FailureRegex = 'failed test|failed on the test|fatal|error|cannot|unable|not advertising|Access is denied|is not running|replication.*fail|DsBind|LDAP|RPC|KDC|NetLogon'
        $HasFailure = ($ExitCode -ne 0) -or (($ImportantLines | Where-Object { $_ -match $FailureRegex }).Count -gt 0)

        if ($HasFailure) {
            $AllOutput += "DCDiag kapsamlı kontrol hata/uyarı detayları:"
            if ($ImportantLines.Count -gt 0) {
                $AllOutput += $ImportantLines
            } elseif ($Lines.Count -gt 0) {
                $AllOutput += ($Lines | Select-Object -First 200)
            } else {
                $AllOutput += "DCDiag hata kodu döndürdü fakat okunabilir çıktı üretmedi. ExitCode: $ExitCode"
            }
            $Status = "HATALI"
        } else {
            $AllOutput += "Hata bulunmadı. DCDiag kapsamlı kontrol tamamlandı."
            $Status = "SAĞLIKLI"
        }

        try { if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue } } catch {}
        try { if (Test-Path $ErrFile) { Remove-Item $ErrFile -Force -ErrorAction SilentlyContinue } } catch {}

        return [PSCustomObject]@{
            Status = $Status
            Text = ((HtmlEncode ($AllOutput -join "`r`n")) -replace "`r?`n", "<br>")
        }
    } catch {
        return [PSCustomObject]@{
            Status = "KONTROL EDİLEMEDİ"
            Text = HtmlEncode("DCDiag kapsamlı kontrol çalıştırılamadı: $($_.Exception.Message)")
        }
    }
}

function Get-StatusClass {
    param([string]$Status)

    switch -Regex ($Status) {
        "SAĞLIKLI|Running|True|^0$" { return "status-ok" }
        "HATALI|Stopped|False" { return "status-bad" }
        "UYARI" { return "status-warn" }
        "KONTROL EDİLEMEDİ|Erişilemedi|ATLANDI" { return "status-unknown" }
        default { return "status-unknown" }
    }
}

function Get-IPv4FromDns {
    param([string]$Name)

    try {
        return @(Resolve-DnsName -Name $Name -Type A -QuickTimeout -ErrorAction Stop |
            Where-Object { $_.IPAddress -and $_.IPAddress -match '^\d{1,3}(\.\d{1,3}){3}$' } |
            Select-Object -ExpandProperty IPAddress -Unique)
    } catch {
        return @()
    }
}

function Select-PreferredIPv4 {
    param([string[]]$Ips)

    $ValidIps = @($Ips | Where-Object { $_ -and $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -Unique)
    if ($ValidIps.Count -eq 0) { return "Çözümlenemedi" }

    $Preferred = @($ValidIps | Where-Object { $_ -match '^10\.1\.' })
    if ($Preferred.Count -gt 0) { return ($Preferred -join ", ") }

    return ($ValidIps -join ", ")
}

function Get-ResolvedIP {
    param([string]$Name)

    $Ips = Get-IPv4FromDns -Name $Name
    return (Select-PreferredIPv4 -Ips $Ips)
}

function Get-DomainControllerIP {
    param($DC)

    $Candidates = @()

    if ($DC.IPv4Address -and $DC.IPv4Address -match '^\d{1,3}(\.\d{1,3}){3}$') {
        $Candidates += [string]$DC.IPv4Address
    }

    if ($DC.HostName) {
        $Candidates += @(Get-IPv4FromDns -Name $DC.HostName)
    }

    if ($DC.Name -and $DC.Name -ne $DC.HostName) {
        $Candidates += @(Get-IPv4FromDns -Name $DC.Name)
    }

    return (Select-PreferredIPv4 -Ips $Candidates)
}

$Domain = Get-ADDomain
$Forest = Get-ADForest
$DCs = Get-ADDomainController -Filter *

$PreparedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$ReportTitle = "Active Directory Durum Raporu ($($Domain.DNSRoot))"
$Subject = $SubjectPrefix + $ReportTitle

$SafeDomainName = $Domain.DNSRoot -replace '[\\/:*?"<>|]', '_'
$ReportPath = "$ReportDir\Active Directory Durum Raporu ($SafeDomainName).html"

$Trusts = Get-ADTrust -Filter * -Properties * -ErrorAction SilentlyContinue

if ($Trusts) {
    $TrustRows = foreach ($T in $Trusts) {
        $DirectionDetail = switch ($T.Direction) {
            "Bidirectional" { "Two-way / Çift Yönlü" }
            "Inbound"       { "One-way / Tek Yönlü - Gelen" }
            "Outbound"      { "One-way / Tek Yönlü - Giden" }
            default         { $T.Direction }
        }

        $AuthenticationType = if ($T.SelectiveAuthentication -eq $true) {
            "Selective Authentication"
        } else {
            "Forest-wide Authentication"
        }

        $TransitiveText = if ($T.ForestTransitive -eq $true) {
            "Transitive"
        } else {
            "Non-Transitive"
        }

        $TrustIP = Get-ResolvedIP $T.Name

@"
<tr>
<td>$(HtmlEncode $T.Name)</td>
<td>$(HtmlEncode $TrustIP)</td>
<td>$(HtmlEncode $DirectionDetail)</td>
<td>$(HtmlEncode $T.TrustType)</td>
<td>$(HtmlEncode $AuthenticationType)</td>
<td>$(HtmlEncode $TransitiveText)</td>
<td>$(HtmlEncode $T.SIDFilteringForestAware)</td>
</tr>
"@
    }
} else {
    $TrustRows = @"
<tr>
<td colspan="7">Trust yapısı bulunamadı.</td>
</tr>
"@
}

$PrivilegedGroups = @(
    "Domain Admins",
    "Enterprise Admins",
    "Schema Admins",
    "Administrators",
    "Account Operators",
    "Server Operators",
    "Backup Operators",
    "DnsAdmins",
    "Group Policy Creator Owners"
)

$GroupClassMap = @{
    "Domain Admins" = "grp1"
    "Enterprise Admins" = "grp2"
    "Schema Admins" = "grp3"
    "Administrators" = "grp4"
    "Account Operators" = "grp5"
    "Server Operators" = "grp6"
    "Backup Operators" = "grp7"
    "DnsAdmins" = "grp8"
    "Group Policy Creator Owners" = "grp9"
}

$PrivilegedResults = foreach ($GroupName in $PrivilegedGroups) {
    Write-Host ("[{0}] Grup kontrol: {1}" -f (Get-Date -Format "HH:mm:ss"), $GroupName)
    try {
        $Group = Get-ADGroup -Identity $GroupName -ErrorAction Stop
        $Members = Get-ADGroupMember -Identity $Group.DistinguishedName -Recursive -ErrorAction Stop

        foreach ($Member in $Members) {
            $Obj = Get-ADObject `
                -Identity $Member.DistinguishedName `
                -Properties objectClass, samAccountName, enabled, lastLogonTimestamp `
                -ErrorAction SilentlyContinue

            [PSCustomObject]@{
                GroupName   = $GroupName
                Name        = $Member.Name
                SamAccount  = $Obj.samAccountName
                ObjectClass = $Obj.objectClass
                Enabled     = $Obj.enabled
                LastLogon   = if ($Obj.lastLogonTimestamp) {
                    [DateTime]::FromFileTime($Obj.lastLogonTimestamp).ToString("dd.MM.yyyy HH:mm")
                } else {
                    "Yok"
                }
                RowClass    = $GroupClassMap[$GroupName]
            }
        }
    } catch {
        [PSCustomObject]@{
            GroupName   = $GroupName
            Name        = "Grup okunamadı veya bulunamadı"
            SamAccount  = "-"
            ObjectClass = "-"
            Enabled     = "-"
            LastLogon   = "-"
            RowClass    = $GroupClassMap[$GroupName]
        }
    }
}

$DCResults = foreach ($DC in $DCs) {
    $Server = $DC.HostName
    $DetectedIP = Get-DomainControllerIP -DC $DC
    Write-Host ("[{0}] DC kontrol: {1}" -f (Get-Date -Format "HH:mm:ss"), $Server)
    try {
        $Ping = Test-Connection $Server -Count 1 -Quiet -ErrorAction SilentlyContinue
    } catch {
        $Ping = $false
    }

    $Services = @("NTDS","DNS","Netlogon","Kdc","W32Time","DFSR","IsmServ")

    if ($Ping -eq $true) {
        $ServiceDetails = foreach ($Svc in $Services) {
            try {
                $S = Get-Service -ComputerName $Server -Name $Svc -ErrorAction Stop
                [PSCustomObject]@{
                    Name   = $Svc
                    Status = $S.Status.ToString()
                }
            } catch {
                [PSCustomObject]@{
                    Name   = $Svc
                    Status = "Erişilemedi"
                }
            }
        }
    } else {
        $ServiceDetails = foreach ($Svc in $Services) {
            [PSCustomObject]@{
                Name   = $Svc
                Status = "Erişilemedi"
            }
        }
    }

    $BadServices = $ServiceDetails | Where-Object { $_.Status -ne "Running" }

    $KerberosStatus = if (($ServiceDetails | Where-Object { $_.Name -eq "Kdc" }).Status -eq "Running") {
        "SAĞLIKLI"
    } else {
        "HATALI"
    }

    try {
        $ReplicationResult = Invoke-NativeCommand -FileName "repadmin.exe" -Arguments @("/showrepl", $Server, "/csv") -TimeoutSeconds 20

        if ($ReplicationResult.TimedOut -or $ReplicationResult.ExitCode -eq -999) {
            $ReplicationStatus = "KONTROL EDİLEMEDİ"
            $ReplicationErrorCount = 0
        } else {
            $ReplicationRaw = $ReplicationResult.Output | ConvertFrom-Csv
            $ReplicationErrors = $ReplicationRaw | Where-Object {
                $_.'Number of Failures' -and [int]$_.'Number of Failures' -gt 0
            }

            $ReplicationStatus = if ($ReplicationErrors) { "HATALI" } else { "SAĞLIKLI" }
            $ReplicationErrorCount = SafeCount ($ReplicationErrors.Count)
        }
    } catch {
        $ReplicationStatus = "KONTROL EDİLEMEDİ"
        $ReplicationErrorCount = 0
    }

    if ($RunDcDiag) {
        try {
            $DcDiagFullResult = Invoke-DcDiagFull -Server $Server -TimeoutSeconds $DcDiagTimeoutSeconds
            $DcDiagStatus = $DcDiagFullResult.Status
            $DcDiagText = $DcDiagFullResult.Text
        } catch {
            $DcDiagStatus = "KONTROL EDİLEMEDİ"
            $DcDiagText = "DCDiag kapsamlı kontrol çalıştırılamadı: $($_.Exception.Message)"
        }
    } else {
        $DcDiagStatus = "ATLANDI"
        $DcDiagText = "DCDiag kontrolü kapalı. Ana sağlık sonucu servis, ping, replikasyon, Kerberos/KDC ve zaman senkronizasyonu kontrollerine göre hesaplanır."
    }

    try {
        $TimeResult = Invoke-NativeCommand -FileName "w32tm.exe" -Arguments @("/query", "/computer:$Server", "/status") -TimeoutSeconds 10
        $TimeHealth = if ($TimeResult.ExitCode -eq 0) { "SAĞLIKLI" } else { "HATALI" }
    } catch {
        $TimeHealth = "KONTROL EDİLEMEDİ"
    }

    $IsHealthy = (
        $Ping -eq $true -and
        $BadServices.Count -eq 0 -and
        $KerberosStatus -eq "SAĞLIKLI" -and
        $ReplicationStatus -eq "SAĞLIKLI" -and
        ($DcDiagStatus -eq "SAĞLIKLI" -or $DcDiagStatus -eq "ATLANDI") -and
        $TimeHealth -eq "SAĞLIKLI"
    )

    $IsUnknown = (
        $ReplicationStatus -eq "KONTROL EDİLEMEDİ" -or
        $DcDiagStatus -eq "KONTROL EDİLEMEDİ" -or
        $TimeHealth -eq "KONTROL EDİLEMEDİ"
    )

    $IsFailed = (
        $Ping -ne $true -or
        $KerberosStatus -eq "HATALI" -or
        $ReplicationStatus -eq "HATALI" -or
        $DcDiagStatus -eq "HATALI"
    )

    if ($IsHealthy) {
        $OverallStatus = "SAĞLIKLI"
    } elseif ($IsFailed) {
        $OverallStatus = "HATALI"
    } elseif ($IsUnknown) {
        $OverallStatus = "KONTROL EDİLEMEDİ"
    } else {
        $OverallStatus = "UYARI"
    }

    [PSCustomObject]@{
        DomainController      = $Server
        Site                  = $DC.Site
        IP                    = $DetectedIP
        Online                = $Ping
        ServiceDetails        = $ServiceDetails
        BadServiceCount       = SafeCount ($BadServices.Count)
        ReplicationStatus     = $ReplicationStatus
        ReplicationErrorCount = $ReplicationErrorCount
        DcDiagStatus          = $DcDiagStatus
        DcDiagText            = $DcDiagText
        TimeHealth            = $TimeHealth
        KerberosStatus        = $KerberosStatus
        OverallStatus         = $OverallStatus
        IsHealthy             = $IsHealthy
        IsFailed              = $IsFailed
        IsUnknown             = $IsUnknown
    }
}

$TotalDC  = SafeCount ($DCResults.Count)
$OnlineDC  = SafeCount (($DCResults | Where-Object { $_.Online -eq $true }).Count)
$OfflineDC = SafeCount (($DCResults | Where-Object { $_.Online -ne $true }).Count)

$HealthyDC = SafeCount (($DCResults | Where-Object { $_.IsHealthy -eq $true }).Count)
$FailedDC  = SafeCount (($DCResults | Where-Object { $_.OverallStatus -eq "HATALI" }).Count)
$UnknownDC = SafeCount (($DCResults | Where-Object { $_.OverallStatus -eq "KONTROL EDİLEMEDİ" }).Count)

# Uyarı sayacı yalnızca OverallStatus = UYARI olanları değil,
# raporda problem olarak görünen DCDiag / replikasyon / servis / zaman / Kerberos hatalarını da sayar.
# Böylece DCDiag Genel Durum = HATALI iken özet kartında 0 görünmez.
$WarningDC = SafeCount (($DCResults | Where-Object {
    $_.OverallStatus -eq "UYARI" -or
    $_.DcDiagStatus -eq "HATALI" -or
    $_.DcDiagStatus -eq "KONTROL EDİLEMEDİ" -or
    $_.ReplicationStatus -eq "HATALI" -or
    $_.ReplicationStatus -eq "KONTROL EDİLEMEDİ" -or
    $_.KerberosStatus -eq "HATALI" -or
    $_.TimeHealth -eq "HATALI" -or
    $_.TimeHealth -eq "KONTROL EDİLEMEDİ" -or
    $_.BadServiceCount -gt 0
}).Count)

$DcDiagProblemDC = SafeCount (($DCResults | Where-Object {
    $_.DcDiagStatus -eq "HATALI" -or $_.DcDiagStatus -eq "KONTROL EDİLEMEDİ"
}).Count)

$PrivilegedCount = SafeCount ($PrivilegedResults.Count)
$DCNames = ($DCResults | Select-Object -ExpandProperty DomainController) -join ", "

$FsmoRows = @"
<tr><td>Domain</td><td>$(HtmlEncode $Domain.DNSRoot)</td></tr>
<tr><td>Forest</td><td>$(HtmlEncode $Forest.Name)</td></tr>
<tr><td>PDC Emulator</td><td>$(HtmlEncode $Domain.PDCEmulator)</td></tr>
<tr><td>RID Master</td><td>$(HtmlEncode $Domain.RIDMaster)</td></tr>
<tr><td>Infrastructure Master</td><td>$(HtmlEncode $Domain.InfrastructureMaster)</td></tr>
<tr><td>Schema Master</td><td>$(HtmlEncode $Forest.SchemaMaster)</td></tr>
<tr><td>Domain Naming Master</td><td>$(HtmlEncode $Forest.DomainNamingMaster)</td></tr>
"@

$SummaryRows = foreach ($R in $DCResults) {
@"
<tr>
<td>$(HtmlEncode $R.DomainController)</td>
<td>$(HtmlEncode $R.Site)</td>
<td>$(HtmlEncode $R.IP)</td>
<td><span class="$(Get-StatusClass $R.Online)">$($R.Online)</span></td>
<td><span class="$(Get-StatusClass $R.KerberosStatus)">$($R.KerberosStatus)</span></td>
<td><span class="$(Get-StatusClass $R.ReplicationStatus)">$($R.ReplicationStatus)</span></td>
<td><span class="$(Get-StatusClass $R.ReplicationErrorCount)">$($R.ReplicationErrorCount)</span></td>
<td><span class="$(Get-StatusClass $R.DcDiagStatus)">$($R.DcDiagStatus)</span></td>
<td><span class="$(Get-StatusClass $R.TimeHealth)">$($R.TimeHealth)</span></td>
<td><span class="$(Get-StatusClass $R.BadServiceCount)">$($R.BadServiceCount)</span></td>
<td><span class="$(Get-StatusClass $R.OverallStatus)">$($R.OverallStatus)</span></td>
</tr>
"@
}

$PrivilegedRows = foreach ($P in $PrivilegedResults) {
@"
<tr class="$($P.RowClass)">
<td>$(HtmlEncode $P.GroupName)</td>
<td>$(HtmlEncode $P.Name)</td>
<td>$(HtmlEncode $P.SamAccount)</td>
<td>$(HtmlEncode $P.ObjectClass)</td>
<td>$($P.Enabled)</td>
<td>$(HtmlEncode $P.LastLogon)</td>
</tr>
"@
}

$DCSections = foreach ($R in $DCResults) {
    $SafeDcName = $R.DomainController -replace '[\\/:*?"<>|.]', '_'

    $ServiceRows = foreach ($S in $R.ServiceDetails) {
        $SvcClass = if ($S.Status -eq "Running") { "status-ok" } else { "status-bad" }

@"
<tr>
<td>$(HtmlEncode $S.Name)</td>
<td><span class="$SvcClass">$($S.Status)</span></td>
</tr>
"@
    }

@"
<div class="section">
<div class="section-title">
<h2>DC Sağlık Detayı: $(HtmlEncode $R.DomainController)</h2>
<div class="export-buttons">
<span>Dışa Aktar:</span>
<button onclick="exportTableToPDF('tblHealth_$SafeDcName','DC_Saglik_Detayi_$SafeDcName')">PDF</button>
<button onclick="exportTableToCSV('tblHealth_$SafeDcName','DC_Saglik_Detayi_$SafeDcName')">CSV</button>
<button onclick="exportTableToXLSX('tblHealth_$SafeDcName','DC_Saglik_Detayi_$SafeDcName')">XLSX</button>
</div>
</div>

<table id="tblHealth_$SafeDcName" class="standard-table two-col">
<tr><th>Kontrol</th><th>Sonuç</th></tr>
<tr><td>Online Erişim</td><td><span class="$(Get-StatusClass $R.Online)">$($R.Online)</span></td></tr>
<tr><td>Kerberos / KDC</td><td><span class="$(Get-StatusClass $R.KerberosStatus)">$($R.KerberosStatus)</span></td></tr>
<tr><td>Replication Durumu</td><td><span class="$(Get-StatusClass $R.ReplicationStatus)">$($R.ReplicationStatus)</span></td></tr>
<tr><td>Replication Hata Sayısı</td><td><span class="$(Get-StatusClass $R.ReplicationErrorCount)">$($R.ReplicationErrorCount)</span></td></tr>
<tr><td>DCDiag Durumu</td><td><span class="$(Get-StatusClass $R.DcDiagStatus)">$($R.DcDiagStatus)</span></td></tr>
<tr><td>Zaman Senkronizasyonu</td><td><span class="$(Get-StatusClass $R.TimeHealth)">$($R.TimeHealth)</span></td></tr>
<tr><td>Problemli Servis Sayısı</td><td><span class="$(Get-StatusClass $R.BadServiceCount)">$($R.BadServiceCount)</span></td></tr>
<tr><td>Genel Durum</td><td><span class="$(Get-StatusClass $R.OverallStatus)">$($R.OverallStatus)</span></td></tr>
</table>

<div class="section-title sub-title">
<h3>Servis Sağlığı</h3>
<div class="export-buttons">
<span>Dışa Aktar:</span>
<button onclick="exportTableToPDF('tblService_$SafeDcName','DC_Servis_Sagligi_$SafeDcName')">PDF</button>
<button onclick="exportTableToCSV('tblService_$SafeDcName','DC_Servis_Sagligi_$SafeDcName')">CSV</button>
<button onclick="exportTableToXLSX('tblService_$SafeDcName','DC_Servis_Sagligi_$SafeDcName')">XLSX</button>
</div>
</div>

<table id="tblService_$SafeDcName" class="standard-table two-col">
<tr><th>Servis</th><th>Durum</th></tr>
$ServiceRows
</table>

<h3>DCDiag Hata Özeti</h3>
<div class="codebox">$($R.DcDiagText)</div>
</div>
"@
}

$Html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
body { font-family: Segoe UI, Arial, sans-serif; background: #f3f6fa; color: #1f2937; }
.container { width: 96%; margin: auto; }
.header { background: linear-gradient(135deg, #16345c, #0f766e); color: white; padding: 24px; border-radius: 12px; }
.header h1 { margin: 0 0 10px 0; }

.cards { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; margin-top: 18px; }
.card { height: 112px; background: white; padding: 16px; border-radius: 12px; box-shadow: 0 2px 10px rgba(15, 23, 42, .10); border-left: 6px solid #16345c; box-sizing: border-box; }
.card p { height: 36px; margin: 0 0 8px 0; color: #4b5563; font-size: 13px; font-weight: 600; }
.card h2 { margin: 0; font-size: 31px; color: #16345c; }
.card.total { border-left-color: #16345c; }
.card.ok { border-left-color: #15803d; }
.card.warn { border-left-color: #b45309; }
.card.bad { border-left-color: #b91c1c; }
.card.gray { border-left-color: #6b7280; }

.section { margin-top: 24px; background: white; padding: 18px; border-radius: 12px; box-shadow: 0 2px 10px rgba(15, 23, 42, .08); }
.section-title { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 10px; }
.section-title h2, .section-title h3 { margin: 0; }
.sub-title { margin-top: 22px; }

.export-buttons { display: flex; justify-content: flex-end; align-items: center; gap: 6px; white-space: nowrap; }
.export-buttons span { font-size: 12px; font-weight: 600; color: #374151; }
.export-buttons button { background: #16345c; color: white; border: none; padding: 7px 12px; border-radius: 6px; cursor: pointer; font-size: 12px; }
.export-buttons button:hover { background: #0f766e; }

.standard-table { width: 100%; border-collapse: collapse; table-layout: fixed; margin-top: 12px; }
.standard-table th, .standard-table td { padding: 9px; border-bottom: 1px solid #ddd; font-size: 13px; vertical-align: middle; text-align: left; word-wrap: break-word; overflow-wrap: break-word; }
.standard-table th { background: #16345c; color: white; font-weight: 600; }

.two-col th:first-child, .two-col td:first-child { width: 35%; }
.two-col th:last-child, .two-col td:last-child { width: 65%; }

.summary-table th:nth-child(1), .summary-table td:nth-child(1) { width: 15%; }
.summary-table th:nth-child(2), .summary-table td:nth-child(2) { width: 9%; }
.summary-table th:nth-child(3), .summary-table td:nth-child(3) { width: 9%; }
.summary-table th:nth-child(4), .summary-table td:nth-child(4) { width: 7%; }
.summary-table th:nth-child(5), .summary-table td:nth-child(5) { width: 10%; }
.summary-table th:nth-child(6), .summary-table td:nth-child(6) { width: 10%; }
.summary-table th:nth-child(7), .summary-table td:nth-child(7) { width: 9%; }
.summary-table th:nth-child(8), .summary-table td:nth-child(8) { width: 9%; }
.summary-table th:nth-child(9), .summary-table td:nth-child(9) { width: 8%; }
.summary-table th:nth-child(10), .summary-table td:nth-child(10) { width: 8%; }
.summary-table th:nth-child(11), .summary-table td:nth-child(11) { width: 10%; }

.priv-table th:nth-child(1), .priv-table td:nth-child(1) { width: 22%; }
.priv-table th:nth-child(2), .priv-table td:nth-child(2) { width: 22%; }
.priv-table th:nth-child(3), .priv-table td:nth-child(3) { width: 18%; }
.priv-table th:nth-child(4), .priv-table td:nth-child(4) { width: 13%; }
.priv-table th:nth-child(5), .priv-table td:nth-child(5) { width: 10%; }
.priv-table th:nth-child(6), .priv-table td:nth-child(6) { width: 15%; }

.trust-table th:nth-child(1), .trust-table td:nth-child(1) { width: 18%; }
.trust-table th:nth-child(2), .trust-table td:nth-child(2) { width: 13%; }
.trust-table th:nth-child(3), .trust-table td:nth-child(3) { width: 17%; }
.trust-table th:nth-child(4), .trust-table td:nth-child(4) { width: 13%; }
.trust-table th:nth-child(5), .trust-table td:nth-child(5) { width: 18%; }
.trust-table th:nth-child(6), .trust-table td:nth-child(6) { width: 11%; }
.trust-table th:nth-child(7), .trust-table td:nth-child(7) { width: 10%; }

.status-ok { color: #15803d; font-weight: 700; }
.status-bad { color: #b91c1c; font-weight: 700; }
.status-warn { color: #b45309; font-weight: 700; }
.status-unknown { color: #6b7280; font-weight: 700; }

.codebox { background: #f8fafc; border: 1px solid #d1d5db; padding: 12px; border-radius: 8px; font-family: Consolas, monospace; font-size: 12px; }
.grp1 { background: #e0f2fe; }
.grp2 { background: #dcfce7; }
.grp3 { background: #fef3c7; }
.grp4 { background: #ede9fe; }
.grp5 { background: #fee2e2; }
.grp6 { background: #fce7f3; }
.grp7 { background: #ecfccb; }
.grp8 { background: #ccfbf1; }
.grp9 { background: #f3e8ff; }

.footer { margin-top: 20px; padding: 10px; background: #e5e7eb; border-radius: 8px; font-size: 12px; text-align: center; color: #374151; }
</style>

<script>
function exportTableToCSV(tableId, filename) {
    var table = document.getElementById(tableId);
    var rows = table.querySelectorAll("tr");
    var csv = [];

    rows.forEach(function(row) {
        var cols = row.querySelectorAll("th, td");
        var rowData = [];
        cols.forEach(function(col) {
            var text = col.innerText.replace(/"/g, '""');
            rowData.push('"' + text + '"');
        });
        csv.push(rowData.join(","));
    });

    var blob = new Blob(["\ufeff" + csv.join("\n")], { type: "text/csv;charset=utf-8;" });
    downloadBlob(blob, filename + ".csv");
}

function exportTableToXLSX(tableId, filename) {
    var table = document.getElementById(tableId).outerHTML;
    var html = '<html><head><meta charset="UTF-8"></head><body>' + table + '</body></html>';
    var blob = new Blob(["\ufeff" + html], { type: "application/vnd.ms-excel;charset=utf-8;" });
    downloadBlob(blob, filename + ".xlsx");
}

function exportTableToPDF(tableId, filename) {
    var table = document.getElementById(tableId).outerHTML;
    var win = window.open("", "_blank");

    win.document.write(
        '<html><head><meta charset="UTF-8"><title>' + filename + '</title>' +
        '<style>body{font-family:Segoe UI,Arial,sans-serif;}h2{color:#16345c;}table{width:100%;border-collapse:collapse;table-layout:fixed;}th{background:#16345c;color:white;padding:8px;text-align:left;}td{padding:8px;border-bottom:1px solid #ddd;font-size:12px;word-wrap:break-word;}</style>' +
        '</head><body><h2>' + filename + '</h2>' + table + '</body></html>'
    );

    win.document.close();
    win.focus();
    win.print();
}

function downloadBlob(blob, filename) {
    var link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}
</script>
</head>
<body>
<div class="container">

<div class="header">
<h1>$ReportTitle</h1>
<p><b>Raporu Hazırlayan:</b> $(HtmlEncode $PreparedBy)</p>
<p><b>Rapor Tarihi:</b> $(Get-Date -Format "dd.MM.yyyy HH:mm")</p>
</div>

<div class="cards">
<div class="card total"><p>Toplam Domain Controller</p><h2>$TotalDC</h2></div>
<div class="card ok"><p>Erişilebilir Domain Controller</p><h2>$OnlineDC</h2></div>
<div class="card bad"><p>Erişilemeyen Domain Controller</p><h2>$OfflineDC</h2></div>
<div class="card ok"><p>Sağlıklı Domain Controller</p><h2>$HealthyDC</h2></div>
<div class="card warn"><p>Uyarı/Hata Bulunan Domain Controller</p><h2>$WarningDC</h2></div>
<div class="card bad"><p>Hatalı Domain Controller</p><h2>$FailedDC</h2></div>
<div class="card bad"><p>DCDiag Hatalı/Kontrol Edilemeyen DC</p><h2>$DcDiagProblemDC</h2></div>
<div class="card gray"><p>Kontrol Edilemeyen Domain Controller</p><h2>$UnknownDC</h2></div>
<div class="card warn"><p>Kritik Yetki Grubu Üyeliği</p><h2>$PrivilegedCount</h2></div>
</div>

<div class="section">
<div class="section-title">
<h2>Domain / Forest / FSMO Bilgileri</h2>
<div class="export-buttons">
<span>Dışa Aktar:</span>
<button onclick="exportTableToPDF('tblFsmo','Domain_Forest_FSMO_Bilgileri')">PDF</button>
<button onclick="exportTableToCSV('tblFsmo','Domain_Forest_FSMO_Bilgileri')">CSV</button>
<button onclick="exportTableToXLSX('tblFsmo','Domain_Forest_FSMO_Bilgileri')">XLSX</button>
</div>
</div>
<table id="tblFsmo" class="standard-table two-col">
<tr><th>Alan</th><th>Değer</th></tr>
$FsmoRows
</table>
</div>

<div class="section">
<div class="section-title">
<h2>Domain Controller Sağlık Özeti</h2>
<div class="export-buttons">
<span>Dışa Aktar:</span>
<button onclick="exportTableToPDF('tblDCSummary','Domain_Controller_Saglik_Ozeti')">PDF</button>
<button onclick="exportTableToCSV('tblDCSummary','Domain_Controller_Saglik_Ozeti')">CSV</button>
<button onclick="exportTableToXLSX('tblDCSummary','Domain_Controller_Saglik_Ozeti')">XLSX</button>
</div>
</div>
<table id="tblDCSummary" class="standard-table summary-table">
<tr>
<th>Domain Controller</th>
<th>Site</th>
<th>IP</th>
<th>Online</th>
<th>Kerberos / KDC</th>
<th>Replication</th>
<th>Replication Hata</th>
<th>DCDiag</th>
<th>Zaman</th>
<th>Problemli Servis</th>
<th>Genel Durum</th>
</tr>
$SummaryRows
</table>
</div>

<div class="section">
<div class="section-title">
<h2>Yönetici / Kritik Yetki Grupları</h2>
<div class="export-buttons">
<span>Dışa Aktar:</span>
<button onclick="exportTableToPDF('tblPrivileged','Yonetici_Kritik_Yetki_Gruplari')">PDF</button>
<button onclick="exportTableToCSV('tblPrivileged','Yonetici_Kritik_Yetki_Gruplari')">CSV</button>
<button onclick="exportTableToXLSX('tblPrivileged','Yonetici_Kritik_Yetki_Gruplari')">XLSX</button>
</div>
</div>
<table id="tblPrivileged" class="standard-table priv-table">
<tr>
<th>Grup</th>
<th>Üye</th>
<th>Kullanıcı Adı</th>
<th>Tip</th>
<th>Aktif</th>
<th>Son Logon</th>
</tr>
$PrivilegedRows
</table>
</div>

<div class="section">
<div class="section-title">
<h2>Trust Yapısı</h2>
<div class="export-buttons">
<span>Dışa Aktar:</span>
<button onclick="exportTableToPDF('tblTrust','Trust_Yapisi')">PDF</button>
<button onclick="exportTableToCSV('tblTrust','Trust_Yapisi')">CSV</button>
<button onclick="exportTableToXLSX('tblTrust','Trust_Yapisi')">XLSX</button>
</div>
</div>
<table id="tblTrust" class="standard-table trust-table">
<tr>
<th>Trust Ad</th>
<th>IP Adresi</th>
<th>Yön</th>
<th>Trust Tipi</th>
<th>Authentication</th>
<th>Transitive</th>
<th>SID Filtering</th>
</tr>
$TrustRows
</table>
</div>

$DCSections

<div class="footer">
$ReportTitle<br>
Domain Controller Bilgileri: $(HtmlEncode $DCNames)
</div>

</div>
</body>
</html>
"@

$Html | Out-File -FilePath $ReportPath -Encoding UTF8

$MailBody = @"
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Segoe UI, Arial, sans-serif; font-size:14px; color:#1f2937;">
<p>Merhaba,</p>
<p>$ReportTitle ektedir.</p>
<p>Rapor kapsamında aşağıdaki Domain Controller bilgileri kontrol edilmiştir:<br><b>$(HtmlEncode $DCNames)</b></p>
<p>İyi çalışmalar.</p>
</body>
</html>
"@

try {
    $Message = New-Object System.Net.Mail.MailMessage
    $Message.From = New-Object System.Net.Mail.MailAddress($From)

    # ÖNEMLİ DÜZELTME:
    # $To bir dizi olduğu için $Message.To.Add($To) tek seferde kullanılmamalı.
    # Her alıcı ayrı ayrı eklenmezse toplu mail gönderimi hata verebilir.
    foreach ($Recipient in $To) {
        if (-not [string]::IsNullOrWhiteSpace($Recipient)) {
            [void]$Message.To.Add($Recipient.Trim())
        }
    }

    if ($Message.To.Count -eq 0) {
        throw "Geçerli mail alıcısı bulunamadı. `$To listesini kontrol edin."
    }

    $Message.Subject = $Subject
    $Message.Body = $MailBody
    $Message.IsBodyHtml = $true
    $Message.BodyEncoding = [System.Text.Encoding]::UTF8
    $Message.SubjectEncoding = [System.Text.Encoding]::UTF8
    $Message.HeadersEncoding = [System.Text.Encoding]::UTF8

    if (-not (Test-Path -LiteralPath $ReportPath)) {
        throw "Ek dosya bulunamadı: $ReportPath"
    }

    $Attachment = New-Object System.Net.Mail.Attachment($ReportPath)
    $Attachment.NameEncoding = [System.Text.Encoding]::UTF8
    [void]$Message.Attachments.Add($Attachment)

    $Client = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
    $Client.Timeout = 30000
    $Client.EnableSsl = $false
    $Client.DeliveryMethod = [System.Net.Mail.SmtpDeliveryMethod]::Network

    $Client.Send($Message)
    Write-Host ("Rapor gönderildi. Alıcılar: " + (($To | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ", "))
} catch {
    Write-Warning ("Mail gönderilemedi: " + $_.Exception.Message)
    if ($_.Exception.InnerException) {
        Write-Warning ("Detay: " + $_.Exception.InnerException.Message)
    }
} finally {
    if ($Attachment) { $Attachment.Dispose() }
    if ($Message) { $Message.Dispose() }
    if ($Client) { $Client.Dispose() }
}

Write-Host "HTML ek dosya: $ReportPath"

# ------------------------------------------------------------
# Hazırlayan : İbrahim TONCA
# Web        : www.ibrahimtonca.com
# ------------------------------------------------------------
