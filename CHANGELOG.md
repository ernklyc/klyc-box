# Değişiklik günlüğü / Changelog

Sürüm numaraları [SemVer](https://semver.org) mantığıyla. Sürüm: `Scripts/release-klyc.sh`.

## 1.0.3 (9 Ekim 2026)
- **Steam'in siyah pencere sorununun gerçek nedeni bulundu.** Wine 11 (CrossOver 26.3) motorunda Steam'in kendi penceresi siyah kalıyor; aynı ortam Wine 10 (Sikarugir) motorunda Steam'i sorunsuz açıyor. 1.0.2'deki `-cef-disable-gpu` düzeltmesi bunu çözmüyordu, kaldırıldı. Artık Steam'i Wine 11 motorundaki bir ortamda başlatmaya çalışınca boş bir pencere açmak yerine ne yapılacağı söylenir (ortamı Wine 10'a al). Oyunlar etkilenmez, yalnızca Steam'in kendi penceresi.

## 1.0.2 (9 Ekim 2026)
- Denendi, işe yaramadı: Steam'i Wine 11 motorunda yazılım çizimiyle başlatma bayrağı. Pencere yine siyah kalıyordu. 1.0.3'te kaldırıldı; asıl çözüm yukarıda.

## 1.0.1 (8 Ekim 2026)
- **Steam mağazası uygulamanın diliyle konuşuyor:** oyun açıklamaları, yorumlar, etiketler, tarih ve fiyat biçimi artık Türkçe, English, 简体中文 ya da 日本語 (eskiden uygulama İngilizce olsa bile Türkçe geliyordu). Fiyat bölgesi Türkiye olarak kalır.
- Highball'dan kalan kısmi Fransızca çeviri kaldırıldı; Fransızca ayarlı bir Mac artık İngilizce görür.

## 1.0.0 (8 Ekim 2026)

İlk herkese açık sürüm. KLYC-Box, Gauthier Piarrette'in [Highball](https://github.com/gauthierpiarrette/highball) projesinin fork'u olarak başladı ve onun üzerine geliştirildi; atıflar ve değişiklik bildirimi [NOTICE.md](NOTICE.md) içinde.

- **Dört dil:** Türkçe, English, 简体中文, 日本語. Ayarlar › Genel › Dil'den seçilir ("Otomatik" Mac'in dilini izler); değişiklik için "Şimdi yeniden başlat" düğmesi var.
- **Atlas (oyun rehberi) entegrasyonu:** oyun sayfasında ve Steam mağaza sayfasında "Atlas" bölümü: oyuncuların ne dediği, kaydedilen grafik modu, çıkış yılı ve türü, Highball denemesi ya da hile koruması; "Atlas'ta aç" ile sitedeki oyun sayfasına geçersin. Veri sitenin küçük beslemesinden gelir (günde en fazla bir kez, ETag'li) ve önbellekte tutulur; ağ yoksa son hali kullanılır. Beslemede tarif, kurulum adresi ya da başlatma argümanı yok.
- **Mağazada Atlas süzgeci:** Steam mağazasında "Bu Mac'te" süzgeci: Denendi, Oyuncu bildirdi, "Çalışması muhtemel (tahmin)" ve Çalışmaz. Liste en iyi kanıtlıdan başlar, en fazla 240 oyun gösterir; oyun kartlarında ve sayfalarında rozet olarak da görünür.
- **Hakkında sayfası:** Ayarlar › Hakkında: projenin ne olduğu, oyun rehberi sitesi, kaynak kod, gizlilik ve sorun bildirme bağlantıları, üzerine kurulduğumuz tüm projelerin listesi (lisans ve bağlantı) ve Highball'a atıf.
- **Steam ve Epic bir arada:** kütüphane, kendi Steam mağazası ve Epic ekranı, arkadaşlar ve profil. Epic indirmelerinde yüzde, hız, kalan süre, Duraklat / Devam / İptal; uygulama kapanırken indirmeler nazikçe duraklatılır.
- **Oyun başına ayar:** grafik modu, kare hızı sınırı, başlatma seçenekleri, modlar, kayıt yedekleri ve geri yükleme.
- **Oyuncu raporları (isteğe bağlı):** oyun sayfasında "Tek bir oyun için anonim rapor": çalışıyor mu, 1-5 puan, kısa not; çipin ve macOS sürümün otomatik eklenir. Göndermeden önce giden her alanı görürsün; geri çekilebilir. Ad ve e-posta yok.
- **Çökme raporu, izinle:** beklenmedik kapanıştan sonraki ilk açılışta uygulama GitHub'da hazır doldurulmuş bir rapor açmayı *önerir*; kendiliğinden hiçbir şey göndermez. İçinde yalnızca çökmenin türü, sürümler ve çöktüğü işlev adları var (dosya yolu, oyun, hesap yok).
- **Kendi motor deposu:** motorun indirmelerinin çoğu `ernklyc/klyc-engine` sürümünde; her dosya SHA-256 ile doğrulanır. Sikarugir'in runtime paketi Apple'ın D3DMetal'ini içerdiği için kopyalanmaz.
- **Hesap güvenliği:** Steam girişi yalnızca Steam'in kendi istemcisinde ve sayfalarında, Epic girişi Epic'in sayfası ve tek kullanımlık kodla; şifre ve anahtarlar KLYC-Box'a görünmez. Ayrıntılar: [SECURITY.md](SECURITY.md).
- **Kendi güncelleme kanalı:** Sparkle, kendi imza anahtarıyla; "güncelleme var" rozeti Ayarlar düğmesinde ve Ayarlar'ın tepesinde görünür.
- **Sürüm kapısı:** her sürümden önce testler ve ilk kurulum testi (`Scripts/firstrun-smoke.sh`: motoru boş bir klasöre sıfırdan kurar) geçmek zorunda.
- Siyah ve çelik mavisi tema; macOS 26 ve üstünde Liquid Glass.
