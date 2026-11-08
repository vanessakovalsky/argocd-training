# Module 06 — Exercices

Contexte CLI administrateur : `argocd context localhost:8443`. Dépôt `flotte-config` cloné dans `<FLOTTE_CONFIG>`.

## Lab 06.1 ⭐ — Livrer une version fautive et lire l'historique (guidé)
**Durée** : 15 min · **Objectif** : relier chaque déploiement à un commit et comparer deux révisions
**Contexte** : la version `6.17.0` de `flotte-web` est livrée en `dev` ; le message affiché révèle une anomalie.
**Prérequis** : état final du M05 (auto-sync, self-heal, hooks)

### Étapes
1. Livrer la version `6.17.0` (image ET configuration dans le même commit).
   ```bash
   cd <FLOTTE_CONFIG>
   sed -i -E 's#(podinfo:)[0-9.]+#\16.17.0#' apps/flotte-web/deployment.yaml
   sed -i 's/suivi de flotte"/v6.17 (anomalie)"/' apps/flotte-web/configmap.yaml
   git commit -am "feat: flotte-web 6.17.0" && git push
   argocd app get flotte-web-dev --refresh > /dev/null
   argocd app wait flotte-web-dev --sync --health
   ```
   Résultat attendu : `Synced` / `Healthy`, hooks de migration et de smoke test `Succeeded`.
2. Vérifier l'application.
   ```bash
   kubectl get deploy flotte-web -n flotte-dev -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
   kubectl get cm flotte-web-config -n flotte-dev -o jsonpath='{.data.PODINFO_UI_MESSAGE}{"\n"}'
   ```
   Résultat attendu :
   ```
   ghcr.io/stefanprodan/podinfo:6.17.0
   Hexa Mobilite - v6.17 (anomalie)
   ```
3. Lire l'historique et noter l'ID de la version précédente (`6.16.0`).
   ```bash
   argocd app history flotte-web-dev
   git log --oneline -3
   ```
4. Comparer le cluster actuel à la révision précédente.
   ```bash
   argocd app diff flotte-web-dev --revision <SHA_PRECEDENT>
   ```
   Résultat attendu : lignes `image` (`6.17.0` contre `6.16.0`) et `PODINFO_UI_MESSAGE`.
5. Dans l'UI : *History and rollback* ; repérer les mêmes révisions.

### Critères de réussite
- [ ] Correspondance établie entre chaque ID d'historique et un commit de `git log`
- [ ] Diff entre la version actuelle et la précédente lu et expliqué

---

## Lab 06.2 ⭐ — Rollback GitOps par `git revert` (guidé)
**Durée** : 15 min · **Objectif** : revenir à `6.16.0` sans quitter le modèle GitOps
**Contexte** : l'équipe dev décide d'annuler la livraison `6.17.0`.
**Prérequis** : Lab 06.1

### Étapes
1. Tenter d'abord le rollback ArgoCD, pour constater le refus.
   ```bash
   argocd app rollback flotte-web-dev <ID_PRECEDENT>
   ```
   Résultat attendu :
   ```
   {"level":"fatal","msg":"rpc error: code = FailedPrecondition desc = rollback cannot be initiated when auto-sync is enabled","time":"<DATE>"}
   ```
2. Annuler le commit fautif.
   ```bash
   git revert --no-edit HEAD
   git log --oneline -2
   git push
   ```
   Résultat attendu (`git log`) :
   ```
   <SHA> Revert "feat: flotte-web 6.17.0"
   <SHA> feat: flotte-web 6.17.0
   ```
3. Laisser la synchronisation automatique agir, puis vérifier.
   ```bash
   argocd app get flotte-web-dev --refresh > /dev/null
   argocd app wait flotte-web-dev --sync --health
   kubectl get deploy flotte-web -n flotte-dev -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
   argocd app history flotte-web-dev
   ```
   Résultat attendu : image `6.16.0`, nouvelle entrée d'historique avec le commit de revert.

### Critères de réussite
- [ ] Image `6.16.0` et message `Hexa Mobilite - suivi de flotte` restaurés
- [ ] Revert visible dans `git log` ET dans l'historique ArgoCD

---

## Exercice 06.3 ⭐⭐ — Rollback d'urgence (semi-autonome)
**Durée** : 20 min · **Objectif** : appliquer la procédure d'urgence complète sans laisser Git et le cluster divergents
**Contexte** : la `6.17.0` est relivrée par erreur ; GitLab est lent à répondre, l'équipe doit rétablir le service AVANT de corriger Git.

**Énoncé** :
- Relivrer la `6.17.0` (`git revert` du commit de revert, push, synchronisation).
- Rétablir la `6.16.0` en moins de 2 minutes sans commit Git : suspendre l'automatisme, rollback vers l'ID de la dernière version saine.
- Relever l'état de l'application (statut de synchronisation, politique) et l'expliquer.
- Réaligner Git, puis réactiver l'automatisme dans le bon ordre ; vérifier l'état final.

**Indices** :
- `automated.enabled: false` dans `argocd/flotte-web-dev.yaml` (puis `kubectl apply`), ou `kubectl patch app` pendant l'urgence
- `argocd app rollback <APP> <ID>`

**Critères de réussite** :
- [ ] `6.16.0` restaurée par rollback ArgoCD, application `OutOfSync` et `Manual` expliquée
- [ ] Git corrigé AVANT réactivation, état final `Synced`, `Automated`, image `6.16.0`
- [ ] Fichier `argocd/flotte-web-dev.yaml` de nouveau en `enabled: true`

---

## Défi 06.4 ⭐⭐⭐ — Réserver le rollback aux ops (autonome)
**Durée** : 15 min · **Objectif** : séparer le droit de synchroniser du droit de revenir en arrière
**Contexte** : la direction technique d'*Hexa Mobilité* veut que seuls les ops (`ops-bob`) puissent effectuer un rollback d'urgence ; les devs synchronisent, mais passent par `git revert`.

**Énoncé** :
- Montrer qu'avec la configuration actuelle, `dev-alice` peut effectuer un rollback (vérification `can-i`).
- Activer le contrôle RBAC distinct du rollback, puis montrer que `dev-alice` est refusée et `ops-bob` autorisé.
- Réduire l'historique conservé de `flotte-web-dev` à 5 entrées et vérifier quand la limite prend effet.

**Critères de réussite** :
- [ ] `can-i rollback` de `dev-alice` : `yes` avant, `no` après
- [ ] Tentative réelle de `dev-alice` refusée (`permission denied`), `ops-bob` autorisé
- [ ] Historique limité à 5 entrées après la synchronisation suivante

---

## Bonus 🚀
Modifier uniquement `PODINFO_UI_MESSAGE` dans `configmap.yaml` (sans changer l'image), pousser, puis comparer le message de la ConfigMap et celui servi par l'application (`curl` via `port-forward`). Expliquer l'écart et proposer deux solutions.
