# Module 11 — Corrections

Script d'état final du module (testé sur v3.6.1 + Sealed Secrets v0.41.2) — mêmes variables que le M04, CLI `kubeseal` requise :
```bash
FLOTTE_PUSH_URL=https://oauth2:<TOKEN>@gitlab.com/<GITLAB_USER>/flotte-config.git \
FLOTTE_REPO_URL=https://gitlab.com/<GITLAB_USER>/flotte-config.git \
  ./scripts/m11/catch-up/m11-final-state.sh
```
État obtenu : contrôleur Sealed Secrets installé ; `flotte-web-secrets` scellé pour `flotte-dev` (valeur de formation `hexa-dev-0001`) et référencé par le Rollout ; rôle de projet `ci-deployer`. Le scellement utilise la clé publique du cluster du stagiaire : un fichier scellé sur un autre cluster ne fonctionne pas.

## Lab 11.1 ⭐ — Sceller le premier secret
### Solution
Extrait de `sealed-secret.yaml` (testé) :
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: flotte-web-secrets
  namespace: flotte-dev
spec:
  encryptedData:
    FLOTTE_API_KEY: AgBZXuRzoWpbNHFbec5C6bpT/2oJN6yKqtlY5bUQhkkyF6baoXXJO0xfeXDrrpFyFIXX
  template:
    metadata:
      name: flotte-web-secrets
      namespace: flotte-dev
```
Overlay `dev` :
```yaml
resources:
- ../../base
- sealed-secret.yaml
```
Résultats (testés) :
```
bitnami.com  SealedSecret  flotte-dev  flotte-web-secrets  Synced  Healthy  sealedsecret.bitnami.com/flotte-web-secrets created
SealedSecret
flotte-web-85675c5597-r777v FLOTTE_API_KEY=hexa-dev-0001
```

### Pourquoi
- `kubeseal` récupère le certificat public du contrôleur (namespace `kube-system`, nom `sealed-secrets-controller`) et chiffre localement.
- Contrôleur installé hors ArgoCD (ressources de niveau cluster) : même logique qu'Argo Rollouts au M08.
- `optional: true` : la base reste commune ; seuls les environnements qui fournissent le Secret l'injectent.
- Variable lue au démarrage du conteneur : la promotion du canari crée les nouveaux pods qui la reçoivent.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| `kubeseal: cannot fetch certificate` | Contrôleur absent ou nom / namespace différents | `kubectl get deploy -n kube-system sealed-secrets-controller` ; options `--controller-name`, `--controller-namespace` |
| Pods `CreateContainerConfigError` : secret introuvable | `optional: true` oublié et SealedSecret absent de l'environnement | Ajouter `optional: true` ou sceller pour l'environnement |
| Variable vide dans un pod | Pod d'une version antérieure (canari non promu) | Promouvoir, vérifier le ReplicaSet du pod |
| Le fichier contient la valeur en clair | Commande `kubectl create secret` exécutée sans `kubeseal` | Supprimer le fichier, réécrire l'historique Git, changer la clé d'API |

## Exercice 11.2 ⭐⭐ — Portée et sauvegarde de la clé
### Solution
```bash
sed 's/namespace: flotte-dev/namespace: flotte-recette/g' \
  apps/flotte-web/overlays/dev/sealed-secret.yaml | kubectl apply -f -
kubectl get sealedsecret flotte-web-secrets -n flotte-recette \
  -o jsonpath='{.status.conditions[0].message}{"\n"}'
kubectl delete sealedsecret flotte-web-secrets -n flotte-recette
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key.yaml
```
Résultats (testés) :
```
no key could decrypt secret (FLOTTE_API_KEY)
Error from server (NotFound): secrets "flotte-web-secrets" not found
```
Fichier de sauvegarde : Secret(s) `sealed-secrets-key<suffixe>` avec `tls.crt` et `tls.key`.

Stockage : coffre de l'entreprise (ou support chiffré hors ligne), JAMAIS dans Git ni dans le seul cluster ; restauration : `kubectl apply -f sealed-secrets-key.yaml` dans le nouveau cluster AVANT le contrôleur (ou redémarrage du contrôleur ensuite).

Recette : `kubectl create secret ... -n flotte-recette ... | kubeseal --format yaml > apps/flotte-web/overlays/recette/sealed-secret.yaml`, ajout à `resources` de l'overlay.

### Pourquoi
- Portée *strict* : le nom et le namespace font partie des données chiffrées ; une copie dans un autre namespace est indéchiffrable (protection contre la réutilisation d'un secret dans un namespace moins protégé).
- Perte de la clé privée = tous les SealedSecrets du dépôt inutilisables ; il faudrait resceller chaque secret à partir des valeurs d'origine.

## Lab 11.3 ⭐ — Rôle de projet pour la CI
### Solution
Commandes de l'énoncé. Résultats (testés) :
```
Phase:              Succeeded
Message:            successfully synced (all tasks run)
{"level":"fatal","msg":"rpc error: code = PermissionDenied desc = permission denied: applications, delete, flotte/flotte-api-dev, sub: proj:flotte:ci-deployer, iat: <DATE>"}
```
Liste et révocation des jetons :
```bash
argocd proj role list-tokens flotte ci-deployer
argocd proj role delete-token flotte ci-deployer <ISSUED_AT_UNIX>
```
Version déclarative : `labs/m11/appproject-flotte-roles.yaml` (bloc `roles`).

### Pourquoi
- Sujet du jeton : `proj:flotte:ci-deployer` ; ses droits ne peuvent pas dépasser le projet.
- Jetons émis enregistrés dans `status.jwtTokensByRole` du projet (testé : retirer `jwtTokens` de la spécification ne révoque pas le jeton) ; révocation explicite par `delete-token`.
- Préférable au compte global `ci-gitlab` (M03) quand chaque équipe gère ses pipelines.

## Exercice 11.4 ⭐⭐ — Durcir ArgoCD
### Solution
```bash
argocd account can-i create projects '*' --argocd-context <CONTEXTE_OPS_BOB>
kubectl patch cm argocd-cm -n argocd --type merge --patch-file labs/m11/argocd-cm-hardening.yaml
argocd login localhost:8443 --username admin --insecure
```
Résultat (testé au M03) : `rpc error: code = Unauthenticated desc = Account admin is disabled`.

| Réglage | Défaut v3.6 | Production |
|---|---|---|
| `admin.enabled` | `true` | `false` |
| `users.anonymous.enabled` | `false` | `false` (conforme) |
| `exec.enabled` | `false` | `false` (conforme) |
| `users.session.duration` | `24h` | `8h` |
| TLS | Certificat auto-signé | Certificat reconnu (`argocd-server-tls`) |
| `server.rbac.rollback.enforce.enable` | désactivé | `"true"` |

Réactivation : `kubectl patch cm argocd-cm -n argocd --type merge -p '{"data":{"admin.enabled":"true"}}'`.

## Défi 11.5 ⭐⭐⭐ — Registre privé et secret de téléchargement
### Solution
```bash
kubectl create secret docker-registry gitlab-registry -n flotte-dev \
  --docker-server=registry.gitlab.com \
  --docker-username=<DEPLOY_TOKEN_USER> --docker-password=<DEPLOY_TOKEN> \
  --dry-run=client -o yaml | kubeseal --format yaml \
  > apps/flotte-web/overlays/dev/sealed-registry-secret.yaml
```
Overlay `dev` : ajout du fichier à `resources`, et patch :
```yaml
patches:
  - target: {group: argoproj.io, kind: Rollout, name: flotte-web}
    patch: |-
      - op: add
        path: /spec/template/spec/imagePullSecrets
        value: [{name: gitlab-registry}]
```
Testé avec un registre privé à authentification (`registry:2` + htpasswd) à la place de `registry.gitlab.com` : secret scellé par la commande ci-dessus → Secret `kubernetes.io/dockerconfigjson` créé par le contrôleur ; pod avec `imagePullSecrets` → `Running` ; sans → `ImagePullBackOff` (`authorization failed: no basic auth credentials`) ; patch rendu sur le Rollout de l'overlay `dev`. Jeton de déploiement GitLab (portée `read_registry`) à créer le J-1.

Secret propre à chaque namespace : un pod ne peut référencer que des Secrets de son namespace ; et la portée *strict* de Sealed Secrets impose de sceller par namespace.

## Défi 11.6 ⭐⭐⭐ — N'accepter que des commits signés
Testé sur un cluster kind séparé (ArgoCD 3.6.1, GnuPG 2.2.27, dépôt Git interne au cluster).

### Solution
```bash
export GNUPGHOME=$HOME/.gnupg-flotte && mkdir -m 700 -p "$GNUPGHOME"
gpg --batch --passphrase '' --quick-gen-key "Ops Flotte <ops@hexa-mobilite.test>" ed25519 sign 1d
KID=$(gpg --list-keys --with-colons | awk -F: '/^pub/{print $5; exit}')
gpg --armor --export "$KID" > ops-flotte.asc
argocd gpg add --from ops-flotte.asc
argocd gpg list
kubectl patch appproj flotte -n argocd --type merge -p "{\"spec\":{\"signatureKeys\":[{\"keyID\":\"$KID\"}]}}"
```
Sortie mesurée de `argocd gpg list` :
```
KEYID             TYPE     IDENTITY
191A59647C86D5C2  ED25519  Ops Flotte <ops@hexa-mobilite.test>
```
Commit non signé → `OutOfSync`, condition :
```
GIT/GPG: Failed verifying revision 62f8ae808b7898f6ce02d179eedee1e517202b7b by 't <t@t>': unsigned (key_id=)
```
Commit signé :
```bash
git -c user.signingkey="$KID" commit -S -am "fix: replicas" && git push
argocd app terminate-op flotte-web-dev      # opération automatique bloquée sur la révision non signée
```
Résultat mesuré : `Synced` / `Healthy` sur la révision signée.

Commit signé par une autre clé :
```
GIT/GPG: Failed verifying revision 8bfba84c... by 'Intrus <intrus@exemple.test>': signed with key not in keyring (key_id=ED5ADEE803F95014)
```
Fin de défi : `kubectl patch appproj flotte -n argocd --type json -p '[{"op":"remove","path":"/spec/signatureKeys"}]'`.

### Pourquoi
- `signatureKeys` du projet : toute révision synchronisée doit être signée par une des clés listées et présente dans le trousseau d'ArgoCD (`argocd-gpg-keys-cm`).
- Seul le commit pointé par la révision (le dernier) est vérifié, pas l'historique : un commit non signé suivi d'un commit signé passe → la signature exprime « un ops a validé cet état », à combiner avec des branches protégées et des MR.
- Opération automatique en échec : elle réessaie la **même** révision (non signée) jusqu'à sa limite → `terminate-op` pour repartir sur la dernière révision.
- Clé sans phrase de passe, validité courte, `GNUPGHOME` séparé : adapté au laboratoire seulement ; en production, clés matérielles ou signature SSH/X.509 côté GitLab et clé de vérification gérée en configuration déclarative.
- Les sources Helm (dépôt de charts) ne sont pas concernées par cette vérification.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Commit signé refusé `unsigned` | `git commit` sans `-S`, ou `commit.gpgsign` non défini | `git log --show-signature -1` avant le push |
| `signed with key not in keyring` avec la bonne clé | Clé publique non importée, ou ID de sous-clé ≠ ID déclaré | `argocd gpg list` ; déclarer l'ID affiché dans le message |
| Toujours bloqué après un commit signé | Opération précédente en cours de nouvelles tentatives | `argocd app terminate-op <APP>` |

## Défi 11.7 ⭐⭐⭐ — Rotation de la clé Sealed Secrets
Testé sur un cluster kind séparé (Sealed Secrets v0.41.2, kubeseal 0.41.2).

### Solution
```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  --sort-by=.metadata.creationTimestamp -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp
kubeseal --fetch-cert > cert-avant.pem
kubectl set env deploy/sealed-secrets-controller -n kube-system SEALED_SECRETS_KEY_CUTOFF_TIME="$(date -R)"
kubectl rollout status deploy/sealed-secrets-controller -n kube-system
kubeseal --fetch-cert > cert-apres.pem && cmp cert-avant.pem cert-apres.pem   # différents
```
Clés mesurées :
```
NAME                      CREATED
sealed-secrets-keyk6vqs   2026-11-16T16:20:44Z
sealed-secrets-key6q7nw   2026-11-16T16:21:32Z
```
Journal : `registered private key secretname=sealed-secrets-keyk6vqs` puis `New key written ... name=sealed-secrets-key6q7nw` ; SealedSecrets existants toujours déchiffrés.

Rechiffrement (sans la valeur en clair) :
```bash
for e in dev recette; do
  f=apps/flotte-web/overlays/$e/sealed-secret.yaml
  kubeseal --re-encrypt -o yaml < "$f" > "$f.new" && mv "$f.new" "$f"
done
git commit -am "chore: rechiffrement SealedSecrets (rotation de clé)" && git push
```
Retrait de l'ancienne clé (après synchronisation de tous les environnements) :
```bash
kubectl delete secret sealed-secrets-keyk6vqs -n kube-system
kubectl rollout restart deploy/sealed-secrets-controller -n kube-system
```
Mesures après retrait : ancien scellé → `no key could decrypt secret (API_KEY)`, aucun Secret ; scellé rechiffré → condition `Synced=True`, valeur intacte.

### Pourquoi
- Le contrôleur crée une nouvelle clé tous les 30 jours par défaut et **garde** les anciennes : rotation automatique = nouveaux scellés avec la nouvelle clé, sans rendre illisibles les anciens.
- `SEALED_SECRETS_KEY_CUTOFF_TIME` (ou `--key-cutoff-time`) : au démarrage, nouvelle clé si la plus récente est antérieure à cette date → rotation à la demande.
- `--re-encrypt` : déchiffrement et rechiffrement par le contrôleur, la valeur ne transite jamais en clair sur le poste.
- Retirer l'ancienne clé **après** rechiffrement de tous les scellés de Git (tous dépôts, tous namespaces), sinon perte au prochain déploiement.
- Limite : une clé compromise permet de déchiffrer tous les anciens scellés présents dans l'**historique Git** → la seule vraie remédiation est de changer la valeur du secret (nouvelle clé d'API), puis de la sceller.

### Erreurs fréquentes
| Symptôme | Cause | Déblocage |
|---|---|---|
| Aucune nouvelle clé au redémarrage | Date de coupure au mauvais format, ou antérieure à la clé la plus récente | `date -R` au moment de la rotation |
| `kubeseal` en erreur juste après la rotation | Contrôleur en cours de redémarrage | `kubectl rollout status` avant `kubeseal` |
| Secret disparu après retrait de clé | Scellé non rechiffré, puis SealedSecret recréé | Restaurer la clé depuis la sauvegarde (exercice 11.2), rechiffrer, retirer |

## Bonus
| Aspect | OIDC direct (`oidc.config`) | Dex (`dex.config`, Défi 03.6) |
|---|---|---|
| Composant | `argocd-server` parle directement au fournisseur | `argocd-dex-server` sert d'intermédiaire |
| Secret client | `argocd-secret` (`$oidc.<nom>.clientSecret`) | `argocd-secret` (`$dex.<nom>.clientSecret`) |
| Groupes | Revendication `groups` du jeton OIDC (portée demandée) | Fournis par le connecteur Dex (LDAP, GitLab, SAML) |
| Cas d'usage | Fournisseur OIDC existant (Keycloak, Entra ID, Okta) | Annuaire sans OIDC (LDAP, SAML) ou forge Git |

## QCM — Réponses
1. **B** — Base64 est un encodage réversible sans clé.
2. **C** — La clé privée est détenue par le contrôleur, dans le cluster.
3. **B** — Portée strict : nom et namespace sont liés au chiffrement.
4. **B** — Un rôle de projet délègue des droits limités au projet, avec ses propres jetons.
5. **B** — `exec.enabled: "false"` désactive le terminal web.
6. **A** — Sans la clé privée, aucun SealedSecret ne peut être déchiffré.
7. **C** — External Secrets Operator lit la valeur dans un coffre ; Git ne contient qu'une référence.
