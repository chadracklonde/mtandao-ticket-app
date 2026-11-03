# Identité visuelle de Mtandao Ticket

Choix du 3 novembre 2026 : **piste A, « Ticket et signal »**. Un ticket à encoches avec le signal wifi à l'intérieur ; le point ambre est le point d'émission du signal.

Planches de travail (3 pistes, couleurs, icônes, écrans) : <https://claude.ai/artifact/MhPJ1SLoLKUT86yuiEmUVG> (privé).

## Fichiers

| Fichier | Usage |
| --- | --- |
| `assets/brand/logo.svg`, `logo.png` | Logo seul, ticket bleu nuit (fond clair) |
| `assets/brand/icon.svg` | Icône à coins arrondis, pour affichage |
| `assets/brand/icon_square.png` | Icône 1024 px carrée, source du lanceur Android |
| `assets/brand/icon_foreground.png` | Premier plan de l'icône adaptative (ticket réduit pour la zone sûre) |

L'icône de l'app se génère avec `dart run flutter_launcher_icons`.

## Couleurs

| Nom | Valeur | Usage |
| --- | --- | --- |
| Encre | `#0E2A47` | Texte, barre d'application, fonds sombres |
| Bleu signal | `#0F5FD0` | Boutons, liens, onglet actif |
| Ciel | `#9CC3F5` | Accents doux sur fond sombre |
| Ambre | `#F5B301` | Le point du signal (logo uniquement) |
| Connecté | `#17784E` | Client actif, routeur joignable |
| Erreur | `#C63D2F` | Routeur injoignable, déconnexion |
| Fond | `#F4F7FB` | Écrans ; cartes `#FFFFFF`, traits `#DCE4EE` |

Tous les textes ont un contraste d'au moins 4,5 sur leur fond.

## Typographie

- Titres et chiffres : Sora (800 pour les titres, 600 pour les sous-titres).
- Textes et listes : Inter.
- Codes de tickets : police à chasse fixe.

Dans l'application, les polices Sora et Inter ne sont pas encore embarquées : elles seront ajoutées à la phase Socle (le thème actuel utilise la police Android par défaut).

## Règles du logo

- Zone libre autour du logo : au moins la hauteur d'une encoche.
- Taille minimale : 24 px de large.
- Sur fond sombre : ticket blanc, arcs bleu nuit, point bleu signal.
- Ne pas déformer, ne pas changer les couleurs des arcs, ne pas ajouter d'ombre.
