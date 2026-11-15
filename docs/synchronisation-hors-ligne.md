# File locale de synchronisation

Le service `lib/services/sync_outbox.dart` fournit la première couche de synchronisation différée de Mtandao Ticket.

## Utilisation

- Obtenir une identité stable de l'installation avec `SyncIdentity.deviceId()`.
- Ajouter un événement avec `SyncOutbox.enqueue(...)` après une opération métier confirmée localement.
- Appeler `SyncOutbox.flush(...)` lorsqu'un utilisateur authentifié et un site Cloud actif sont disponibles.
- Utiliser `SyncCoordinator` pour déclencher la synchronisation au retour d'une connectivité et lors de contrôles périodiques (60 secondes par défaut). Le coordinateur reçoit les fournisseurs de site actif et de jeton ; il ne stocke aucun secret.
- Fournir l'URL racine de l'API et le jeton d'accès Supabase de l'utilisateur courant.
- Ne jamais supprimer manuellement les événements non acquittés.

## Contrat

Chaque événement contient :
- `id` : UUID v4 généré une seule fois et conservé durant toutes les tentatives ;
- `site_id` et `device_id` ;
- `event_type` et `schema_version` ;
- `occurred_at` en UTC ;
- `payload` métier sans secret ;
- `idempotency_key` facultative.

L'API Cloud reçoit les événements sur `POST /v1/sites/:siteId/sync/events`. Le client efface un événement uniquement après avoir vérifié que l'accusé du serveur contient tous les identifiants envoyés.

## Limites de cette étape

Le moteur local et le client HTTP sont implémentés, mais leur branchement aux ventes/tickets attend l'intégration de l'authentification Cloud et du choix du site actif dans Flutter. Le déclenchement automatique sur changement de connectivité, la reprise en arrière-plan et la résolution des conflits sont des tâches restantes du lot 1.
