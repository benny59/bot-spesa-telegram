# Release Android privata

L'app usa una chiave privata stabile: gli APK futuri potranno aggiornare quelli
precedenti senza disinstallare l'app e senza passare da uno store.

## Prima configurazione

Eseguire una sola volta:

```bash
scripts/init_android_signing.sh
```

Salvare in un backup sicuro entrambi i file indicati dal comando. La perdita
della chiave impedisce di aggiornare le installazioni esistenti.

## Creare una release

Scegliere la nuova versione e incrementare il `versionCode`:

```bash
scripts/bump_android_version.sh 1.2.0
```

Creare quindi l'APK firmato:

```bash
scripts/build_android_release.sh
```

Il risultato si trova in `apk/releases/BotSpesa-v1.2.0.apk`. Il file APK puo
essere condiviso direttamente via WhatsApp. Android lo riconoscera come
aggiornamento se il pacchetto installato e firmato con la stessa chiave e ha un
`versionCode` inferiore.

## Prima installazione firmata

Le build debug precedenti hanno una firma differente. Sul telefono di test e
quindi necessario disinstallare una sola volta la vecchia build debug, installare
la prima release firmata e ripetere il collegamento con `/collegaapp`. Da quel
momento le release successive si installeranno come normali aggiornamenti.
