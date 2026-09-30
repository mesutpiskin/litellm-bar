# LiteLLM Bar

macOS menü çubuğunda (sağ üst) duran, [LiteLLM](https://github.com/BerriAI/litellm) proxy'nizdeki **model, token ve harcama** kullanımınızı gösteren hafif, native (SwiftUI) bir uygulama.

Admin hesabı gerektirmez — kendi **sanal anahtarınız (sk-…)** ya da LiteLLM UI **kullanıcı adı/şifreniz** yeterlidir.

## Özellikler

- Menü çubuğunda bugünkü harcama / token / toplam harcama (seçilebilir)
- Toplam harcama, bütçe ve bütçe sıfırlanma tarihi, RPM/TPM limitleri
- Bugün / 7 / 30 / 90 günlük aralıkta: harcama, toplam token, girdi/çıktı token, istek & hata sayısı
- Günlük grafik (harcama / token / istek)
- Model bazlı kırılım (harcama, token, istek)
- Kullanıcıya ait tüm anahtarlar ve harcamaları
- Erişilebilir model listesi
- Kullanıcı geneli veya yalnızca aktif anahtar kapsamı
- Otomatik yenileme, oturum açılışında başlatma, kurumsal/self-signed sertifika desteği
- Kimlik bilgileri macOS Anahtar Zinciri'nde saklanır

## Kurulum

```bash
brew tap mesutpiskin/litellm-bar https://github.com/mesutpiskin/litellm-bar
brew trust mesutpiskin/litellm-bar   # Homebrew 7+: üçüncü parti tap onayı
brew install --cask litellm-bar
```

Güncelleme: `brew upgrade --cask litellm-bar`

> Uygulama Apple Developer ID ile imzalanmadığı için (ad-hoc imza) cask kurulumda karantina bayrağını kaldırır.
> Zip'i elle indirdiyseniz: `xattr -dr com.apple.quarantine /Applications/LiteLLMBar.app`

## Kullanım

1. Menü çubuğundaki gösterge ikonuna tıklayın.
2. Sunucu adresini girin (ör. `https://litellm.sirket.com` — sonundaki `/ui` otomatik atılır).
3. **API Anahtarı** sekmesinde sanal anahtarınızı ya da **Kullanıcı Adı / Şifre** sekmesinde LiteLLM UI bilgilerinizi girin.

### Kullanılan LiteLLM uç noktaları

| Uç nokta | Amaç |
|---|---|
| `GET /key/info` | Anahtar harcaması, bütçe, limitler |
| `GET /user/info` | Kullanıcı harcaması ve anahtar listesi |
| `GET /user/daily/activity` | Günlük / model bazlı token & harcama |
| `GET /v1/models` | Erişilebilir modeller |
| `POST /login`, `POST /v2/login` | UI kullanıcı adı/şifre girişi (oturum anahtarı JWT'den alınır) |

Günlük kırılım için LiteLLM'in `/user/daily/activity` destekleyen bir sürümde olması gerekir; eski sürümlerde yalnızca toplam harcama gösterilir.

## Geliştirme

Xcode gerekmez, Command Line Tools yeterli:

```bash
swift build && swift run            # geliştirme
./scripts/build-app.sh 0.1.0        # universal build/LiteLLMBar.app
```

## Sürüm yayınlama

```bash
git tag v0.1.0 && git push origin v0.1.0
```

`Release` workflow'u universal `.app` üretir, GitHub Release'e zip olarak yükler ve `Casks/litellm-bar.rb` dosyasını yeni sürüm/sha256 ile günceller.
