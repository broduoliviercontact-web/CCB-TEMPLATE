---
name: safe-git-boundaries
description: Appliquer les limites Git et d’écriture des rôles CCB avant toute opération sensible.
---

# Safe Git Boundaries

## Rôles

- **Manager** : lecture, planification et délégation ; aucune modification applicative, commit,
  push, merge ou déploiement sans autorisation explicite.
- **Graph** : lecture du code et de la documentation, analyse technique ; écriture seulement
  dans `graphify-out/` avec autorisation explicite ; aucune modification applicative.
- **Graphiste** : lecture des fichiers textuels de design, analyse UX/UI ; écriture seulement
  dans `graphiste-out/` avec autorisation explicite ; aucune modification applicative.
- **Developer** : seul rôle autorisé à modifier les fichiers applicatifs ; travail dans un
  worktree isolé, tests selon le contexte ; aucun push ou déploiement sans autorisation.
- **Reviewer** : lecture seule, aucun correctif direct ; rend un verdict et une liste de
  problèmes ; aucun commit ou push.

## Règles générales

- Ne jamais utiliser `git push --force`.
- Ne jamais réécrire l’historique sans autorisation humaine explicite.
- Afficher `git status --short` avant toute opération sensible.
- Ne jamais inclure un secret dans un commit.
- Ne jamais modifier un fichier hors périmètre sans le signaler.
- Distinguer les fichiers préexistants des fichiers modifiés pendant la mission.
