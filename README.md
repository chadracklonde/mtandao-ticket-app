# Mtandao Ticket

Application Android qui fonctionne comme Mikhmon : elle pilote le hotspot MikroTik d'une wifi zone
depuis un téléphone, sans serveur PHP ni WinBox. Elle parle directement à l'API RouterOS
(port 8728, ou 8729 en SSL).

**État du projet : phase Socle.** Le [cahier des charges](docs/cahier-des-charges.md) est validé
(3 novembre 2026). Le code ci-dessous est un prototype **jamais compilé ni testé sur un vrai routeur**.

## Fonctions de la V1

- **Routeurs** : plusieurs connexions enregistrées (mot de passe dans le stockage sécurisé Android).
- **Profils** : débit, appareils simultanés, prix en FC, durée de connexion.
- **Générer** des tickets (1 à 500) : préfixe, longueur, chiffres/lettres, code unique ou utilisateur + mot de passe.
- **PDF** : tickets A4 (3 colonnes) avec QR code, partage ou impression.
- **Lots** : retrouver, réimprimer ou supprimer les tickets non utilisés.
- **Actifs** : utilisateurs connectés, déconnexion d'un client.
- **Ventes** : rapport par mois et par jour, total encaissé.

Pas encore faits (prévus par le cahier des charges) : expiration en jours calendaires (F19) et rapport
sur une période choisie (F16/F17).

## Accès

- À distance : si « Back to Home » de MikroTik est installé et connecté sur le téléphone (routeur en RouterOS 7.11 ou plus).
- Sinon : uniquement connecté au wifi du routeur, comme Mikhmon.
- Toutes les versions de RouterOS (6 et 7) sont visées.

## Mise en route

Prérequis : Flutter récent (3.33 ou plus) et Android Studio / SDK Android.

```bash
cd mtandao-ticket-app
flutter create --org cd.xsoftdesign --project-name mtandao_ticket --platforms android .
```

Cette commande génère le dossier `android/` sans toucher à `lib/`, `pubspec.yaml` ni `test/`.
Ensuite, **ajoutez la permission Internet** dans `android/app/src/main/AndroidManifest.xml`,
juste avant la balise `<application` :

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

(Sans elle, l'application fonctionne en debug mais ne se connecte pas en release.)

`flutter_secure_storage` demande `minSdkVersion 23` : dans `android/app/build.gradle(.kts)`,
mettez `minSdk = 23` si ce n'est pas déjà le cas.

```bash
flutter pub get
dart run flutter_launcher_icons   # icône de l'app (logo A)
flutter analyze
flutter test
flutter run                 # téléphone branché en USB
flutter build apk --release # APK dans build/app/outputs/flutter-apk/
```

## Préparer le MikroTik

1. Activer l'API : `/ip service enable api` (ou `api-ssl` pour le port 8729).
2. Créer, de préférence, un utilisateur dédié (groupe `write`, sans `policy`/`sensitive` inutiles)
   plutôt que d'utiliser `admin`.
3. Si vous passez par le VPN « Back to Home », vérifiez que le service `api` accepte les
   connexions venant du réseau du VPN (`/ip service print`, colonne *address* vide ou incluant
   le sous-réseau du VPN), et utilisez comme adresse l'IP **locale** du routeur (ex. 192.168.88.1).
4. Ne laissez jamais l'API ouverte côté WAN.

## Comment les ventes sont comptées

Chaque profil créé par l'application contient un script **on-login**. À la **première**
connexion d'un ticket (commentaire `vc-…` ou `up-…`), le routeur :

1. écrit une ligne dans `/system script` (commentaire `mikhmon`) au format
   `date-|-heure-|-utilisateur-|-prix-|-ip-|-mac-|-durée-|-profil-|-commentaire` ;
2. renomme le commentaire du ticket en `used-…` pour qu'il ne soit pas recompté.

Le rapport lit ces lignes. Les profils créés **hors de l'application** (WinBox, autre Mikhmon)
n'ont pas ce script : leurs ventes ne sont pas comptées ici. Ouvrez-les dans l'onglet
*Profils* et enregistrez-les pour ajouter le script.

La durée d'un ticket est pour l'instant appliquée avec `limit-uptime` (temps de connexion cumulé,
mesuré par RouterOS). L'expiration en jours calendaires depuis la première connexion (F19) reste à
écrire.

## Structure

```
lib/routeros/api_client.dart     protocole API (encodage, lecture, login, reconnexion)
lib/services/mikhmon_service.dart  profils, tickets, actifs, ventes
lib/services/voucher_pdf.dart    PDF des tickets
lib/screens/                     écrans
test/                            tests du codec, des ventes et des profils
```
