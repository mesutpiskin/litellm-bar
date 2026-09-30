# LiteLLM Usage (VS Code)

LiteLLM proxy'nizdeki **model, token ve harcama** kullanımınızı VS Code durum çubuğunda ve bir panelde gösterir. Admin hesabı gerekmez; kendi sanal anahtarınız (sk-…) veya LiteLLM UI kullanıcı adı/şifreniz yeterli.

## Kurulum

[Releases](https://github.com/mesutpiskin/litellm-bar/releases) sayfasından `litellm-usage-*.vsix` dosyasını indirin:

```bash
code --install-extension litellm-usage-0.1.0.vsix
```

## Kullanım

- Durum çubuğunda (sağ alt) **LiteLLM: Giriş yap**'a tıklayın veya Komut Paleti'nden `LiteLLM: Giriş Yap`.
- Giriş sonrası durum çubuğu bugünkü harcamayı gösterir; tıklayınca kullanım paneli açılır.
- Panel: bütçe, bugün/7/30/90 gün harcama & token, günlük grafik, model bazlı tablo, anahtarlarınız, erişilebilir modeller.

Kimlik bilgileri VS Code SecretStorage'da (macOS Anahtar Zinciri) saklanır.

## Ayarlar

| Ayar | Açıklama |
|---|---|
| `litellm.baseUrl` | LiteLLM proxy adresi |
| `litellm.refreshMinutes` | Yenileme aralığı (dk) |
| `litellm.statusBar` | `todaySpend`, `todayTokens`, `totalSpend`, `icon` |
| `litellm.allowInsecureTLS` | Self-signed / kurumsal sertifikalara güven |
