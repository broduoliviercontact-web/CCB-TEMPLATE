---
name: project-memory
description: Maintenir les mémoires CCB avec des informations durables, factuelles et sans secrets.
---

# Project Memory

Écrire uniquement des informations durables, courtes et factuelles. Ne pas mémoriser les
sorties temporaires, secrets, tokens, mots de passe ou clés API. Dater une décision importante
lorsque cela aide à comprendre son évolution. Corriger une information ancienne plutôt que
d’ajouter plusieurs versions contradictoires.

## Destinations

- `.ccb/ccb_memory.md` : décisions globales, contraintes partagées et conventions communes.
- `.ccb/agents/manager/memory.md` : décisions de pilotage, délégations et contraintes projet.
- `.ccb/agents/graph/memory.md` : architecture, dépendances et risques structurels.
- `.ccb/agents/graphiste/memory.md` : direction visuelle, UX/UI, accessibilité et conventions graphiques.
- `.ccb/agents/reviewer/memory.md` : risques récurrents, critères de validation et points de vigilance.

La mémoire partagée sert à tous les agents ; une mémoire d’agent sert uniquement à son rôle.
Le developer n’a pas nécessairement besoin d’une mémoire persistante distincte si la politique
CCB actuelle ne la prévoit pas.
