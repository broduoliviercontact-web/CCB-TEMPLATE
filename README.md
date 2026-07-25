# CCB Template

Un point de départ générique pour travailler avec Claude Codex Bridge (CCB) dans un dépôt Git.
Il définit une séparation de responsabilités durable, des mémoires persistantes et des
contrôles simples à réutiliser dans un nouveau projet.

## Les cinq agents

| Agent | Responsabilité | Écriture produit |
| --- | --- | --- |
| manager | Reçoit la demande, planifie, délègue et consolide. | Jamais |
| graph | Analyse textuellement l'architecture et les dépendances. | Jamais |
| graphiste | Analyse UX/UI et donne une direction visuelle depuis des fichiers textuels. | Jamais |
| developer | Implémente dans un worktree isolé. | Seul agent autorisé |
| reviewer | Relit le diff, les tests et les risques. | Jamais |

Le flux normal est `manager → graph et/ou graphiste → developer → reviewer → manager`.
Le manager délègue toute implémentation lorsqu'un developer est disponible ; le reviewer
ne corrige jamais directement le code. Graph traite l'architecture technique, les dépendances
et la structure du code ; graphiste traite UX/UI, mise en page, tokens et cohérence visuelle.

## Politique TEXT ONLY

Les agents utilisent des modèles textuels. Ils ne doivent jamais ouvrir, envoyer ou
interpréter une image, une capture d'écran, un fichier PDF rendu comme image ou un outil
Vision. Préférer le DOM, HTML, CSS, JavaScript, logs, stack traces, sorties textuelles de
Puppeteer/Playwright, diff Git et tests automatisés. Voir
[`.ccb/AGENT_POLICY.md`](.ccb/AGENT_POLICY.md).

## Skills partagés

Le catalogue minimal sous [`skills/shared/`](skills/shared/) contient des références de travail
réutilisables : transmission, mémoire projet, limites Git et politique TEXT ONLY. Ces skills
ne remplacent pas `.ccb/AGENT_POLICY.md`, ne donnent aucune permission supplémentaire et les
agents ne lisent que ceux utiles à leur mission. Cette première version reste volontairement
simple ; aucun skill externe n’est ajouté sans audit humain.

## Utilisation avec Claude Code et Codex

CCB peut piloter Claude Code comme interface de fournisseur. Codex peut utiliser ce dépôt
comme contrat de workflow : il lit les politiques et mémoires, laisse le manager orchestrer,
et réserve les modifications produit au developer. Aucune clé, session, état provider ou
runtime CCB ne doit être versionné.

## Installer dans un nouveau projet

1. Clonez le template :

   ```sh
   git clone https://github.com/broduoliviercontact-web/CCB-TEMPLATE.git
   cd CCB-TEMPLATE
   ```

2. Le projet cible doit être un dépôt Git ayant déjà un commit initial. Installez les fichiers
   persistants sans écraser les mémoires locales :

   ```sh
   ./scripts/install-project.sh /chemin/vers/mon-projet
   ./scripts/validate-ccb.sh /chemin/vers/mon-projet
   ```

3. Pour mettre à jour la politique commune, tout en préservant tous les `memory.md`, utilisez :

   ```sh
   ./scripts/install-project.sh /chemin/vers/mon-projet --update
   ```

   L'ancienne politique est sauvegardée sous `.ccb/backups/`.

4. Ajoutez une configuration CCB adaptée au projet si nécessaire, sans commettre les
   sessions, worktrees, sauvegardes ou états provider.
5. Démarrez ensuite CCB selon la procédure locale de votre environnement. Les scripts ne
   démarrent jamais CCB automatiquement.

Les scripts ne démarrent aucun agent et ne modifient pas les sources applicatives.

## Contenu

- `.ccb/` : politiques et mémoires persistantes ;
- `docs/` : architecture, workflow, rôles et démarrage ;
- `scripts/` : installation non destructive et validation ;
- `tests/` : test d'intégration de l'installation ;
- `graphify-out/.gitkeep` et `graphiste-out/.gitkeep` : emplacements réservés aux sorties
  explicitement demandées ; leurs productions locales sont ignorées ;
- `examples/` : emplacement pour de futurs exemples génériques.

La CI GitHub exécute la validation shell et le test d'installation sur les push vers `main` et
les pull requests ciblant `main`.

## Activer le dépôt comme GitHub Template

Sur GitHub, activez manuellement : **Settings → General → Template repository**.

## Licence

Ce template est distribué sous licence [MIT](LICENSE).
