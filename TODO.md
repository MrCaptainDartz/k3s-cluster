# TODO: Évolution du Cluster K3s vers l'État de l'Art

Ce document liste les tâches à accomplir pour améliorer l'infrastructure GitOps, suite à l'analyse de la baseline.

## 1. Notifications GitOps (ArgoCD vers Telegram)
- [ ] Récupérer le token du bot Telegram utilisé actuellement pour Alertmanager, ou en créer un dédié à ArgoCD.
- [ ] Créer le `Secret` Kubernetes contenant le token Telegram dans le namespace `argocd`.
- [ ] Activer `argocd-notifications` dans la configuration Ansible (`09-argocd.yml.j2`) ou via GitOps si géré par Helm.
- [ ] Configurer le `ConfigMap` des notifications (triggers et templates) pour envoyer un message sur `SyncFailed` ou `Degraded`.
- [ ] Annoter les applications ArgoCD pour s'abonner aux notifications Telegram.

## 2. Sécurité & Conformité de la Posture (Kyverno & Trivy Operator)
- [ ] Créer le répertoire de déploiement `gitops/infrastructure/kyverno/`.
- [ ] Configurer les politiques Kyverno pour appliquer les Pod Security Standards (PSS Restricted).
- [ ] Bloquer les images sans tag fixe ou utilisant le tag `:latest`, et imposer le TLS sur les Ingresses.
- [ ] Créer le répertoire de déploiement `gitops/infrastructure/trivy/`.
- [ ] Déployer Trivy Operator pour analyser en continu les vulnérabilités (CVE) des workloads et exporter les métriques dans Grafana.
- [ ] Déployer **Falco** (sécurité runtime) pour détecter en temps réel les comportements suspects (exec dans pod, shell, écriture `/proc`, escalation de privilège). Complémentaire de Trivy (scan d'images au repos) — Trivy voit l'image, Falco voit l'exécution.
- [ ] Déployer **kube-bench** (conformité CIS Kubernetes) en CronJob périodique + exporter/alertes sur les contrôles échoués. L'audit-policy est déjà tuné, mais aucun benchmark automatisé ne valide la posture.

## 3. Gestion des Identités et SSO (Authelia ou Authentik)
- [ ] Déterminer la solution à utiliser (Authelia pour sa légèreté ou Authentik pour ses fonctionnalités complètes).
- [ ] Créer le répertoire de déploiement `gitops/infrastructure/sso/`.
- [ ] Préparer les manifestes Helm/Kustomize pour déployer l'Identity Provider (IdP).
- [ ] Configurer le middleware `Traefik ForwardAuth` pour protéger les services internes (sans auth native).
- [ ] (Optionnel) Configurer l'intégration OIDC pour les applications compatibles (Proxmox, Grafana, ArgoCD).

## 4. Automatisation des Dépendances (Renovate)
- [ ] Installer l'application GitHub/GitLab Renovate sur le dépôt ou préparer le déploiement d'un runner local.
- [ ] Créer le fichier `renovate.json` à la racine du dépôt.
- [ ] Configurer Renovate pour scanner les fichiers Ansible, valeurs Helm, et Kustomizations.
- [ ] (Optionnel) Configurer l'auto-merge pour les patchs et mises à jour mineures afin de réduire la charge mentale.

## 5. Portail Homelab Unifié (Homepage) & K8s Gateway API
- [ ] Créer le répertoire de déploiement `gitops/infrastructure/homepage/`.
- [ ] Configurer Homepage pour la découverte automatique des Ingress/Services Kubernetes et l'affichage des métriques du cluster.
- [ ] Protéger l'accès au tableau de bord Homepage via le middleware SSO.
- [ ] Préparer la transition des Ingresses Traefik v3 vers la Kubernetes Gateway API (`gateway.networking.k8s.io`).

## 6. Fiabilité & Résilience des Workloads
- [ ] Ajouter des **PodDisruptionBudgets** sur les workloads critiques de l'observability (`minAvailable: 1` pour Prometheus, Alertmanager, Loki, Grafana) — actuellement seul `coredns-pdb` existe, donc un drain kured peut évacuer un singleton sans garde-fou.
- [ ] **Requests/limits + PriorityClass sur les pods essentiels** au fonctionnement du cluster (Prometheus, Alertmanager, Loki, Grafana, ArgoCD, cert-manager, Traefik, kube-vip) :
      - leur attribuer une `PriorityClass` haute (ex. `system-cluster-critical` ou custom) afin qu'ils **preemptent** les autres sous pression et soient schedulés en premier ;
      - fixer des **requests** (pas forcément des limits) → QoS `Guaranteed`/`Burstable` → évités en dernier lors d'une eviction under pressure (les pods `BestEffort` sans requests partent d'abord). Actuellement Prometheus/Loki n'ont **aucune** request/limit (`{}`) ;
      - réserver les **limits** aux pods à risque de débordement (requêtes Loki/Prometheus mal bornées, exporteurs qui fuient) pour caper le blast radius.
      - Pas de `ResourceQuota`/`LimitRange` global : disproportionné pour des petits serveurs fixes où l'on contrôle tout ce qui tourne — la protection ciblée PriorityClass+requests+PDB suffit.
- [ ] **Certificat Let's Encrypt pour l'Ingress ArgoCD** (`argocd.captaindartz.org`). Actuellement l'ingress n'a que l'annotation `traefik.ingress.kubernetes.io/router.tls: "true"` et utilise le cert par défaut de Traefik (cert-manager n'est pas encore bootstrappé au moment du playbook Ansible). Ajouter une `Certificate` cert-manager / bloc `tls:` en gitops (cert-manager est déployé après, sync-wave -7) pour un vrai cert LE, comme Grafana.

## 7. Supervision des Backups
- [ ] **Alerte sur échec des backups** : aujourd'hui ni les snapshots etcd (locaux, toutes les 6h) ni les CronJobs `volume-snapshotter` (PVC Prometheus/Grafana/Loki, quotidien 2h) n'alertent en cas d'échec — un backup silencieusement cassé n'est détecté qu'au moment du restore.
      - Ajouter une alerte Prometheus sur l'âge du dernier snapshot etcd (k3s expose `etcd_debugging_mvcc_db_total_size_in_bytes` etc. ; ou une sonde via le filesystem) ;
      - Alerte sur `kube_job_status_failed` pour les CronJobs `grafana-/loki-/prometheus-snapshotter` (règle `KubeJobFailed` du KPS par défaut, à router/capter) ;
      - Router ces alertes vers Telegram (receiver `telegram`).