# Module 07 — Exercices

Fichiers fournis : `labs/m07/` (récepteur webhook, configuration des notifications, Application abonnée, Prometheus minimal). Contexte CLI administrateur : `argocd context localhost:8443`.

## Lab 07.1 ⭐ — Préparer et parcourir les outils de diagnostic (guidé)
**Durée** : 15 min · **Objectif** : rendre les pannes visibles vite et connaître les commandes de diagnostic
**Contexte** : avant d'ouvrir `flotte-web` à de nouveaux clients, l'équipe ops veut des pannes détectées en une minute.
**Prérequis** : état final du M06

### Étapes
1. Ajouter `progressDeadlineSeconds: 60` au Deployment (sous `replicas`), committer, pousser.
   ```bash
   cd <FLOTTE_CONFIG>
   sed -i -E 's/^(  replicas: [0-9]+)$/\1\n  progressDeadlineSeconds: 60/' apps/flotte-web/deployment.yaml
   grep -A1 '^  replicas' apps/flotte-web/deployment.yaml
   git commit -am "feat: echeance de deploiement 60 s" && git push
   ```
   Résultat attendu :
   ```
     replicas: 3
     progressDeadlineSeconds: 60
   ```
2. Parcourir les commandes de diagnostic sur l'application saine.
   ```bash
   argocd app get flotte-web-dev --refresh
   argocd app resources flotte-web-dev
   argocd app logs flotte-web-dev --kind Deployment --name flotte-web --tail 2
   kubectl get events -n flotte-dev --sort-by=.lastTimestamp | tail -5
   ```
   Résultat attendu (`app resources`) :
   ```
   GROUP  KIND        NAMESPACE   NAME                 ORPHANED
          ConfigMap   flotte-dev  flotte-web-config    No
          Service     flotte-dev  flotte-web           No
   apps   Deployment  flotte-dev  flotte-web           No
   batch  Job         flotte-dev  flotte-db-migration  No
   batch  Job         flotte-dev  flotte-smoke-test    No
   ```
3. Dans l'UI : cliquer sur le Deployment puis sur un pod ; parcourir *Summary*, *Events*, *Logs*.

### Critères de réussite
- [ ] `progressDeadlineSeconds: 60` dans Git et dans le cluster (`kubectl get deploy flotte-web -n flotte-dev -o yaml`)
- [ ] Journaux des pods lus par la CLI ArgoCD et par l'UI

---

## Exercice 07.2 ⭐⭐ — Pannes injectées en binôme (semi-autonome)
**Durée** : 25 min · **Objectif** : diagnostiquer une panne sans en connaître la cause
**Contexte** : trois incidents réels de l'historique d'*Hexa Mobilité* sont rejoués.

**Énoncé** : chaque stagiaire injecte, dans SON dépôt `flotte-config`, UNE des pannes ci-dessous choisie au hasard, sans dire laquelle ; le voisin la diagnostique depuis le poste du premier, uniquement avec ArgoCD, `kubectl get events` et les journaux. Puis inversion des rôles.

| Panne | Modification à pousser |
|---|---|
| A | Image `podinfo:6.99.0` (tag inexistant) |
| B | `containers:` renommé `containerz:` dans le Deployment |
| C | `readinessProbe` sur le chemin `/pret` (inexistant) |

Pour chaque diagnostic, relever : statuts Sync / Health, ressource en cause, message exact, cause, correction proposée. Réparer par `git revert` puis vérifier le retour à `Synced` / `Healthy`.

**Indices** :
- Opération bloquée : `argocd app terminate-op flotte-web-dev` avant le revert
- Message d'opération : `argocd app get flotte-web-dev -o json` (champ `status.operationState.message`)

**Critères de réussite** :
- [ ] Fiche de diagnostic complète (5 rubriques) pour la panne reçue
- [ ] Retour à `Synced` / `Healthy` après revert
- [ ] Explication de la différence de statut Sync entre les pannes A et B

---

## Lab 07.3 ⭐ — Notification webhook (guidé)
**Durée** : 20 min · **Objectif** : recevoir une alerte à chaque déploiement et à chaque dégradation
**Contexte** : l'équipe ops veut un message automatique dans son outil d'alerte ; un récepteur webhook simule cet outil.
**Prérequis** : Lab 07.1

### Étapes
1. Déployer le récepteur (namespace `flotte-ops`).
   ```bash
   kubectl create namespace flotte-ops
   kubectl apply -f <FORMATION>/labs/m07/webhook-receiver.yaml
   kubectl rollout status deploy/alertes-receiver -n flotte-ops
   ```
   Résultat attendu : `deployment "alertes-receiver" successfully rolled out`.
2. Lire puis appliquer la configuration des notifications (service, template, deux triggers).
   ```bash
   cat <FORMATION>/labs/m07/argocd-notifications-cm-patch.yaml
   kubectl patch cm argocd-notifications-cm -n argocd --type merge \
     --patch-file <FORMATION>/labs/m07/argocd-notifications-cm-patch.yaml
   ```
3. Abonner l'Application : reprendre le modèle `labs/m07/flotte-web-dev-notif.yaml` (2 annotations), renseigner `repoURL`, committer, pousser, appliquer.
   ```bash
   sed "s|<GITLAB_USER>|$GITLAB_USER|" <FORMATION>/labs/m07/flotte-web-dev-notif.yaml > argocd/flotte-web-dev.yaml
   git commit -am "feat: notifications flotte-alertes" && git push
   kubectl apply -f argocd/flotte-web-dev.yaml
   ```
4. Déclencher un déploiement (par exemple 2 réplicas), puis lire le récepteur.
   ```bash
   sed -i 's/replicas: 3$/replicas: 2/' apps/flotte-web/deployment.yaml
   git commit -am "feat: 2 replicas" && git push
   argocd app get flotte-web-dev --refresh > /dev/null && argocd app wait flotte-web-dev --sync --health
   kubectl logs -n flotte-ops deploy/alertes-receiver | grep -E '"(application|sync|health)"'
   ```
   Résultat attendu :
   ```
           "application": "flotte-web-dev",
           "sync": "Synced",
           "health": "Healthy",
   ```
5. Contrôler l'envoi côté ArgoCD.
   ```bash
   kubectl logs -n argocd deploy/argocd-notifications-controller --tail 20 | grep "Sending notification"
   ```
   Résultat attendu : `Sending notification about condition 'flotte-deployed.[0].<ID>' to '{flotte-alertes }'`.

### Critères de réussite
- [ ] Notification `flotte-deployed` reçue avec la révision déployée
- [ ] Abonnement présent dans le fichier `argocd/flotte-web-dev.yaml` de Git

---

## Exercice 07.4 ⭐⭐ — Lire les métriques (semi-autonome)
**Durée** : 10 min · **Objectif** : relier l'état d'une application aux métriques exposées
**Contexte** : l'équipe ops prépare l'intégration d'ArgoCD dans sa supervision Prometheus.

**Énoncé** :
- Exposer temporairement le service `argocd-metrics` et afficher la ligne `argocd_app_info` de `flotte-web-dev`.
- Relever les labels utiles à une alerte.
- Afficher le nombre de synchronisations réussies et en échec de `flotte-web-dev`.
- Expliquer pourquoi une requête trouvée dans un tutoriel sur `argocd_app_health_status` ne renvoie rien.

**Indices** : `kubectl port-forward -n argocd svc/argocd-metrics 8082:8082`, puis `curl -s localhost:8082/metrics`.

**Critères de réussite** :
- [ ] Ligne `argocd_app_info` portant le label `name="flotte-web-dev"` affichée et labels `health_status`, `sync_status` identifiés
- [ ] Compteurs `argocd_app_sync_total` par phase relevés
- [ ] Suppression de la métrique en 3.0 expliquée

---

## Défi 07.5 ⭐⭐⭐ — Prometheus et requêtes d'alerte (autonome)
**Durée** : 15 min · **Objectif** : collecter les métriques d'ArgoCD et formuler des alertes
**Contexte** : avant l'arrivée d'une vraie pile de supervision, l'équipe veut valider ses requêtes.

**Énoncé** :
- Déployer `labs/m07/prometheus-minimal.yaml` et vérifier que les 3 cibles ArgoCD sont `up`.
- Écrire et tester dans l'interface Prometheus : applications `Degraded`, applications `OutOfSync`, nombre d'échecs de synchronisation sur la dernière heure par application.
- Provoquer la panne A de l'exercice 07.2 et observer l'évolution des requêtes ; réparer.
- Proposer une règle d'alerte (`expr`, `for`, `labels`) pour « application dégradée depuis 5 minutes ».

**Critères de réussite** :
- [ ] Page *Status* → *Targets* : 3 cibles `UP`
- [ ] 3 requêtes testées, dont une qui change pendant la panne
- [ ] Règle d'alerte cohérente (durée, sévérité)

---

## Défi 07.6 ⭐⭐⭐ — Santé d'une ressource personnalisée en Lua (autonome)
**Durée** : 25 min · **Objectif** : apprendre à ArgoCD à évaluer la santé d'un type de ressource qu'il ne connaît pas
**Contexte** : l'équipe logistique d'*Hexa Mobilité* a créé une CRD `Livraison` (groupe `hexa-mobilite.io`) ; un opérateur renseigne `status.phase` (`EnAttente`, `EnCours`, `Livree`, `Echec`). Dans ArgoCD, ces objets n'ont aucune santé : une tournée en échec passe inaperçue.

**Énoncé** :
- Installer la CRD fournie (corrigé, ou à écrire : `spec.vehicule`, `spec.destination`, `status.phase`, `status.message`, sous-ressource `status`).
- Déployer par ArgoCD une `Livraison` `tournee-lyon-01` (Application `livraisons`, namespace `flotte-livraison`) : constater l'absence de santé.
- Écrire la règle de santé Lua : pas de statut → `Progressing` ; `Livree` → `Healthy` ; `Echec` → `Degraded` ; `EnAttente` → `Suspended` ; sinon `Progressing` ; message = `status.message`.
- La tester **hors cluster** sur un fichier YAML, puis l'appliquer.
- Simuler l'opérateur (modifier le statut) pour chaque phase et relever la santé de l'Application.
- Nettoyer : Application, CRD et règle supprimées.

**Indices** : clé `resource.customizations.health.<GROUPE>_<KIND>` de `argocd-cm` ; `argocd admin settings resource-overrides health <FICHIER> --argocd-cm-path <FICHIER>` ; `kubectl patch ... --subresource=status`.

**Critères de réussite** :
- [ ] Test hors cluster : `STATUS: Degraded`, `MESSAGE: <message>` pour une phase `Echec`
- [ ] Santé de l'Application : `Progressing` → `Degraded` → `Healthy` selon la phase
- [ ] Explication : pourquoi la santé d'une seule ressource change celle de toute l'Application

---

## Défi 07.7 ⭐⭐⭐ — Quand ArgoCD lui-même tombe en panne (autonome)
**Durée** : 20 min · **Objectif** : reconnaître la panne de chaque composant d'ArgoCD à ses symptômes, et savoir ce qui continue de fonctionner
**Contexte** : l'astreinte d'*Hexa Mobilité* reçoit « ArgoCD ne déploie plus ». Avant de chercher dans les applications, il faut savoir si l'outil lui-même est sain.

**Énoncé** (sur son propre cluster, une panne à la fois, réparer avant la suivante) :
- Panne 1 : `argocd-repo-server` arrêté (`--replicas=0`). Rafraîchir une application ; relever statut et condition.
- Panne 2 : `argocd-application-controller` arrêté. Pousser un commit, rafraîchir, synchroniser (prévoir `timeout 20`) ; relever ce qui se passe. Redémarrer et observer.
- Panne 3 : `argocd-redis` arrêté. Tester `argocd app list` et `argocd app get` ; chercher la trace dans les journaux.
- Remplir le tableau : composant, symptôme visible, preuve dans les journaux, impact sur les applications déjà déployées.

**Indices** : `kubectl scale deploy|sts ... -n argocd --replicas=0|1` ; `.status.reconciledAt` et `.operation` de l'Application ; `kubectl logs ... --since=1m`.

**Critères de réussite** :
- [ ] Panne 1 : `ComparisonError ... failed to generate manifest ... Unavailable` identifiée
- [ ] Panne 2 : statut figé (`reconciledAt` ancien), commande bloquée, opération en attente exécutée au redémarrage
- [ ] Panne 3 : API utilisable, erreurs `redis: connection pool` dans le contrôleur
- [ ] Tableau complet ; tous les composants revenus à 1 réplica

---

## Bonus 🚀
Ajouter un trigger `flotte-sync-failed` (phase d'opération `Error` ou `Failed`) envoyé au même webhook, l'abonner, puis le déclencher avec la panne B. Mesurer le délai entre le push et la notification, et l'expliquer.
