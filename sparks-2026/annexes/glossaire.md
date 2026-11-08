# Glossaire

## A à C
- **Abort** : interruption d'une livraison Argo Rollouts ; retour à la version stable (M08).
- **AnalysisTemplate** : modèle de mesure automatique d'un canari (Job, Prometheus, Web) (M08).
- **Application** : ressource ArgoCD reliant une source Git (ou chart) à une destination du cluster, dans un projet (M04).
- **ApplicationSet** : ressource qui génère des Applications à partir de générateurs (liste, Git, clusters) (M12).
- **App of Apps** : Application racine dont la source contient d'autres Applications (M12).
- **AppProject** : périmètre d'une équipe : dépôts, destinations, ressources, rôles autorisés (M03).
- **Argo Rollouts** : contrôleur Kubernetes des stratégies bleu-vert et canari (M08).
- **Auto-sync** : synchronisation automatique dès qu'un écart avec Git est détecté (M05).
- **Bleu-vert (blue-green)** : nouvelle version déployée à côté de l'ancienne, bascule du trafic en une fois (M08).
- **Canari (canary)** : exposition progressive d'une nouvelle version à une fraction des pods ou du trafic (M08).
- **ConfigMap générée** : ConfigMap produite par Kustomize, nom suffixé par une empreinte du contenu (M09).
- **CRD** (*Custom Resource Definition*) : extension de l'API Kubernetes (ex. `Application`, `Rollout`).

## D à H
- **Dérive (drift)** : écart entre l'état du cluster et l'état décrit dans Git (M01, M05).
- **Dex** : fournisseur d'identité intégré à ArgoCD, connecteurs LDAP, SAML, GitLab (M03, M11).
- **Finalizer** : marqueur qui retarde la suppression d'une ressource ; `resources-finalizer.argocd.argoproj.io` supprime en cascade les ressources d'une Application (M04).
- **GitOps** : modèle où Git décrit l'état souhaité, appliqué et réconcilié en continu par un agent (M01).
- **Health** : santé d'une ressource ou d'une Application : `Healthy`, `Progressing`, `Degraded`, `Suspended`, `Missing`, `Unknown` (M01, M07).
- **Helm** : gestionnaire de paquets Kubernetes (charts) ; utilisé par ArgoCD comme moteur de rendu (M09).
- **Hook** : ressource exécutée à une phase précise de la synchronisation (`PreSync`, `PostSync`, `SyncFail`) (M05).

## I à O
- **IgnoreDifferences** : champs exclus de la comparaison Git ↔ cluster (M05).
- **Kustomize** : outil de personnalisation de manifestes par base et overlays (M09).
- **Multi-sources** : Application combinant plusieurs sources (ex. chart externe + valeurs dans Git, `$values`) (M09).
- **Notification** : message émis par ArgoCD : trigger + template + service + abonnement (M07).
- **OIDC** (*OpenID Connect*) : protocole d'authentification fédérée utilisé pour le SSO (M11).
- **OutOfSync** : état d'une Application dont le cluster diffère de Git (M01).
- **Overlay** : variante d'environnement d'une base Kustomize (M09).

## P à R
- **Prune** : suppression des ressources retirées de Git (M05).
- **Pull (modèle)** : l'agent dans le cluster tire l'état depuis Git ; s'oppose au modèle *push* où la CI déploie (M01, M10).
- **Réconciliation** : boucle de comparaison et de correction entre Git et le cluster (120 s + jitter par défaut) (M01).
- **Repo-server** : composant d'ArgoCD qui clone les dépôts et rend les manifestes (M01).
- **Rollback** : retour à une version antérieure ; par `git revert` (GitOps) ou `argocd app rollback` (urgence) (M06).
- **Rollout** : ressource Argo Rollouts remplaçant un Deployment, avec stratégie de livraison (M08).

## S à Z
- **SealedSecret** : secret chiffré par la clé publique d'un contrôleur, stockable dans Git (M11).
- **Self-heal** : correction automatique d'une dérive du cluster (M05).
- **Sharding** : répartition des clusters entre plusieurs réplicas du contrôleur (M12).
- **Source Hydrator** : fonctionnalité (bêta depuis 3.5) qui écrit dans Git les manifestes rendus (M12).
- **Sync** : application de l'état de Git sur le cluster ; statut `Synced` / `OutOfSync` (M04, M05).
- **Sync wave** : ordre d'application des ressources au sein d'une phase (M05).
- **Sync window** : créneau autorisant ou interdisant les synchronisations d'un projet (M05, M12).
- **Webhook** : appel HTTP de la forge Git vers ArgoCD pour une détection immédiate des commits (M10).
