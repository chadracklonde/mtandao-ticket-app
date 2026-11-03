# Plan de construction : phases et lots

Découpage des cinq phases du [cahier des charges](cahier-des-charges.md) en lots. Un lot est un morceau de travail qui se termine par quelque chose de testable. Aucune date n'est fixée.

Méthode de travail depuis le 3 novembre 2026 : chaque lot est écrit, compilé et testé sur GitHub (analyse du code et tests automatiques à chaque envoi), puis on passe au suivant sans attendre. Chadrack n'intervient qu'au lot L13, pour l'essai en usage réel. Un **faux routeur** (`test/support/fake_router.dart`) répond comme un MikroTik pour tester la connexion, les profils, les tickets, les actifs et les ventes. Il n'exécute pas les scripts du routeur : ceux-ci ne sont validés que sur un vrai routeur, au lot L13.

| Phase | Lot | Contenu | Fonctions | Fini quand | État |
| --- | --- | --- | --- | --- | --- |
| 1. Cadrage | — | Cahier des charges, logo, maquettes | — | Fait (3 novembre 2026) | Fait |
| 2. Socle | L1 | Compiler le prototype, corriger les erreurs, produire un APK | — | `flutter analyze` et `flutter test` passent, l'APK se compile | Fait |
| 2. Socle | L2 | Connexion au routeur : API, identification RouterOS 6 et 7, message clair si injoignable | F3 | Mauvais mot de passe refusé (T1), identification simple et par défi MD5 | Fait (faux routeur) |
| 2. Socle | L3 | Routeurs enregistrés : liste, ajout, modification, mot de passe sécurisé, bouton « Tester la connexion » | F1, F2 | Le routeur est retrouvé après fermeture de l'application | Fait |
| 2. Socle | L4 | Profils : créer, modifier, supprimer, prix en FC, durée, validité, script du routeur | F4, F5 | Profil relu avec son prix, sa durée et sa validité (T2) | Fait (faux routeur) |
| 2. Socle | L5 | Habillage : polices Sora et Inter, interface en français, thème de la charte | — | L'application a l'identité du logo A | Fait |
| 3. Tickets | L6 | Génération de 1 à 500 tickets, code unique ou utilisateur + mot de passe, reprise après coupure | F6 à F9 | 100 tickets sans doublon (T3), arrêt en route expliqué (T4) | Fait (faux routeur) |
| 3. Tickets | L7 | PDF A4 en 3 colonnes avec QR code, partage et impression | F10, F11 | PDF de 100 tickets généré ; QR scanné à L13 (T5) | Fait (PDF) ; QR à L13 |
| 3. Tickets | L8 | Lots : retrouver, réimprimer, supprimer les tickets non utilisés | F12, F13 | Lots regroupés, tickets utilisés exclus | Fait |
| 3. Tickets | L9 | Expiration en jours calendaires depuis la première connexion | F19 | Script de forme correcte ; test T9 sur le vrai routeur à L13 | Écrit ; à valider à L13 |
| 3. Tickets | Contrôle | Première vente comptée sur le vrai routeur | — | Une vente apparaît dans `/system script` (T7) | À L13 |
| 4. Suivi | L10 | Utilisateurs actifs et déconnexion d'un client | F14, F15 | Le client apparaît, puis est coupé (T6) | Fait (faux routeur) |
| 4. Suivi | L11 | Rapports de ventes : jour, mois, période choisie, détail, totaux par profil | F16, F17 | Bornes de période et totaux testés (T8) | Fait |
| 5. Essais | L12 | Tests automatiques T1 à T9 sur faux routeur, APK de test sur GitHub | — | Tous les tests passent ; APK téléchargeable | Fait |
| 5. Essais | L13 | **Essai en usage réel (Chadrack)** : routeur réel, RouterOS 6 ou 7, QR, vente, expiration, accès à distance | — | Une semaine d'usage sans erreur bloquante | Premier essai réussi (3 nov. 2026) ; usage suivi en cours |
| 5. Essais | Contrôle | Mise en service | — | Ventes exactes | Après L13 |

## Phase 6. Compléments (3 nov. 2026)

| Lot | Contenu | État |
|---|---|---|
| L14 | Utilisateurs : liste complète, recherche, filtres (neufs, utilisés, épuisés, désactivés), détail de consommation, prolonger, désactiver, remise à zéro, supprimer | Fait (faux routeur) |
| L15 | Ventes : effacer / annuler, histogramme (par heure ou par jour), comparaison avec la période précédente | Fait (faux routeur) |
| L16 | Mise en page du ticket : A4 en 2, 3 ou 4 colonnes, rouleau 58 ou 80 mm, logo, titre, texte de bas de ticket, QR facultatif, aperçu | Fait (PDF) ; impression sur rouleau à essayer |
| L17 | Surveillance : processeur, mémoire, trafic en direct, journal, appareils DHCP | Fait (faux routeur) |
| L18 | Sauvegarde : profils (fichier JSON) et sauvegarde du routeur (.backup + .rsc) | Fait (faux routeur) |
| L19 | Verrouillage par code, vérification du certificat SSL, alerte de stock bas | Fait |
| L20 | Compilation Android, Windows et macOS | En cours |

Limite de temps (démarre à la première connexion), limite de données, vitesse du profil, export des ventes en PDF et Excel, versions Windows et macOS : faits (voir le journal des versions).

Non faits, décidés : langues (français seulement), rôle vendeur et mode vente, impression Bluetooth directe sur imprimante thermique (par le système d'impression uniquement), alertes poussées hors de l'application, empreinte digitale. VPN intégré : V3. Version iPhone et Play Store : plus tard.
