# Installer VIGIROAD sur iPhone

Chaque release contient `vigiroad-<version>-ios-non-signe.ipa`, compilée par la CI à partir du
même code que l'APK Android (iOS 16 ou plus).

## Pourquoi « non signée »

Apple n'autorise l'installation d'une application que si elle est **signée** par un compte
développeur Apple. Le projet n'a pas encore de compte Apple Developer : l'IPA est donc fournie sans
signature, et c'est l'outil d'installation qui la signe avec **votre identifiant Apple**.

## Installation avec Sideloadly (Windows ou Mac, gratuit)

1. Installer **Sideloadly** (sideloadly.io) et, sous Windows, **iTunes** et **iCloud** (versions
   du site d'Apple).
2. Brancher l'iPhone en USB, le déverrouiller, accepter « Faire confiance à cet ordinateur ».
3. Glisser `vigiroad-…-ios-non-signe.ipa` dans Sideloadly, saisir son identifiant Apple, cliquer
   **Start**.
4. Sur l'iPhone : **Réglages → Général → VPN et gestion de l'appareil** → faire confiance au
   profil de son identifiant Apple.
5. iOS 16 et plus : **Réglages → Confidentialité et sécurité → Mode développeur** → activer, puis
   redémarrer l'iPhone.

AltStore (altstore.io) fonctionne de la même façon.

## Limites d'un identifiant Apple gratuit

- L'application **expire au bout de 7 jours** : la réinstaller avec Sideloadly (les données sont
  conservées si l'on réinstalle par-dessus) ; AltStore peut le faire automatiquement.
- Trois applications ainsi installées au maximum par appareil.

## Distribution sans ces limites

Un compte **Apple Developer Program** (99 €/an, au nom de VIGIROAD INC) permet de signer l'IPA en
CI et de la distribuer par **TestFlight** ou l'App Store, sans expiration hebdomadaire. Il faudra
alors fournir à la CI, en secrets GitHub : le certificat de distribution (.p12 et son mot de passe),
le profil de provisionnement et une clé API App Store Connect.
