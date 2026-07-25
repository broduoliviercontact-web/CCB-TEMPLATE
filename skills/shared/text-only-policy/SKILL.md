---
name: text-only-policy
description: Appliquer la politique CCB TEXT ONLY et choisir des preuves textuelles plutôt que Vision.
---

# Text Only Policy

## Interdictions

- Ne pas analyser une capture d’écran.
- Ne pas ouvrir ou interpréter un PNG, JPG ou WEBP.
- Ne pas utiliser Vision.
- Ne pas interpréter un PDF rendu comme image.
- Ne pas envoyer une image à un autre agent.
- Ne pas rouvrir une capture créée pendant un test.

## Alternatives autorisées

- HTML, CSS et SVG textuel ;
- structure DOM et attributs ARIA ;
- tokens de design ;
- logs, stack traces et `textContent` ;
- sorties textuelles Playwright ou Puppeteer ;
- résultats de tests et diffs Git ;
- inspection textuelle des valeurs calculées lorsqu’elle est disponible.

Si une analyse visuelle est indispensable, arrêter la mission et demander une autorisation
humaine explicite.
