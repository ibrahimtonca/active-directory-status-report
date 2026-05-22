Active Directory Detaylı Durum Raporu Scripti

Active Directory ortamlarında Domain Controller sunucularının durumunu düzenli olarak kontrol etmek için hazırladığım bu PowerShell scripti, temel sağlık kontrollerini otomatik olarak raporlamak amacıyla kullanılabilir.

Birden fazla Domain Controller bulunan yapılarda DCDiag çıktıları, servis durumları, DNS kontrolleri ve replikasyon sonuçlarını manuel olarak takip etmek zaman alabiliyor. Bu script ile bu kontrolleri daha okunabilir bir HTML rapor haline getirip e-posta üzerinden paylaşılabilir duruma getirdim.

Script çalıştırıldığında Active Directory ortamındaki durum bilgilerini toplar, belirlenen kontrolleri yapar ve sonuçları tablo yapısıyla HTML formatında raporlar. Böylece hem günlük kontrollerde hem de sorun analizi sırasında daha hızlı inceleme yapılabilir.

Bu script ile genel olarak aşağıdaki raporları alabiliyoruz:

- Genel durum özeti raporu
- Domain Controller bilgileri raporu
- DCDiag test sonuçları raporu
- Active Directory replikasyon durumu raporu
- DNS kontrol raporu
- Kritik servis durumu raporu
- Kritik hata ve uyarılar raporu
- HTML mail raporu

Bu script Windows PowerShell 5.1 üzerinde hazırlanmıştır. Active Directory PowerShell modülü yüklü olan Windows Server ortamlarında kullanılabilir. PowerShell 7 üzerinde kullanılacaksa Active Directory modül uyumluluğu ayrıca test edilmelidir.

Kullanım detayları için blog yazısını ziyaret edebilirsiniz:

https://www.ibrahimtonca.com/active-directory-detayli-durum-raporu-scripti/
