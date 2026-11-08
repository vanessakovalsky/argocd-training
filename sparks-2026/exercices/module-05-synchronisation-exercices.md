# Module 05 — Exercices

Fichiers fournis : `labs/m05/` (Application en synchronisation automatique, hooks). Contexte CLI administrateur : `argocd context localhost:8443`.

## Lab 05.1 ⭐ — Passer en synchronisation automatique (guidé)
**Durée** : 20 min · **Objectif** : livrer une modification de Git sans action manuelle
**Contexte** : l'équipe dev d'*Hexa Mobilité* veut que tout commit sur `main` soit déployé en `dev`.
**Prérequis** : état final du M04

### Étapes
1. Ajouter la politique automatique (sans prune ni self-heal) dans `argocd/flotte-web-dev.yaml` du dépôt `flotte-config`.
   ```yaml
   spec:
     syncPolicy:
       automated:
         enabled: true
       syncOptions:
         - CreateNamespace=true
   ```
2. Committer, pousser, puis appliquer.
   ```bash
   git commit -am "feat: synchronisation automatique dev" && git push
   kubectl apply -f argocd/flotte-web-dev.yaml
   argocd app get flotte-web-dev | grep "Sync Policy"
   ```
   Résultat attendu :
   ```
   Sync Policy:        Automated
   ```
3. Passer à 3 réplicas dans `apps/flotte-web/deployment.yaml`, committer et pousser.
   ```bash
   sed -i 's/replicas: 2/replicas: 3/' apps/flotte-web/deployment.yaml
   git commit -am "feat: 3 replicas" && git push
   ```
4. Attendre la détection (3 min au plus) ou forcer le rafraîchissement, puis vérifier.
   ```bash
   argocd app get flotte-web-dev --refresh > /dev/null
   argocd app history flotte-web-dev
   kubectl get deploy flotte-web -n flotte-dev
   ```
   Résultat attendu : nouvelle ligne d'historique avec le dernier commit ; Deployment `3/3`.

### Critères de réussite
- [ ] Deployment à 3 réplicas sans `argocd app sync`
- [ ] Historique : une entrée par commit synchronisé

---

## Lab 05.2 ⭐ — Dérive et self-heal (guidé)
**Durée** : 15 min · **Objectif** : constater une dérive, puis la faire corriger automatiquement
**Contexte** : un ops a « dépanné » la prod en ajoutant des réplicas à la main ; personne ne l'a reporté dans Git.
**Prérequis** : Lab 05.1

### Étapes
1. Simuler la dérive.
   ```bash
   kubectl scale deploy flotte-web -n flotte-dev --replicas=5
   sleep 15
   argocd app get flotte-web-dev | grep -E "Sync Status|Deployment"
   argocd app diff flotte-web-dev
   ```
   Résultat attendu : `OutOfSync`, diff `replicas: 5` (cluster) contre `replicas: 3` (Git) ; 5 pods conservés.
2. Activer le self-heal dans `argocd/flotte-web-dev.yaml` (`selfHeal: true` sous `automated`), committer, pousser, appliquer.
   ```bash
   kubectl apply -f argocd/flotte-web-dev.yaml
   sleep 15
   kubectl get deploy flotte-web -n flotte-dev
   ```
   Résultat attendu : retour à `3/3`, application `Synced`.
3. Recommencer `kubectl scale --replicas=5` et chronométrer le retour à 3 réplicas.

### Critères de réussite
- [ ] Dérive visible dans `app diff` sans self-heal
- [ ] Retour à 3 réplicas en quelques secondes avec self-heal

---

## Exercice 05.3 ⭐⭐ — Supprimer ce qui a quitté Git (semi-autonome)
**Durée** : 15 min · **Objectif** : comprendre le prune et ses précautions
**Contexte** : une ConfigMap `flotte-web-legacy` n'est plus utilisée ; elle doit disparaître du cluster quand elle disparaît de Git.

**Énoncé** :
- Ajouter dans `apps/flotte-web/` une ConfigMap `flotte-web-legacy` (une clé `mode: "ancien"`), pousser, vérifier sa création.
- La retirer de Git, pousser, observer l'état de l'application et de la ConfigMap.
- Activer `prune: true` dans l'Application, observer le résultat (un rafraîchissement peut être nécessaire).
- Citer deux moyens de protéger une ressource contre le prune.

**Indices** : `argocd app get --refresh` ; annotation `argocd.argoproj.io/sync-options`.

**Critères de réussite** :
- [ ] Sans prune : ConfigMap présente, application `OutOfSync`
- [ ] Avec prune : ressource affichée `Pruned`, absente du cluster
- [ ] Deux protections citées

---

## Lab 05.4 ⭐⭐ — Hooks et sync waves (guidé puis semi-autonome)
**Durée** : 25 min · **Objectif** : ordonner une livraison : migration avant, test après
**Contexte** : la version suivante de `flotte-web` exigera une migration de schéma ; l'équipe veut aussi un test automatique après chaque déploiement.
**Prérequis** : Lab 05.2

### Étapes
1. Copier les deux hooks fournis et les lire.
   ```bash
   cp <FORMATION>/labs/m05/hook-*.yaml apps/flotte-web/
   grep -A2 'annotations' apps/flotte-web/hook-*.yaml
   ```
   Résultat attendu : `argocd.argoproj.io/hook: PreSync` pour la migration, `PostSync` pour le smoke test.
2. Placer la ConfigMap en vague -1 : ajouter dans `apps/flotte-web/configmap.yaml`, sous `metadata` :
   ```yaml
     annotations:
       argocd.argoproj.io/sync-wave: "-1"
   ```
3. Committer, pousser, rafraîchir, puis observer la synchronisation (UI : panneau *Sync status*).
   ```bash
   git add apps/ && git commit -m "feat: hooks migration et smoke test" && git push
   argocd app get flotte-web-dev --refresh > /dev/null
   argocd app wait flotte-web-dev --sync --health
   argocd app get flotte-web-dev
   ```
   Résultat attendu : Job `flotte-db-migration` (`PreSync`, `Succeeded`), ressources synchronisées, Job `flotte-smoke-test` (`PostSync`, `Succeeded`).
4. Lire les journaux des deux hooks.
   ```bash
   kubectl logs -n flotte-dev job/flotte-db-migration
   kubectl logs -n flotte-dev job/flotte-smoke-test
   ```
   Résultat attendu :
   ```
   Migration schema flotte v2
   OK
   {
     "status": "OK"
   }
   ```
5. (Semi-autonome) Expliquer pourquoi les deux Jobs sont toujours présents après la synchronisation, et quand ils seront supprimés.

### Critères de réussite
- [ ] Ordre observé : PreSync → vague -1 → vague 0 → PostSync
- [ ] Journaux des deux hooks lus
- [ ] Politique `BeforeHookCreation` expliquée

---

## Défi 05.5 ⭐⭐⭐ — Migration en échec et champ géré ailleurs (autonome)
**Durée** : 20 min · **Objectif** : vérifier qu'une migration ratée bloque la livraison, puis réparer ; protéger un champ géré par un autre contrôleur
**Contexte** : la version `6.16.0` arrive avec une migration défectueuse ; par ailleurs, un futur HPA gérera le nombre de réplicas.

**Énoncé** :
- Dans un même commit : image `podinfo:6.16.0` et migration qui se termine en erreur (`exit 1`). Observer : image du Deployment, état de l'opération, tentatives successives.
- Interrompre les tentatives, corriger la migration par un nouveau commit, vérifier que `6.16.0` est déployée et le smoke test réussi.
- Configurer l'Application pour que le nombre de réplicas ne soit ni signalé comme écart ni écrasé par une synchronisation ; le prouver avec `kubectl scale`.
- Retirer cette configuration en fin d'exercice (le M06 s'appuie sur le self-heal).

**Critères de réussite** :
- [ ] Image restée en `6.15.0` tant que la migration échoue
- [ ] `6.16.0` déployée après correction, historique à jour
- [ ] `kubectl scale --replicas=4` conservé, application `Synced`

---

## Bonus 🚀
Ajouter un hook `SyncFail` (Job qui affiche « Echec de synchronisation flotte-web ») et le déclencher avec une migration en échec. Puis suspendre l'automatisme (`automated.enabled: false`) et vérifier qu'un nouveau commit n'est plus déployé tant qu'il n'est pas réactivé.
