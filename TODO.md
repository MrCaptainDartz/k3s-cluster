# TODO: Évolution du Cluster K3s

Ordonné du plus utile au moins utile pour cet homelab. Les sections « Pourquoi » rappellent le raisonnement pour ne pas re-litiger plus tard.

## 1. Migrer le repo GitOps de GitHub vers le Forgejo local

**Pourquoi en premier :** Forgejo (Layer 0, hors cluster) existe déjà mais n'est plus la source GitOps depuis le passage à GitHub ; rapatrier le repo rend le cluster réellement autonome (rebuild/DR sans dépendance externe) — c'était d'ailleurs le design initial de Layer 0.

- [ ] Créer le repo sur Forgejo (`git.infra-services.local`) et y pousser l'historique complet (miroir).
- [ ] Deploy key : enregistrer la clé ArgoCD existante dans Forgejo (ou en générer une dédiée) — côté Ansible : `argocd_git_repository_url` + `argocd_git_deploy_key` dans `ansible-k3s/inventory/group_vars/all.yml` (format SSH Forgejo : `ssh://git@git.infra-services.local:2222/<owner>/k3s-cluster.git`).
- [ ] Mettre à jour `gitops/components/cluster-settings/cluster-settings.yaml` → nouveau `repoURL`.
- [ ] Cutover : resync root-app ; les retries nouvellement ajoutés absorbent la transition. Le remote GitHub devient ensuite un miroir en lecture seule (ou supprimé).
- [ ] Adapter §4 (Renovate) : plus d'app GitHub — Renovate self-hosted supporte Gitea/Forgejo (runner local ou CronJob dans le cluster).
- [ ] Mettre à jour les READMEs (source GitOps : GitHub → Forgejo) et l'ajouter au runbook DR (§14).

## 2. Supervision des Backups — alertes sur échec

**Pourquoi :** trou béant actuel — ni les snapshots etcd (locaux, 6h) ni les CronJobs `volume-snapshotter` (PVC Prometheus/Grafana/Loki, quotidien 2h) n'alertent en cas d'échec ; un backup silencieusement cassé ne se découvre qu'au restore. Coût : un après-midi.

- [ ] Alerte PrometheusRule sur `kube_job_status_failed` pour les CronJobs `grafana-/loki-/prometheus-snapshotter` (règle `KubeJobFailed` du KPS existe déjà par défaut — vérifier qu'elle est routée/captée, sinon la surcharger).
- [ ] Alerte sur l'âge du dernier snapshot etcd : k3s expose déjà les métriques etcd sur `:2381` (cf. config control-plane) — sonder via métrique ou via le filesystem (`node_filesystem_*` / textfile collector sur le répertoire snapshots).
- [ ] Router ces alertes vers le receiver `telegram` existant.
- [ ] (Vérif croisée) Tester **une fois** un restore réel d'un VolumeSnapshot pour valider la chaîne de bout en bout.

## 3. Fiabilité des Workloads critiques — PDB, requests, PriorityClass

**Pourquoi :** kured drain des nœuds régulièrement ; aujourd'hui un drain peut évacuer Prometheus ou Loki (singletons) sans garde-fou, et ces deux pods n'ont **aucune** request (`{}`) → premiers éjectés sous pression mémoire. C'est le chantier le plus « production-grade » de la liste.

- [ ] **PodDisruptionBudgets** sur les singletons de l'observability : `minAvailable: 1` pour Prometheus, Alertmanager, Loki, Grafana (seul `coredns-pdb` existe aujourd'hui).
- [ ] **Requests** (pas forcément des limits) sur les pods essentiels (Prometheus, Alertmanager, Loki, Grafana, ArgoCD, cert-manager, Traefik) → QoS `Guaranteed`/`Burstable` → évités en dernier lors d'une eviction.
- [ ] **PriorityClass** haute (ex. `system-cluster-critical` ou custom) sur ces mêmes pods → preemptent les autres sous pression et sont schedulés en premier.
- [ ] Réserver les **limits** aux pods à risque de débordement (requêtes Loki/Prometheus mal bornées, exporteurs qui fuient) pour caper le blast radius.
- [ ] Pas de `ResourceQuota`/`LimitRange` global : disproportionné pour des serveurs fixes dont on contrôle tous les workloads — la protection ciblée PriorityClass + requests + PDB suffit.

## 4. Automatisation des Dépendances (Renovate)

**Pourquoi :** des dizaines de versions pinnées (charts argo-cd/KPS/Loki/traefik, binaire k3s, rôle Galaxy) et rien ne signale leur vieillissement. L'auto-merge des patchs est acceptable **parce que** le déploiement est validable from-scratch sur VMs fraîches (démontré : ~12 min, zéro intervention).

- [ ] Installer l'app GitHub Renovate (repo auto-hébergé : prévoir les credentials d'accès en plus de la clé de déploiement ArgoCD).
- [ ] Créer `renovate.json` à la racine : scanners pour `requirements.yml` Ansible, valeurs Helm (`targetRevision`/versions dans les values), kustomizations, et le `k3s_version` des group_vars.
- [ ] Configurer l'auto-merge pour les patchs et mineures ; garder les majeures en revue manuelle.

## 5. Alertes GitOps via les métriques ArgoCD (PAS argocd-notifications)

**Pourquoi :** un app `OutOfSync` avec toutes ses ressources `Healthy` est invisible dans la stack actuelle. Approche choisie : **réutiliser la chaîne Prometheus → Telegram existante** plutôt que d'ajouter le contrôleur `argocd-notifications` (annotations par app, secrets/templates dédiés) — moins de composants, même résultat.

- [ ] ServiceMonitor sur les métriques ArgoCD (`argocd-application-controller`, `argocd-server`).
- [ ] PrometheusRule : `argocd_app_info{health_status="Degraded"}` et `sync_status="OutOfSync"` avec `for: 15m` (tolère les transitoires de bootstrap observés).
- [ ] Routage vers le receiver `telegram`.
- [ ] Dashboard Grafana ArgoCD (id community) en sidecar provisioning, tant qu'à faire.

## 6. Pre-commit hooks sur le repo GitOps

**Pourquoi :** chaque manifeste cassé committé coûte un debug ArgoCD ; les hooks bloquent avant le push. 20 minutes de setup.

- [ ] `kubeconform` sur `gitops/` (validation schéma des manifestes).
- [ ] `yamllint` + `ansible-lint` sur `ansible-*/`.
- [ ] Détection de secrets en clair (gitleaks) — les secrets doivent rester dans OpenBao/ExternalSecrets.
- [ ] Vérification Jinja : rendre les templates `ansible-k3s/templates/*.j2` avec des valeurs factices + parse YAML (reproduit le piège `trim_blocks` sur `valuesContent`).

## 7. Vrai certificat Let's Encrypt pour l'Ingress ArgoCD

**Pourquoi :** quick win — aujourd'hui `argocd.captaindartz.org` sert le cert par défaut de Traefik (cert-manager n'existe pas encore au moment du bootstrap Ansible).

- [ ] Ajouter une `Certificate` cert-manager / bloc `tls:` en GitOps dans l'app argocd (cert-manager est up à la wave −7, donc disponible dès que GitOps prend le relais — comme déjà fait pour `grafana-tls`).

## 8. SSO — Authentik (+ CloudNativePG en prérequis)

**Pourquoi :** un seul login + MFA sur Grafana/ArgoCD/Proxmox — l'upgrade « homelab sérieux ». Choix arrêté : **Authentik** plutôt qu'Authelia (OIDC complet, UX admin). Il faut un Postgres → CloudNativePG est le standard actuel (failover, backups, monitoring intégrés, s'appuie bien sur ceph-csi RBD) et prépare le terrain pour toute app future à BDD.

- [ ] Créer `gitops/infrastructure/cloudnative-pg/` (operator) — placer tôt dans les waves (stockage déjà prêt).
- [ ] Créer `gitops/infrastructure/authentik/` : cluster CNPG + Authentik (server + worker).
- [ ] Middleware `Traefik ForwardAuth` pour les services internes sans auth native.
- [ ] (Optionnel) OIDC natif pour Grafana, ArgoCD, Proxmox.

## 9. Trivy Operator

**Pourquoi :** meilleur ratio valeur/effort de la sécurité — visibilité CVE en continu sur les workloads exposés, métriques → Grafana existant.

- [ ] Créer `gitops/infrastructure/trivy/` et déployer l'operator (scan des images au repos).
- [ ] Exporter les métriques vulnérabilités vers Prometheus + dashboard Grafana.
- [ ] NetworkPolicy dédiée (default-deny en place) + ressources bornées sur les scan jobs.

## 10. kube-bench (CIS) en CronJob

**Pourquoi :** pas cher, profil k3s intégré ; l'audit-policy est déjà tunée mais rien ne valide la posture CIS en continu.

- [ ] CronJob hebdomadaire kube-bench avec le profil `k3s`, rapports en ConfigMap/logs → Loki.
- [ ] Alerte (ou simple log watchable) sur les contrôles FAIL nouveaux.

## 11. Kyverno — validatif minimal uniquement

**Pourquoi la prudence :** Kyverno place un webhook d'admission dans le chemin critique de tous les déploiements (s'il tombe avec `failurePolicy: Fail`, plus rien ne se déploie). Ici tous les workloads sont maîtrisés, donc on se limite au **validatif non bloquant** ; pas de mutations (friction avec les diffs ArgoCD). Le dossier `gitops/infrastructure/cluster-policies/` existe déjà et l'attend.

- [ ] Politiques `failurePolicy: Ignore` : bloquer/signaler les images `:latest`, imposer le TLS sur les Ingress, rappeler les PSS restricted.
- [ ] PDB + requests sur les pods Kyverno eux-mêmes (cf. §3).
- [ ] NetworkPolicy dédiée.

## 12. Gateway API (opportuniste)

**Pourquoi :** l'API Ingress est figée et Ingress-NGINX est archivé depuis mars 2026 — la direction est claire, mais pas urgente tant que les Ingress Traefik v3 fonctionnent. À faire **au prochain chantier touchant les ingress**, pas en chantier dédié.

- [ ] Convertir les Ingress existants en `Gateway`/`HTTPRoute` (`gateway.networking.k8s.io`) via le support Traefik v3.

## 13. CrowdSec + bouncer Traefik

**Pourquoi :** blocage communautaire des IP hostiles au niveau de l'ingress pour le périmètre exposé — réellement utile contrairement à un EDR lourd, et faible coût.

- [ ] Déployer CrowdSec (LAPI + agent) + le bouncer Traefik en middleware sur les entrypoints publics.
- [ ] Remonter les décisions/bans en métriques → Grafana.

## 14. Runbook DR écrit

**Pourquoi :** l'architecture rend déjà le rebuild quasi automatique (OpenTofu → ansible-services → ansible-k3s → GitOps → ESO remonte les secrets) — autant documenter et éprouver l'ordre exact une fois, sinon ça ne vaut rien le jour J.

- [ ] Documenter la procédure : ordre des playbooks, restore des VolumeSnapshots PVC, vérifications post-restore.
- [ ] Jouer la procédure une fois sur les VMs réinitialisées (déjà partiellement validé : bootstrap complet ~12 min).

## 15. Falco (reliquat — dernière priorité)

**Pourquoi tout en bas :** sécurité runtime eBPF lourde (sonde kernel sur chaque nœud, bruit important à tuner) pour un threat model « quelques ingress exposés » déjà couvert par NetworkPolicies + audit logs + Loki. Ne faire **que** si objectif d'apprentissage de l'outil.

- [ ] Déployer Falco (driver eBPF) + rules minimales (exec dans pod, écriture `/proc`, escalation de privilège).

---

### Écartés (décision actée, ne pas re-proposer)

- **Homepage / portail unifié** — valeur opérationnelle faible (Grafana existe), renoncé.
- **Probes externes** (blackbox/Gatus) — non retenu.
- **Snapshots etcd hors-VM** (`--etcd-s3`…) — non retenu : les VMs sont déjà sauvegardées intégralement au niveau Proxmox.
