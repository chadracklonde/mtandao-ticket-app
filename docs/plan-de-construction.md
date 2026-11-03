# Plan de construction : phases et lots

Découpage des cinq phases du [cahier des charges](cahier-des-charges.md) en lots. Un lot est un morceau de travail qui se termine par quelque chose de testable. Aucune date n'est fixée.

| Phase | Lot | Contenu | Fonctions | Fini quand |
| --- | --- | --- | --- | --- |
| 1. Cadrage | — | Cahier des charges, logo, maquettes | — | Fait (3 novembre 2026) |
| 2. Socle | L1 | Compiler le prototype sur l'ordinateur de Chadrack, corriger les erreurs, produire un premier APK | — | `flutter analyze` et `flutter test` passent, l'APK s'installe |
| 2. Socle | L2 | Connexion au routeur : API, identification RouterOS 6 et 7, message clair si injoignable | F3 | Mauvais mot de passe refusé (T1), connexion réussie sur le vrai routeur |
| 2. Socle | L3 | Routeurs enregistrés : liste, ajout, modification, mot de passe dans le stockage sécurisé | F1, F2 | Le routeur est retrouvé après fermeture de l'application |
| 2. Socle | L4 | Profils : créer, modifier, supprimer, prix en FC, durée, script du routeur | F4, F5 | Profil visible dans WinBox avec son script (T2) |
| 2. Socle | L5 | Habillage : polices Sora et Inter, icône, thème de la charte | — | L'application a l'identité du logo A |
| 3. Tickets | L6 | Génération de 1 à 500 tickets, code unique ou utilisateur + mot de passe, reprise après coupure | F6 à F9 | 100 tickets en moins de 60 s, sans doublon (T3, T4) |
| 3. Tickets | L7 | PDF A4 en 3 colonnes avec QR code, partage et impression | F10, F11 | Le QR ouvre la page de connexion avec le bon ticket (T5) |
| 3. Tickets | L8 | Lots : retrouver, réimprimer, supprimer les tickets non utilisés | F12, F13 | Un lot ancien se réimprime |
| 3. Tickets | L9 | Expiration en jours calendaires depuis la première connexion | F19 | Un ticket de 24 h s'arrête 24 h après sa première connexion |
| 3. Tickets | Contrôle | Première vente comptée sur le vrai routeur | — | Une vente apparaît dans `/system script` (T7) |
| 4. Suivi | L10 | Utilisateurs actifs et déconnexion d'un client | F14, F15 | Le client connecté apparaît, puis est coupé (T6) |
| 4. Suivi | L11 | Rapports de ventes : jour, mois, période choisie, détail | F16, F17 | Totaux identiques aux tickets vendus (T8) |
| 5. Essais | L12 | Essais sur le vrai routeur : tous les tests T1 à T8, RouterOS 6 et 7 si possible | — | Tous les tests passent |
| 5. Essais | L13 | APK de test confié à l'usage réel, corrections | — | Une semaine d'usage sans erreur bloquante |
| 5. Essais | Contrôle | Mise en service | — | Ventes exactes |

Ordre conseillé : L1 d'abord, car rien d'autre n'avance sans une application qui compile. Les lots d'une même phase peuvent se faire dans le désordre, sauf L2 qui précède L3 et L4.

Hors V1 (candidats V2) : export des ventes (F18), sauvegarde des réglages. VPN intégré : V3.
