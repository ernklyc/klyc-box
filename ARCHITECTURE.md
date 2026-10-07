# Mimari

KLYC-Box üç katmandan oluşur. Kural: **mantık Kit'te, durum model sınıflarında, ekranlar sadece çizer.**

```
Sources/
  KLYCKit/        Çekirdek kütüphane. Arayüzden habersiz, tamamı testlenir.
  KLYCBoxApp/     SwiftUI uygulaması.
  klycbox/        Komut satırı aracı (Kit'in ince bir yüzü).
Tests/KLYCKitTests/   Birim testleri (Kit'in her yeni kuralı burada).
recipes/, db/     Oyun tarifleri, uyumluluk veritabanı, mod kataloğu (CC0 veri).
```

## KLYCKit (model ve iş mantığı)
Saf ve test edilebilir parçalar. Yeni bir kural yazıyorsan önce burada, testiyle birlikte.
- `Bottle`, `BottleStore`, `Recipe`, `WineRunner`, `EngineStore`: Wine ortamları ve çalıştırma.
- `LibraryItem`, `LibraryQuery`, `HomeShelf`: oyun listesi, süzme, sıralama, Ana sayfa şeridi.
- `LibraryStore`: oynama geçmişi, favoriler, oyuna özel grafik modu (`library.json`).
- `TuningStore` / `TuningResult`: "İyileştir" sonuçları (`tuning.json`).
- `ModInstaller`, `ModDLLOverrides`, `WindowsPath`, `ModCatalog`: mod dosyalarını yedekli ekleme, geri alma, DLL ayarı.
- `Verifier`: bir oyunu bir grafik modunda açıp çökme / siyah ekran kontrolü.
- `L10n*`, `L(_:)`: çeviri (İngilizce anahtar, Türkçe ve Fransızca sözlük).

## KLYCBoxApp (görünüm)
- **AppState** (`@Observable`): uygulamanın tek deposu (ortamlar, oyunlar, çalışan işler). Dosyalara bölünmüştür:
  `AppState.swift` (çekirdek), `AppState+Improve.swift` (favoriler, İyileştir), `AppState+Mods.swift` (modlar).
  Yeni bir özellik yeni bir `AppState+Özellik.swift` olur; ana dosya büyümez.
- **ViewModel'ler** (`@Observable`, `@MainActor`): bir ekranın durumu ve kararları. Ekranın içinde iş mantığı bulunmaz.
  `LibraryViewModel`, `HomeViewModel`. Süzme/sıralama gibi hesap Kit'tedir.
- **Görünümler:** `Shell` (üst çubuk, sekmeler, Ana sayfa), `LibraryView`, `GameDetailView`, `ModsPanel`, `SettingsView`...
- **Tasarım sistemi** (`Components.swift`): `StatusPill`, `HBPrimaryButtonStyle`, `HBSecondaryButtonStyle`, `HBCompactButtonStyle`,
  `HBSegment`, `HBSearchField`, `hbGlass`, `hbCard`, `HeroBackdrop`, `BottleBackdrop`. Ekranlarda ham renk/boyut yerine bunlar kullanılır.
- **Sesler** (`UISound`): kendi ürettiğimiz yumuşak tonlar.

## Uyumluluk verisi: kim neyi biliyor, nasıl paylaşılır
- `db/games/*.json` (veritabanı): herkesin göreceği sonuçlar. Uygulamayla birlikte gelir. Her satırda kaynak (`provenance`) ve hangi Mac'te ölçüldüğü yazar.
- `verdicts.json` (veri klasöründe, **yerel**): oyuncunun kendi Mac'i için cevabı: çalışıyor / sorun var, gördüğü fps (elle yazılır, hesaplanmaz). Oyun sayfasında "Senin Mac'in" olarak başkalarının sonuçlarının **üstünde** görünür.
- `tuning.json` (yerel): "İyileştir"in denediği grafik modları ve sonuçları.
- **Paylaşma:** oyun sayfasındaki "Paylaş…" proje deposunun rapor formunu (`.github/ISSUE_TEMPLATE/report.yml`) doldurulmuş açar; gönderen kişi Create'e basar.
- **Veritabanına katma:** Ayarlar → Genel → "Sonuçlarını dışa aktar…", sonra `Scripts/ingest-verdicts.py dosya.json` (önce `--dry-run`) `db/games` satırlarını günceller. Sonraki sürümle herkes görür.

## Veri akışı
`Görünüm → ViewModel → AppState → KLYCKit (Store, Runner)`. Yukarı doğru bağımlılık yoktur: Kit hiçbir görünümü tanımaz.

## Yeni özellik eklerken
1. Kuralı Kit'e yaz, `Tests/KLYCKitTests` altına test ekle.
2. Gerekirse `AppState+Özellik.swift` ile uygulamaya bağla.
3. Ekran durumu için ViewModel, çizim için görünüm. Metinler `L("English")` ile, Türkçesi `L10nTRKit.swift`'e.
4. `Scripts/health-check.sh` yeşil olmadan birleştirme.
