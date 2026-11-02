# Mtandao Ticket

Application Android qui pilote le hotspot MikroTik d'une wifi zone depuis un téléphone :
créer et imprimer des tickets, voir les connectés, suivre les ventes. Elle reprend l'esprit
de Mikhmon, sans serveur PHP ni WinBox.

**État du projet : phase de cadrage.** Le cahier des charges est rédigé et attend validation.
Aucun code n'est encore publié dans ce dépôt.

## Documents

- [Cahier des charges](docs/cahier-des-charges.md) : contexte, périmètre, besoins, architecture, plan, tests, risques et questions ouvertes.

## Aperçu de la V1 (proposition)

Routeurs enregistrés · profils · génération de tickets · PDF avec QR code · lots · utilisateurs actifs · rapport de ventes.

## Choix techniques envisagés

Flutter (Android), protocole API RouterOS (port 8728 ou 8729 en SSL), accès à distance par le VPN « Back to Home » de MikroTik.
