# Promo Studio

[English](README.md) · **Türkçe**

Geliştirdiğin uygulamalar için sosyal medya içeriği üreten, paylaşan ve takip eden macOS kontrol paneli. İlk platform Instagram (Reels).

Akış: proje klasörünü seç → Claude Code kodu analiz eder (özellikler, hedef kitle, marka renkleri, ekran görüntüleri) → bir özellik ya da öneri seç (veya kendi isteğini yaz; Claude gerekirse web’de araştırır) → Claude senaryoyu, açıklamayı ve hashtag'leri yazar → Remotion videoyu render eder → hemen paylaş ya da zamanla → izlenme/erişim istatistiklerini takip et.

## Kurulum

[Releases](https://github.com/ardasnturk/promo-studio/releases/latest) sayfasından `PromoStudio-<sürüm>.dmg` dosyasını
indirip Promo Studio'yu Uygulamalar klasörüne sürükle ya da Homebrew kullan:

```bash
brew tap ardasnturk/promo-studio https://github.com/ardasnturk/promo-studio
brew install --cask promo-studio
```

Uygulama Developer ID ile imzalı ve Apple tarafından notarize edilmiştir.

## Gereksinimler

- macOS 15+, Xcode 16+ ve [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Node.js 20+ (Remotion için; Promo Studio Remotion'ı kurar ve onunla gelen ffmpeg'i kullanır)
- [Claude Code](https://claude.com/claude-code) CLI'ı kurulu ve oturum açılmış olmalı (`claude auth status`)
- İsteğe bağlı: seslendirme için [Gemini API anahtarı](https://aistudio.google.com)
- İsteğe bağlı, paylaşım için: Instagram **İşletme** ya da **İçerik üreticisi** hesabı ve kendi Meta uygulaman

## Derleme

```bash
xcodegen generate
open PromoStudio.xcodeproj
```

Promo Studio açılışta gereksinimleri denetler ve zorunlu bir şey eksikse **kurulum kontrol listesini** açar (ayrıca
**Yardım → Kurulum kontrol listesi…**); Remotion'ı tek tıkla kurar. Meta uygulaması ve Gemini anahtarı dahil adım adım
anlatım: **[docs/SETUP.tr.md](docs/SETUP.tr.md)**.

Instagram bağlamak isteğe bağlı: bağlamadan stüdyodaki **Videoyu kaydet…** ya da **Paylaş** ile MP4'ü alıp kendin
paylaşabilirsin.

## Instagram bağlantısı

Promo Studio, resmi **Instagram API with Instagram Login** kullanır (şifre saklanmaz, hesabın riske girmez).

1. [developers.facebook.com](https://developers.facebook.com) → yeni uygulama → **Instagram** ürününü ekle → "API setup with Instagram login".
2. İzinler: `instagram_business_basic`, `instagram_business_content_publish`, `instagram_business_manage_insights`, `instagram_business_manage_comments`.
3. "Business login settings" altında **OAuth redirect URI** olarak Promo Studio'daki yönlendirme URI'sini gir (varsayılan `https://localhost/promostudio/callback`; sayfanın açılması gerekmez, Promo Studio yönlendirmeyi yakalar).
4. Promo Studio → Hesap → Instagram App ID + App Secret → **Instagram ile giriş yap**.

Hızlı test: uygulama panelindeki "Generate access token" ile aldığın token'ı doğrudan yapıştırabilirsin. Uygulama "Development" modundayken yalnızca uygulamaya tester olarak eklenen hesaplar bağlanabilir.

**Facebook girişi (varsayılan):** Meta panelinde "Instagram girişiyle API kurulumu" görünmüyorsa bu yol kullanılır. Instagram hesabı bir Facebook sayfasına bağlı olmalıdır. Meta uygulamasına `instagram_basic`, `instagram_content_publish`, `instagram_manage_insights`, `instagram_manage_comments`, `pages_show_list`, `pages_read_engagement` ve `business_management` izinlerini ekle. Facebook Login for Business ayarlarında "Eingebettete Browser-OAuth-Anmeldung" (gömülü tarayıcıda OAuth girişi) açık olmalı. Promo Studio → Hesap → App ID → **Facebook ile giriş yap**. App Secret girildiğinde token otomatik olarak 60 güne uzatılır.

Videolar resumable upload ile doğrudan yüklenir; herkese açık bir sunucuya gerek yoktur. Token 60 gün geçerlidir ve süresi dolmadan otomatik yenilenir.

**Birden fazla hesap:** Her proje kendi Instagram hesabına bağlanır (proje ekranının başlığındaki hesap seçici). Paylaşım, zamanlama ve istatistikler o hesabın token'ıyla yapılır; hesabı olmayan projenin videoları paylaşılmaz. Facebook girişi, yönettiğin sayfalara bağlı tüm Instagram hesaplarını tek seferde ekler; adı bir projeyle eşleşen hesap o projeye otomatik bağlanır.

## Kendi isteğinle video (prompt)

Proje ekranındaki **Kendi isteğinle video → Prompt yaz…** (ya da Özelleştir… → "Kendi isteğim"). İki video türü var:

### Promosyon filmi (Claude yönetir, varsayılan)

Ekran görüntüsü slaytı değil, her video için özel kodlanan bir reklam filmi:

1. **Storyboard:** Claude isteğini (gerekirse web'de araştırarak) sahne sahne bir yönetmen storyboard'una çevirir: konsept/görsel dil, her sahnenin görsel ve hareket notu, ekran metni, seslendirme, ses efektleri ve kullanılacak proje görselleri. Stüdyonun **Storyboard** sekmesinde görünür; alanları elle düzeltebilir ya da **Claude ile revize** sekmesinden talimat verebilirsin.
2. **Onay ve üretim:** "Onayla ve videoyu üret" ile Promo Studio seslendirmeyi üretir (sahne süreleri sese göre ayarlanır), Claude videoyu Remotion'da kodlar (`src/videos/<id>/`), `tsc` ve sahne kareleriyle kendi işini kontrol eder, ardından Promo Studio render eder.
3. **Video üzerinden revizyon:** Talimat ver ("kancadaki başlık kenara taşıyor, ortala"); Claude önce storyboard'u, sonra yalnızca ilgili kodu günceller ve video yeniden render edilir. Her revizyondan önceki storyboard ve kod saklanır, "Bu sürüme dön" ile geri alınır.

- **Kit:** Claude, `RemotionTemplate/src/kit` hareketli grafik kitini (kinetik tipografi, sayaç, olasılık çubuğu, geri sayım, rozet/karşılaşma tabelası, bildirim kartı, telefon/zoom, saha, parçacık, flaş, sarsıntı, ses efektleri) kullanır; kılavuzu `RemotionTemplate/KIT.md`. Kit yetmezse videonun klasöründe kendi bileşenini yazar.
- **Marka kiti:** Bir şablon kütüphanesinin Remotion klasöründe projeyle aynı adda klasör varsa (ör. `src/Acme` klasörü, Acme projesi için), Claude o marka kitini ve kütüphanenin CLAUDE.md kurallarını okur; kütüphanenin `public/<proje>` görselleri stüdyoya kopyalanır. Kütüphaneye yazılmaz.
- **Yetki:** Claude yalnızca o videonun klasörüne yazabilir (`Edit(src/videos/<id>/**)`); yalnızca `npx tsc` ve `npx remotion still` komutlarını çalıştırabilir.

### Hızlı şablon (ekran görüntüleri)

1. **İstek:** Ne istediğini yaz (ör. "Bu hafta sonu büyük bir güncelleme yayınlıyoruz, yeni özelliği öne çıkaran enerjik bir tanıtım filmi yap"). İstersen öne çıkacak özelliği seç; boş bırakırsan Claude seçer.
2. **Araştırma:** "Claude web'de araştırsın" açıksa Claude güncel bilgileri (maç tarihi/saati, form, kadro…) WebSearch/WebFetch ile doğrular. Yalnızca doğruladığı bilgiyi kullanır; bulgular ve kaynaklar stüdyonun **Claude ile revize** sekmesinde görünür.
3. **Onay:** Bu modda otomatik render varsayılan olarak kapalıdır; senaryoyu inceleyip soldan render edersin.
4. **Revizyon:** **Claude ile revize** sekmesinde talimat ver ("kancayı sertleştir, 3. sahnede kadroyu göster"). Claude yalnızca istenen yerleri değiştirir. Her revizyondan önceki sürüm saklanır ve "Bu sürüme dön" ile geri alınır. Render sonrası revize edilen videoda önizleme eski sürüme ait olarak işaretlenir; yeniden render et.

## Seslendirme, müzik ve diller

- Claude her sahne için bir seslendirme cümlesi yazar (`[excited]` gibi ton etiketiyle). Render sırasında tüm cümleler tek bir Gemini TTS isteğiyle seslendirilir, sessizliklerden sahnelere bölünür ve sahne süreleri sese göre ayarlanır. Metin değişmedikçe ses yeniden üretilmez.
- Gemini anahtarı Ayarlar → Seslendirme ve müzik'ten girilir; boşsa shell'deki `GEMINI_API_KEY` kullanılır. Ücretsiz kota model başına günde ~10 istektir (video başına 1 istek).
- Arka plan müziği yerel olarak üretilen telifsiz 120 BPM bir ritimdir; konuşma sırasında kısık çalar.
- Her video kendi dilinde üretilir (Türkçe, English, Deutsch, Español, Italiano, Français, Português, 日本語, 한국어, 简体中文). Stüdyodaki "Başka dilde kopyala" videonun metinlerini, seslendirmesini, açıklamasını ve hashtag'lerini hedef pazara uyarlayıp yeniden render eder.
- Promo Studio'nun arayüzü Remote Code ile aynı dillerde: İngilizce, Türkçe, Almanca, İspanyolca, Fransızca, İtalyanca, Portekizce (Brezilya), Japonca, Korece ve Basitleştirilmiş Çince. Mac'inin dilini izler; başka bir dil için Sistem Ayarları → Genel → Dil ve Bölge → Uygulamalar.

## Simülatörden yerel ekranlar

Sadece tek dilde bulunan ham uygulama ekranları için proje ekranındaki **Yerel ekranlar…**:

1. **Tarifi çıkar:** Claude Code kodu (UI testleri, launch argümanları, derin bağlantılar) inceleyip her ekranın nasıl açılacağını bulur. Tarif bundle ID'yi, derleme bilgisini, demo argümanlarını ve her ekran için derin bağlantıyı ve dokunma adımlarını (erişilebilirlik kimlikleri) içerir.
2. **Ekranları yakala:** Promo Studio kendine ait bir simülatör oluşturur ("Promo Studio · iPhone"). Uygulama kurulu değilse simülatör için derleyip kurar. Ardından paketteki XCUITest aracıyla (`CaptureRunner/`) her dilde uygulamayı açar, sistem onaylarını geçer, ekranları 9:41 durum çubuğuyla ve orijinal görselin koyu/açık temasında yakalar.
3. Yakalanan ekranlar ilgili görselin o dildeki karşılığı olarak kaydedilir. "Başka dilde kopyala" bunları otomatik kullanır; tarifi olan projelerde eksik ekranlar uyarlamadan önce kendiliğinden yakalanır.

## Şablon kütüphaneleri (ör. Promo Templates)

Hazır video kalıpları ve Claude Code skill'leri içeren harici bir Remotion projesi, kenar çubuğundaki **Şablonlar → Kütüphane ekle…** ile bağlanır. Kalıplar Promo Studio'ya kopyalanmaz; kütüphanede yapılan her değişiklik "Yeniden tara" ile görünür.

- **Tarama:** Remotion klasörü (package.json + `src/Root.tsx`), `.claude/skills/*/SKILL.md` (Remotion'ın genel skill'leri hariç) ve `Root.tsx`'teki kompozisyonlar (şemalı olanlar işaretli).
- **Üret:** Bir kalıp seçilip istek yazılır. Promo Studio, Claude Code'u kütüphane klasöründe arka planda o skill'le çalıştırır. Claude kütüphanenin `CLAUDE.md` kurallarına uyarak videoyu yazar, doğrular ve render eder. Promo Studio MP4'ü içe alır, kapak çıkarır ve SEO uyumlu açıklama yazdırır. Gerçek bilgi doğrulanamazsa Claude render etmez; gönderi "Girdi gerekli" notuyla taslak kalır.
- **Fikir bul:** Fikir skill'i trendleri araştırıp konsept önerir; "Bunu üret" ilgili skill'i başlatır.
- **Parametrelerle yeniden render:** Stüdyonun "Kalıp" sekmesinde render'da kullanılan props JSON olarak görünür. Düzenleyip Claude'u çalıştırmadan yeniden render edebilirsin.
- **Yetkiler:** Arka plandaki Claude Code kütüphane klasöründe dosya yazabilir, `npx`, `npm` ve `node` komutlarını çalıştırabilir ve web'de arama yapabilir. Kütüphaneye eklenen dosyalar o deponun commit edilmemiş değişiklikleri olarak kalır.

## Mimari

```
Promo Studio/
  App/AppModel.swift          Merkezi durum, iş kuyruğu, zamanlayıcı
  Services/ClaudeCode.swift   `claude -p --json-schema` çağrıları (stream-json ile canlı etkinlik)
  Services/ContentAI.swift    Analiz / senaryo / açıklama istemleri ve JSON şemaları
  Services/ProjectScanner.swift  Depodaki ekran görüntüsü adaylarını bulur
  Services/AssetService.swift    Görselleri kopyalar, iOS Simülatöründen yakalar
  Services/RemotionService.swift Şablonu kurar, video + kapak render eder
  Services/StudioService.swift   Claude'un yönettiği videolar: props, giriş dosyası, render, kod sürümleri
  Services/ContentAI+Studio.swift Storyboard yazımı/revizyonu ve videonun kodlanması istemleri
  Services/InstagramAPI.swift    OAuth, Reels paylaşımı, istatistikler
  Views/                      SwiftUI ekranları
RemotionTemplate/             Video şablonu (AppPromo kompozisyonu, 4 tema, 5 sahne türü) ve stüdyo kiti (src/kit, KIT.md)
```

- Veriler: `~/Library/Application Support/Promo Studio/data.json`; gizli bilgiler (token, app secret) Keychain'de.
- Video sözleşmesi: `PromoStudio/Models/VideoSpec.swift` ↔ `RemotionTemplate/src/types.ts` birebir aynı tutulmalı.
- Şablonu tarayıcıda denemek için: `cd RemotionTemplate && npm install && npm run studio`.

## Bilinen sınırlamalar

- Zamanlanmış paylaşımlar uygulama açıkken gerçekleşir (pencere kapatılsa da menü çubuğunda çalışmaya devam eder). Mac uykudaysa paylaşım uyanınca yapılır.
- Instagram API yalnızca Business/Creator hesaplarında paylaşıma izin verir.
