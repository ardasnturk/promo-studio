# Promo Studio kurulumu

[English](SETUP.md) · **Türkçe**

Promo Studio, Mac'inde kurulu araçları kullanır. Açılışta bunları denetler; zorunlu bir şey eksikse **kurulum kontrol
listesini** açar. Listeyi istediğin zaman **Yardım → Kurulum kontrol listesi…** ile açabilirsin.

| | Ne için | Zorunlu |
|---|---|---|
| [Claude Code](#claude-code) | Analiz, senaryo, storyboard, videoların kodlanması | Evet |
| [Node.js 20+](#nodejs-ve-remotion) | Video motoru Remotion | Evet |
| [Remotion](#nodejs-ve-remotion) | Video render (Promo Studio kurar) | Evet |
| git | Promo Templates'i kurmak ve güncellemek | Hayır |
| Xcode | Simülatörden yerelleştirilmiş ekranlar | Hayır |
| [Gemini API anahtarı](#gemini-seslendirme) | Seslendirme | Hayır |
| [Instagram](#instagram) | Paylaşım ve zamanlama | Hayır |
| [YouTube](#youtube) | Kanalında Shorts | Hayır |
| [Promo Templates](../README.tr.md) | Hazır video kalıpları ve skill'ler | Hayır |

İsteğe bağlı öğeler olmadan da video üretebilirsin: Gemini anahtarı yoksa videolar seslendirmesiz olur; Instagram
bağlı değilse videoyu stüdyodaki **Videoyu kaydet…** ile kaydedip kendin paylaşırsın.

## Claude Code

1. Claude Code'u kur: <https://claude.com/claude-code>.
2. Terminal'de bir kez oturum aç:

   ```bash
   claude auth login
   ```

3. Kontrol et: `claude auth status` çıktısında `"loggedIn": true` görünmeli.

Promo Studio kendi `claude` CLI'ını senin hesabınla çalıştırır; kullanım Claude planından ya da API kullanımından düşer.

## Node.js ve Remotion

1. Node.js 20 veya üstünü <https://nodejs.org> adresinden ya da Homebrew ile kur:

   ```bash
   brew install node
   ```

2. Kurulum kontrol listesinde **Remotion** satırındaki **Kur** düğmesine bas. Video şablonu
   `~/Library/Application Support/Promo Studio/remotion` klasörüne kopyalanır ve `npm install` çalışır (ilk seferde
   birkaç dakika sürer).

Promo Studio, Remotion'la gelen `ffmpeg`'i kullanır; ayrıca ffmpeg kurman gerekmez.

**Araç kurulu ama "bulunamadı" görünüyorsa:** Finder'dan açılan uygulamalar Terminal'in `PATH`'ini almaz. Promo Studio
bunu login shell'den (`zsh -l`) okur; ayrıca `/opt/homebrew/bin`, `/usr/local/bin` ve `~/.local/bin` klasörlerine bakar.
Araç başka bir yerdeyse (ör. yalnızca `.zshrc`'de etkin olan bir sürüm yöneticisi), onu `~/.zprofile`'da da tanımla ve
**Yeniden denetle**'ye bas.

## Gemini seslendirme

1. [Google AI Studio](https://aistudio.google.com)'da bir API anahtarı oluştur (**Get API key**).
2. **Hesap ve Ayarlar → Seslendirme ve müzik → Gemini API anahtarı** alanına yapıştır. Promo Studio anahtarı
   Keychain'de saklar. İstersen shell profilinde `GEMINI_API_KEY` de tanımlayabilirsin.

Bir videonun tüm seslendirme satırları tek istekte üretilir. Ücretsiz katmanda TTS modeli başına günde yaklaşık 10 istek
hakkı var. Kota dolunca Promo Studio ne zaman yenileneceğini söyler; bu arada **Seslendirmesiz** üretebilir ya da
Ayarlar'dan başka bir TTS modeli seçebilirsin.

## Instagram

Paylaşım, Instagram'ın resmi API'leriyle ve senin kendi Meta geliştirici uygulamanla yapılır. Yalnızca paylaşım,
zamanlama ve analiz için gerekir. Promo Studio parola saklamaz; token'lar Keychain'de durur.

### 1. Instagram hesabını hazırla

- Hesap **İşletme** ya da **İçerik üreticisi** hesabı olmalı. Instagram uygulamasında: **Ayarlar → Hesap türü ve
  araçlar → Profesyonel hesaba geç**.
- **Facebook girişi** (önerilen) için hesabı yönettiğin bir Facebook sayfasına bağla: sayfanın ayarlarında **Bağlı
  hesaplar → Instagram → Bağlan**. Birden çok sayfaya bağlı birden çok Instagram hesabı tek girişte eklenir.

### 2. Meta uygulaması oluştur

1. <https://developers.facebook.com/apps> adresinde **Create App**'e bas. **Facebook Login for Business** ekleyebileceğin
   seçenekleri seç (**Business** türü uygulama). Meta bu sihirbazı zaman zaman değiştiriyor; kullanım alanı sorarsa
   Instagram içeriğini yönetmeyle ilgili olanı ya da **Other**'ı seç.
2. **Facebook Login for Business** ürününü ekle. **Settings** bölümünde:
   - **Embedded Browser OAuth Login**'i aç,
   - **Valid OAuth Redirect URIs** listesine `https://www.facebook.com/connect/login_success.html` ekle.
3. Şu izinlerin uygulamada kullanılabilir olduğundan emin ol (geliştirme modunda, uygulamada rolü olan kişiler için
   App Review gerekmez):
   `instagram_basic`, `instagram_content_publish`, `instagram_manage_insights`, `instagram_manage_comments`,
   `pages_show_list`, `pages_read_engagement`, `business_management`.
4. **App settings → Basic** bölümünden **App ID** ve **App Secret**'ı kopyala.

Kendi hesapların için uygulama **geliştirme modunda** kalabilir: yalnızca uygulamada rolü olan kişiler (yönetici,
geliştirici, test kullanıcısı) giriş yapabilir; sen de bunlardansın.

### 3. Promo Studio'da bağla

1. **Hesap ve Ayarlar → Meta uygulaması**: App ID ve App Secret'ı yapıştır. Yönlendirme URI'sini olduğu gibi bırak.
2. **Facebook ile giriş yap**'a bas, oturum aç, uygulamayla paylaşılacak sayfaları ve Instagram hesaplarını seç.
3. Bu sayfalara bağlı tüm Instagram hesapları eklenir. App Secret girildiyse token 60 güne uzatılır ve süresi dolmadan
   yenilenir. Sonradan bağladığın hesapları **Hesapları yenile** yeniden giriş yapmadan ekler.
4. Her projede paylaşım yapacağı hesabı proje başlığındaki hesap seçiciden seç.

### Instagram girişi (alternatif)

Facebook sayfan yoksa bağlantı türü olarak **Instagram girişi**'ni seç. Meta uygulamasına "API setup with Instagram
login" ile **Instagram** ürününü ekle; `instagram_business_basic`, `instagram_business_content_publish`,
`instagram_business_manage_insights`, `instagram_business_manage_comments` izinlerini ve Promo Studio'nun yönlendirme
URI'sini (varsayılan `https://localhost/promostudio/callback`) gir. Geliştirme modunda Instagram hesabını test kullanıcısı
olarak ekle (**App roles → Roles → Instagram Testers**) ve daveti Instagram'da kabul et.

### Sorun çıkarsa

- **Girişten sonra hesap yok:** Promo Studio neyin eksik olduğunu söyler: yukarıdaki izinlerden biri, girişte
  seçilmeyen bir sayfa ya da hesap, veya sayfaya bağlı profesyonel hesap olmayan bir Instagram hesabı. Düzelt ve yeniden
  giriş yap.
- **Paylaşırken izin hatası:** çoğunlukla `instagram_content_publish` verilmemiştir. Yeniden giriş yap ve istenen tüm
  izinleri onayla.
- **Token süresi doldu:** App Secret girildiyse Promo Studio token'ı kendisi yeniler; girilmediyse yeniden giriş yap.

## YouTube

Videolar resmi YouTube Data API ile bir YouTube kanalına Shorts olarak da gidebilir. Ücretsizdir; ama Instagram'ın
kendi Meta uygulamanı kullanması gibi, kendi Google Cloud projende kurarsın.

### 1. Google uygulamasını oluştur

1. [Google Cloud Console](https://console.cloud.google.com)'u aç ve bir proje oluştur (ya da birini seç).
2. **APIs & Services → Library:** **YouTube Data API v3**'ü etkinleştir.
3. **APIs & Services → OAuth consent screen:** **External**'ı seç, uygulama adını ve e-postanı gir, kendini test
   kullanıcısı olarak ekle. Sonra **yayın durumunu In production** yap. Testing durumundayken Google oturumu her 7
   günde bir kapatır. Giriş yaparken kendi uygulaman için "Google bu uygulamayı doğrulamadı" uyarısı çıkar;
   **Continue**'yu seç.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**, tür olarak **Desktop app**. İstemci
   kimliğini ve gizli anahtarı kopyala.

### 2. Promo Studio'da bağla

**Ayarlar → YouTube**'da istemci kimliğini ve gizli anahtarı yapıştır, sonra **YouTube Kanalı Bağla**'ya tıkla.
Google'ın izin sayfası tarayıcında açılır; kanalı seç ve erişime izin ver. Tarayıcı Promo Studio'ya kendisi döner.

Bağladığın ilk kanal varsayılan olur: yeni videolar oraya da gider. Her gönderinin **Yayınla** sekmesinde başka bir
kanal seçebilir ya da YouTube'u dışarıda bırakabilirsin; Ayarlar'daki **Yeni videoları paylaş** seçeneği de bunu
değiştirir.

### 3. YouTube denetimine başvur

**Google projeni denetleyene kadar YouTube, projeyle yüklenen her videoyu gizli tutar ve bu şekilde kilitlenen bir
video sonradan herkese açılamaz.** Bu olduğunda Promo Studio seni uyarır ve denetimden sonra videoyu yeniden yüklemeyi
önerir. [YouTube API Services – Audit and Quota Extension formu](https://support.google.com/youtube/contact/yt_api_form)
ile başvur; ücretsizdir ve birkaç hafta sürebilir.

### Paylaşım nasıl çalışır

- Video Shorts olarak yüklenir: gönderinin başlığı (Claude YouTube için ayrıca yazar), açıklama olarak metin ve
  hashtag'ler, bir de `#Shorts`. Görseller yalnızca Instagram'a gider.
- **Şimdi yayınla** Instagram'a ve YouTube'a birlikte paylaşır. Biri başarısız olursa yeniden denemek yalnızca onu
  tekrarlar.
- **Zamanla** videoyu hemen YouTube'a yükler ve bir yayın saatiyle gizli bırakır: Mac kapalı olsa bile YouTube o saatte
  kendisi yayınlar. Instagram için Promo Studio'nun o saatte açık olması gerekir.
- Yapay zekâyla düzenlenmiş fotoğraflarda kişiler gösteren videolar YouTube'da değiştirilmiş içerik olarak işaretlenir.
- İzlenme, beğeni ve yorumlar gönderinin Yayınla sekmesinde görünür.
- Google her projeye ücretsiz bir günlük kota verir. Dolduğunda Promo Studio bunu söyler; kota Pasifik saatiyle gece
  yarısı sıfırlanır.

## Keychain izinleri

macOS, bir uygulama Keychain kaydını okumadan önce bir kez sorar. **Her zaman izin ver**'i seç. Sabit bir kimlikle
imzalanan derlemeler (yayın sürümleri ya da `Config/Signing.local.xcconfig` ile kendi ekibin, bkz.
[Config/Signing.xcconfig](../Config/Signing.xcconfig)) bu izni güncellemelerde korur. Kaynaktan ad-hoc derlenen
sürümler her derlemeden sonra yeniden sorar.
