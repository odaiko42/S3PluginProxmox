# Plugin S3 Proxmox VE - Tâches de développement

## État actuel
- ✅ Plugin S3 simplifié créé (structure de base)
- ✅ Enregistrement dans Proxmox fonctionnel
- ✅ Apparition dans l'interface web
- ⚠️ Fonctionnalités S3 non implémentées (stubs seulement)

---

## Phase 1 : Infrastructure et dépendances

### [ ] 1.1 Gestion des modules Perl
- [ ] Installer et configurer AWS::S3 ou Net::Amazon::S3
- [ ] Installer HTTP::Request et LWP::UserAgent
- [ ] Installer JSON::XS pour le parsing JSON
- [ ] Installer Digest::HMAC_SHA256 pour les signatures AWS
- [ ] Installer MIME::Base64 pour l'encodage
- [ ] Tester la compatibilité avec Proxmox VE 8.x
- [ ] Créer un script d'installation automatique des dépendances

### [ ] 1.2 Configuration et authentification
- [ ] Implémenter la validation des credentials AWS
- [ ] Ajouter support pour les profils AWS (~/.aws/credentials)
- [ ] Implémenter la signature AWS v4
- [ ] Gérer les tokens temporaires (STS)
- [ ] Ajouter support pour les rôles IAM
- [ ] Implémenter la rotation automatique des credentials

### [ ] 1.3 Gestion des erreurs et logging
- [ ] Créer un système de logging structuré
- [ ] Implémenter la gestion des timeouts
- [ ] Ajouter retry logic avec backoff exponentiel
- [ ] Gérer les erreurs de réseau et de connectivité
- [ ] Implémenter la validation des paramètres de configuration

---

## Phase 2 : Opérations S3 de base

### [ ] 2.1 Connexion et test de connectivité
- [ ] Remplacer le ping par un test S3 réel (ListBuckets)
- [ ] Implémenter la vérification de l'existence du bucket
- [ ] Tester les permissions de lecture/écriture
- [ ] Valider la région S3 configurée
- [ ] Implémenter le test de connectivité avec différents endpoints

### [ ] 2.2 Opérations sur les objets S3
- [ ] Implémenter S3 PUT (upload de fichiers)
- [ ] Implémenter S3 GET (download de fichiers) 
- [ ] Implémenter S3 DELETE (suppression d'objets)
- [ ] Implémenter S3 HEAD (métadonnées d'objets)
- [ ] Implémenter S3 LIST (listing des objets)
- [ ] Gérer les multipart uploads pour gros fichiers (>5GB)

### [ ] 2.3 Gestion des métadonnées
- [ ] Stocker les métadonnées Proxmox dans S3 tags
- [ ] Implémenter la gestion des formats (qcow2, raw, vmdk)
- [ ] Gérer les métadonnées de taille de fichier
- [ ] Stocker les informations de VM (VMID, nom, etc.)
- [ ] Implémenter la gestion des checksums (MD5, SHA256)

---

## Phase 3 : Intégration Proxmox VE

### [ ] 3.1 Implémentation des méthodes de stockage
- [ ] `list_images()` - Lister les images VM dans S3
- [ ] `list_volumes()` - Lister tous les volumes par type
- [ ] `alloc_image()` - Allocation d'espace pour nouvelle image
- [ ] `free_image()` - Suppression d'image VM
- [ ] `status()` - État réel du stockage S3 (espace utilisé/disponible)
- [ ] `path()` - Génération des chemins S3 corrects

### [ ] 3.2 Opérations sur les volumes
- [ ] `volume_size_info()` - Taille réelle des volumes S3
- [ ] `volume_resize()` - Redimensionnement (si possible)
- [ ] `volume_import()` - Import de volumes existants
- [ ] `volume_export()` - Export de volumes vers S3
- [ ] Gestion des formats de disque (conversion automatique)

### [ ] 3.3 Gestion des snapshots (si supporté)
- [ ] `volume_snapshot()` - Créer un snapshot via copie S3
- [ ] `volume_snapshot_rollback()` - Restaurer depuis snapshot
- [ ] `volume_snapshot_delete()` - Supprimer un snapshot
- [ ] `volume_has_feature()` - Définir les capacités supportées
- [ ] Implémenter la gestion des snapshots incrémentaux

---

## Phase 4 : Types de contenu

### [ ] 4.1 Images de VMs
- [ ] Support upload d'images disk (qcow2, raw, vmdk)
- [ ] Download d'images pour démarrage de VM
- [ ] Gestion des images de base (templates)
- [ ] Conversion de formats à la volée
- [ ] Optimisation des transferts (compression)

### [ ] 4.2 Images ISO
- [ ] Upload d'images ISO vers S3
- [ ] Listing des ISOs disponibles
- [ ] Download d'ISOs pour installation
- [ ] Gestion des métadonnées ISO (nom, version, taille)

### [ ] 4.3 Backups
- [ ] Intégration avec vzdump (backup Proxmox)
- [ ] Support des backups compressés (zst, gz)
- [ ] Gestion de la rétention des backups
- [ ] Backup incrémentaux/différentiels
- [ ] Restauration depuis S3

### [ ] 4.4 Templates de conteneurs
- [ ] Support des templates LXC (.tar.gz)
- [ ] Upload de nouveaux templates
- [ ] Gestion des versions de templates
- [ ] Optimisation du stockage (déduplication)

### [ ] 4.5 Snippets et configs
- [ ] Stockage des scripts cloud-init
- [ ] Stockage des configurations personnalisées  
- [ ] Gestion des scripts de hook
- [ ] Synchronisation bidirectionnelle

---

## Phase 5 : Performance et optimisation

### [ ] 5.1 Optimisations de transfert
- [ ] Implémentation du multipart upload
- [ ] Transfer acceleration S3 (si disponible)
- [ ] Compression à la volée
- [ ] Cache local pour objets fréquents
- [ ] Parallélisation des uploads/downloads

### [ ] 5.2 Gestion de la bande passante
- [ ] Limitation de bande passante configurable
- [ ] Priorisation des transferts critiques
- [ ] Statistiques de transfert
- [ ] Monitoring des performances S3

### [ ] 5.3 Cache et optimisation
- [ ] Cache local des métadonnées
- [ ] Cache des petits fichiers fréquents
- [ ] Invalidation intelligente du cache
- [ ] Prefetching prédictif

---

## Phase 6 : Sécurité et fiabilité

### [ ] 6.1 Sécurité
- [ ] Chiffrement des données en transit (TLS)
- [ ] Support du chiffrement côté serveur S3 (SSE)
- [ ] Chiffrement côté client (optionnel)
- [ ] Audit des accès S3
- [ ] Rotation des clés de chiffrement

### [ ] 6.2 Fiabilité
- [ ] Gestion des pannes réseau temporaires
- [ ] Retry automatique avec backoff
- [ ] Détection de corruption de données
- [ ] Réplication multi-région (optionnel)
- [ ] Monitoring de la santé du stockage

### [ ] 6.3 Backup et disaster recovery
- [ ] Stratégie de backup des métadonnées
- [ ] Plan de disaster recovery
- [ ] Test de récupération automatisé
- [ ] Documentation des procédures d'urgence

---

## Phase 7 : Interface utilisateur et configuration

### [ ] 7.1 Interface web Proxmox
- [ ] Améliorer le formulaire de configuration S3
- [ ] Ajouter validation en temps réel des credentials  
- [ ] Affichage des statistiques d'utilisation S3
- [ ] Interface de gestion des backups S3
- [ ] Monitoring visuel des transferts

### [ ] 7.2 Configuration avancée
- [ ] Support de multiple buckets
- [ ] Configuration par type de contenu
- [ ] Stratégies de rétention configurables
- [ ] Alertes et notifications
- [ ] Intégration avec monitoring externe

### [ ] 7.3 Scripts et outils
- [ ] Script de migration depuis autres stockages
- [ ] Outil de vérification d'intégrité
- [ ] Script de nettoyage automatique
- [ ] Outil de diagnostic et debug
- [ ] Interface en ligne de commande

---

## Phase 8 : Tests et documentation

### [ ] 8.1 Tests unitaires
- [ ] Tests des opérations S3 de base
- [ ] Tests de gestion d'erreurs
- [ ] Tests de performance
- [ ] Tests de sécurité
- [ ] Tests d'intégration Proxmox

### [ ] 8.2 Tests d'intégration
- [ ] Tests avec différents providers S3 (AWS, MinIO, etc.)
- [ ] Tests de charge avec multiples VMs
- [ ] Tests de failover et récupération
- [ ] Tests de migration de données
- [ ] Tests de compatibilité Proxmox versions

### [ ] 8.3 Documentation
- [ ] Guide d'installation détaillé
- [ ] Manuel de configuration
- [ ] Guide de dépannage
- [ ] Documentation API
- [ ] Exemples d'utilisation
- [ ] FAQ et troubleshooting

---

## Phase 9 : Déploiement et maintenance

### [ ] 9.1 Packaging
- [ ] Package Debian pour installation facile
- [ ] Script d'installation automatique
- [ ] Gestion des dépendances automatique
- [ ] Système de mise à jour
- [ ] Désinstallation propre

### [ ] 9.2 Monitoring et maintenance
- [ ] Métriques de performance
- [ ] Alertes en cas de problème
- [ ] Log rotation et archivage
- [ ] Maintenance automatique (cleanup)
- [ ] Rapports d'utilisation

### [ ] 9.3 Support et évolution
- [ ] Système de feedback utilisateurs
- [ ] Gestion des bugs et améliorations
- [ ] Roadmap des fonctionnalités futures
- [ ] Communauté et support
- [ ] Migration vers nouvelles versions

---

## Priorités de développement

### Phase critique (P0) - Plugin fonctionnel de base
- [x] Structure plugin de base ✅
- [ ] Dépendances Perl S3
- [ ] Opérations S3 essentielles (PUT/GET/DELETE/LIST)
- [ ] Intégration Proxmox basique

### Phase importante (P1) - Fonctionnalités essentielles  
- [ ] Support complet des images VM
- [ ] Gestion des backups
- [ ] Interface utilisateur améliorée
- [ ] Tests de base

### Phase secondaire (P2) - Optimisations
- [ ] Performance et cache
- [ ] Sécurité avancée
- [ ] Monitoring et alertes
- [ ] Documentation complète

### Phase future (P3) - Fonctionnalités avancées
- [ ] Snapshots et réplication
- [ ] Multi-région
- [ ] Intégrations externes
- [ ] Outils avancés

---

## Ressources nécessaires

### Développement
- Environnement de test Proxmox VE
- Accès à stockage S3 (AWS ou MinIO)
- Connaissance Perl et API Proxmox
- Outils de test et debugging

### Documentation et support
- Serveur de documentation
- Système de tracking des issues
- Plateforme de tests automatisés
- Infrastructure de packaging

---

*Dernière mise à jour : 3 octobre 2025*
*Plugin actuel : Version 0.1-alpha (structure de base uniquement)*