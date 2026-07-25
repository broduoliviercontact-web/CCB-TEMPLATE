# CCB Template

Un point de départ générique pour travailler avec Claude Codex Bridge (CCB) dans un dépôt Git.
Il définit une séparation de responsabilités durable, des mémoires persistantes et des
contrôles simples à réutiliser dans un nouveau projet.

## Les quatre agents

| Agent | Responsabilité | Écriture produit |
| --- | --- | --- |
| manager | Reçoit la demande, planifie, délègue et consolide. | Jamais |
| graph | Analyse textuellement l'architecture et les dépendances. | Jamais |
| developer | Implémente dans un worktree isolé. | Seul agent autorisé |
| reviewer | Relit le diff, les tests et les risques. | Jamais |

Le flux normal est `manager → graph → developer → reviewer → manager`.
Le manager délègue toute implémentation lorsqu'un developer est disponible ; le reviewer
ne corrige jamais directement le code.

## Politique TEXT ONLY

Les agents utilisent des modèles textuels. Ils ne doivent jamais ouvrir, envoyer ou
interpréter une image, une capture d'écran, un fichier PDF rendu comme image ou un outil
Vision. Préférer le DOM, HTML, CSS, JavaScript, logs, stack traces, sorties textuelles de
Puppeteer/Playwright, diff Git et tests automatisés. Voir
[`.ccb/AGENT_POLICY.md`](.ccb/AGENT_POLICY.md).

## Utilisation avec Claude Code et Codex

CCB peut piloter Claude Code comme interface de fournisseur. Codex peut utiliser ce dépôt
comme contrat de workflow : il lit les politiques et mémoires, laisse le manager orchestrer,
et réserve les modifications produit au developer. Aucune clé, session, état provider ou
runtime CCB ne doit être versionné.

## Installer dans un nouveau projet

1. Copiez les fichiers persistants `.ccb/`, `docs/`, `scripts/` et `.gitignore` dans le
   dépôt Git cible.
2. Depuis la racine du projet cible, lancez `./scripts/install-project.sh`.
3. Vérifiez la structure avec `./scripts/validate-ccb.sh`.
4. Ajoutez une configuration CCB adaptée au projet si nécessaire, sans commettre les
   sessions, worktrees, sauvegardes ou états provider.
5. Démarrez ensuite CCB selon la procédure locale de votre environnement.

Les scripts ne démarrent aucun agent et ne modifient pas les sources applicatives.

## Contenu

- `.ccb/` : politiques et mémoires persistantes ;
- `docs/` : architecture, workflow, rôles et démarrage ;
- `scripts/` : installation et validation non destructives ;
- `graphify-out/.gitkeep` : emplacement réservé aux sorties explicitement demandées ;
- `examples/` : emplacement pour de futurs exemples génériques.

## Licence

Ce template est distribué sous licence [MIT](LICENSE).
