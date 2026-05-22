Active Directory ortamlarında Domain Controller sunucularının durumunu düzenli olarak kontrol etmek için hazırladığım bu PowerShell scripti, sistem üzerindeki temel sağlık kontrollerini otomatik şekilde raporlamak için kullanılabilir.

Normalde bu kontrolleri tek tek yapmak zaman alabiliyor. Özellikle birden fazla Domain Controller bulunan yapılarda DCDiag çıktıları, servis durumları, DNS kontrolleri ve replikasyon sonuçlarını manuel takip etmek oldukça yorucu hale gelebiliyor. Bu script ile bu kontrolleri daha okunabilir bir rapor haline getirip e-posta üzerinden paylaşılabilir hale getirdim.

Script çalıştırıldığında Active Directory ortamındaki durum bilgilerini toplar, belirlenen kontrolleri yapar ve sonuçları HTML formatında tablo yapısıyla raporlar. Böylece hem günlük kontrollerde hem de sorun analizi sırasında daha hızlı inceleme yapılabilir.

Script çalıştırıldığında Active Directory ortamındaki temel kontrolleri otomatik olarak yapar ve sonuçları HTML formatında daha okunabilir bir rapor haline getirir. Ben bu raporda özellikle tek tek komut çıktısı incelemek yerine, önemli bilgilerin tablo yapısında görülmesini hedefledim.

Bu script ile genel olarak aşağıdaki raporları alabiliyoruz:

Genel durum özeti raporu
Domain Controller bilgileri raporu
DCDiag test sonuçları raporu
Active Directory replikasyon durumu raporu
DNS kontrol raporu
Kritik servis durumu raporu
Kritik hata ve uyarılar raporu
HTML mail raporu
Bu script Windows PowerShell 5.1 üzerinde hazırlanmıştır. Active Directory PowerShell modülü yüklü olan Windows Server ortamlarında kullanılabilir. PowerShell 7 üzerinde kullanılacaksa Active Directory modül uyumluluğu ayrıca test edilmelidir.

Script İndirme Bağlantısı
Active Directory detaylı durum raporu scriptini aşağıdaki bağlantıdan indirebilirsiniz:

İndirmek için tıklayın.

Genel Durum Özeti
Raporun ilk kısmında genel durum özeti bulunur. Bu bölüm, tüm rapora hızlı bir bakış atmak için kullanılabilir. Domain Controller sunucularının genel durumu, hata ve uyarı bilgileri bu alanda özetlenir. Özellikle günlük kontrollerde raporu açar açmaz genel durumun anlaşılması için bu tablo oldukça kullanışlıdır.



Domain / Forest / FSMO Bilgileri
Bu bölümde domain, forest ve FSMO rol bilgileri yer alır. Görselde görüldüğü gibi Domain ve Forest bilgileriyle birlikte PDC Emulator, RID Master, Infrastructure Master, Schema Master ve Domain Naming Master rollerinin hangi Domain Controller üzerinde olduğu listelenir.

FSMO rollerinin tek tabloda görünmesi, rol dağılımını hızlıca kontrol etmek için faydalıdır. Özellikle bakım, taşıma veya sorun analizi sırasında hangi rolün hangi sunucuda bulunduğu bu bölümden kolayca incelenebilir.



Domain Controller Sağlık Özeti
Bu bölümde ortamda bulunan Domain Controller sunucularının genel sağlık durumu özetlenir. Görselde görüldüğü gibi her Domain Controller için site bilgisi, IP adresi, online durumu, Kerberos / KDC durumu, replication durumu, replication hata sayısı, DCDiag sonucu, zaman senkronizasyonu, problemli servis sayısı ve genel durum bilgileri ayrı sütunlarda listelenmektedir.

Özellikle birden fazla Domain Controller bulunan yapılarda hangi sunucunun problemli olduğunu hızlıca görmek için bu tablo oldukça faydalıdır. Sağlıklı ve hatalı alanların renkli gösterilmesi sayesinde kritik durumlar daha kolay fark edilebilir.


Yönetici / Kritik Yetki Grupları
Bu bölümde Active Directory üzerindeki kritik yetki grupları ve bu gruplara üye olan kullanıcılar listelenmektedir. Görselde görüldüğü gibi Domain Admins, Enterprise Admins, Schema Admins, Administrators, Account Operators, Server Operators ve Group Policy Creator Owners gibi kritik gruplar ayrı satırlarda görüntülenir.

Tablo içerisinde grup adı, üye bilgisi, kullanıcı adı, hesap tipi, aktif durumu ve son logon bilgileri yer almaktadır. Özellikle yetki denetimi yapılırken hangi kullanıcının hangi yetkiye sahip olduğunu hızlı şekilde kontrol etmek için bu bölüm oldukça faydalıdır.

Ayrıca farklı yetki gruplarının renkli şekilde ayrılması sayesinde kritik kullanıcılar daha kolay analiz edilebilir.



Trust Yapısı
Bu bölümde Active Directory ortamındaki trust ilişkileri görüntülenmektedir. Görselde görüldüğü gibi trust adı, IP adresi, yön bilgisi, trust tipi, authentication durumu, transitive bilgisi ve SID filtering durumu tablo halinde listelenmektedir.

Özellikle birden fazla domain veya forest bağlantısı bulunan yapılarda trust ilişkilerini kontrol etmek için bu bölüm oldukça faydalıdır. Trust bağlantısının yönü, authentication tipi ve SID filtering durumu gibi bilgiler sayesinde yapılandırma daha kolay analiz edilebilir.



DC Sağlık Detayı
Her Domain Controller için ayrı sağlık detay tablosu oluşturulmaktadır. Görselde görüldüğü gibi ilgili DC’nin online erişim durumu, Kerberos / KDC kontrolü, replication durumu, replication hata sayısı, DCDiag sonucu, zaman senkronizasyonu, problemli servis sayısı ve genel durum bilgileri ayrı satırlarda gösterilmektedir.

Bu bölüm sayesinde genel sağlık özetinin dışında her Domain Controller özelinde daha detaylı kontrol yapılabilir. Özellikle DCDiag sonucu, replication durumu veya zaman senkronizasyonu gibi kritik kontrollerin tek ekranda görüntülenmesi sorun analizi sırasında oldukça faydalıdır.

Ayrıca sağlıklı ve hatalı durumların renkli şekilde gösterilmesi sayesinde problemli alanlar daha hızlı fark edilebilir.



Servis Sağlığı
DC sağlık detayının altında servis sağlığı bölümü yer almaktadır. Görselde görüldüğü gibi NTDS, DNS, Netlogon, Kdc, W32Time, DFSR ve IsmServ gibi Active Directory için kritik servislerin çalışma durumu tablo halinde gösterilmektedir.

Bu bölüm sayesinde servislerin çalışıp çalışmadığı hızlı şekilde kontrol edilebilir. Özellikle durmuş veya beklenmeyen durumda çalışan servisler doğrudan fark edilebilir ve olası Active Directory problemlerinin kaynağı daha hızlı analiz edilebilir.

Servis durumlarının tek ekranda görüntülenmesi günlük kontroller sırasında oldukça kolaylık sağlamaktadır.



DCDiag Hata Özeti
Raporun bu bölümünde DCDiag çıktısında tespit edilen hata ve uyarılar detaylı şekilde görüntülenmektedir. Görselde görüldüğü gibi DCDiag test süreci, yapılan kontroller ve oluşan hata kayıtları tek alanda listelenmektedir.

Özellikle SystemLog hataları, Kerberos problemleri, DCOM iletişim sorunları, trust account hataları, access denied kayıtları ve benzeri kritik loglar bu bölüm üzerinden takip edilebilir. Uzun DCDiag çıktıları içerisinde önemli kayıtların tek ekranda görüntülenmesi sorun analizi sırasında oldukça faydalı olmaktadır.

Ben bu bölümü özellikle hata tespiti ve hızlı analiz için kullanışlı buluyorum. Çünkü doğrudan aksiyon alınması gereken kayıtlar burada daha net şekilde görülebiliyor.



HTML Mail Raporu Görünümü
Script çalışmasını tamamladıktan sonra oluşturulan HTML rapor e-posta ekinde gönderilir. Mail içeriğinde kısa bir bilgilendirme metni, raporun hangi domain için oluşturulduğu ve kontrol edilen Domain Controller bilgileri yer alır.

Bu yapıda rapor doğrudan mail eki olarak gönderildiği için kullanıcı mail üzerinden gelen dosyayı açarak detaylı Active Directory durum raporunu inceleyebilir. Mail gövdesi sade tutulmuştur; asıl detaylar ekli HTML rapor dosyasında yer alır.



Script Nasıl Kullanılır?
Scripti kullanmadan önce PowerShell’in yönetici olarak çalıştırılması gerekir. Ayrıca scriptin çalışacağı sistemde Active Directory PowerShell modülünün yüklü olması gerekir.

Script içerisinde Active Directory modülü şu şekilde çağrılır:

Import-Module ActiveDirectory

Scripti çalıştırmak için dosyanın bulunduğu dizine gidip aşağıdaki komut kullanılabilir:

.\active-directory-status-report.ps1

Çalıştırma sonrasında script kontrolleri yapar, HTML raporu oluşturur ve tanımlanan mail adreslerine gönderir.

Script İçerisinde Değiştirilmesi Gereken Alanlar
Scripti kendi ortamınızda kullanmadan önce bazı alanları mutlaka düzenlemeniz gerekir.

SMTP Ayarları
Mail gönderimi için SMTP sunucu bilgileri ortamınıza göre değiştirilmelidir.

$SmtpServer = “SMTP_SERVER_IP_OR_HOSTNAME”
$SmtpPort = 25
$From = “rapor@firma.com” -> Gönderici Mail Adresi

Burada SMTP sunucu IP adresi, port bilgisi ve gönderen mail adresi kendi mail yapınıza göre düzenlenmelidir. Mail gönderimi için ortamınızda mevcut bir SMTP sunucusu kullanabilir veya ayrıca SMTP relay server kurarak bu script üzerinden rapor gönderimini sağlayabilirsiniz.

Mail Alıcıları
Raporun kimlere gönderileceği bu bölümden ayarlanır.

$BulkRecipients = @(
“sistem.yoneticisi@firma.com”,
“altyapi.ekibi@firma.com”
)

Buraya sistem yöneticileri, altyapı ekibi veya ilgili destek ekibinin mail adresleri eklenebilir.

Test Modu
Script içerisinde test modu kullanılabilir.

$TestMode = $false
$TestRecipient = “test.kullanici@firma.com”

İlk denemelerde bu değeri true yaparak raporun sadece test adresine gitmesini sağlayabilirsiniz.

$TestMode = $true
$TestRecipient = “test.kullanici@firma.com”

Bu sayede scripti canlı kullanıma almadan önce mail formatını ve rapor içeriğini kontrol edebilirsiniz.

Varsayılanda indirdiğinizde test modu aktif gelmektedir.

Rapor Klasörü
Raporların kaydedileceği klasör bu bölümden değiştirilebilir.

$ReportDir = "C:\Temp"
İsterseniz farklı bir klasör, log dizini veya ortak bir paylaşım alanı belirleyebilirsiniz.

DCDiag Timeout Süresi
Büyük Active Directory ortamlarında DCDiag testleri uzun sürebilir. Bu nedenle timeout süresi ortam büyüklüğüne göre artırılabilir.

$DcDiagTimeoutSeconds = 600
Eğer testler tamamlanmadan kesiliyorsa bu değeri yükseltebilirsiniz.

Hata Filtreleme Kelimeleri
Script içerisinde belirli hata kelimeleri filtrelenerek raporda öne çıkarılır.

Örnek olarak:

$Patterns = @( 'failed test', 'error', 'warning' )
İhtiyaca göre bu listeye farklı kelimeler eklenebilir. Örneğin kurumunuza özel takip etmek istediğiniz hata mesajları varsa bu bölüme dahil edebilirsiniz.

Zamanlanmış Görev Olarak Çalıştırma
Bu script Windows Task Scheduler ile zamanlanmış görev olarak çalıştırılabilir.

Benzer kontrolleri günlük, haftalık veya bakım öncesi otomatik çalıştırmak için zamanlanmış görev oluşturulabilir.

Örnek senaryolar:

Her sabah otomatik sağlık raporu almak
Haftalık Active Directory durum kontrolü yapmak
Bakım öncesi DC durumunu raporlamak
Replikasyon sorunlarını düzenli takip etmek
Bu şekilde script manuel çalıştırmaya gerek kalmadan düzenli rapor üretebilir.

Uyarı!
Bu yazıda paylaşılan script ve açıklamalar örnek kullanım içindir. Scriptin kullanımı, düzenlenmesi ve canlı ortamlarda çalıştırılması tamamen kullanıcının sorumluluğundadır.

Yanlış yapılandırma, eksik yetki, hatalı SMTP bilgisi, ortam farklılıkları veya yanlış kullanım nedeniyle oluşabilecek veri kaybı, servis kesintisi, güvenlik problemi ya da sistem hatalarından sorumluluk kabul edilmez.

Canlı ortamda kullanmadan önce test ortamında denenmesi ve kurum yapısına göre kontrol edilmesi önerilir.
