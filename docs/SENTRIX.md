# SENTRIX — assistant vocal

## Identité

Tête robotique vectorielle (`sentrix/presentation/sentrix_head.dart`) : casque nacré, visière noire
à trame de points, yeux en arc cyan, écouteurs lumineux, micro-perche. Six états :

| État | Quand | Rendu |
|---|---|---|
| Repos | par défaut | yeux en arc, clignement |
| Écoute | après un appui sur SENTRIX | écouteurs et micro pulsés |
| Analyse | phrase reçue, interprétation | yeux qui balayent |
| Réponse | réponse prononcée | onde sous les yeux |
| Notification | alerte de plaque active | yeux ronds rouges |
| Erreur | commande non comprise, micro refusé… | yeux en croix orange |

## Utilisation

- **Appui** sur SENTRIX (écran de navigation) : écoute d'une commande. L'activation est manuelle ;
  un mot d'activation (« Sentrix ») pourra être ajouté plus tard.
- **Nouvel appui** pendant l'écoute : annulation.
- **Appui long** : menu (recherche, plaques, historique, réglages).
- Une bulle affiche ce qui est entendu puis la réponse ; la réponse est aussi prononcée.

## Chaîne de traitement

1. Autorisation du micro (et de la reconnaissance vocale sur iOS).
2. Reconnaissance vocale du système (`speech_to_text`, français), arrêt au silence (2 s) ou après 8 s.
3. Interprétation (`sentrix/domain/command_engine.dart`) : phrase normalisée (minuscules, accents,
   mots vides retirés, synonymes : « allume » = « active », « caméra » = « détection »…), comparée aux
   phrases-types de chaque commande ; mots-clés obligatoires pour distinguer les contraires.
4. Exécution de l'action, puis réponse vocale et visuelle. Commande inconnue : « Je n'ai pas compris ».

## Commandes (provisoires)

Liste dans `sentrix/application/sentrix_commands.dart`, reprenant les exemples de l'image de
référence. **À valider avec le propriétaire du projet.**

| Commande | Exemple |
|---|---|
| Lancer la navigation | « Lancer la navigation » |
| Arrêter la navigation | « Annule le guidage » |
| Heure d'arrivée | « Dans combien de temps j'arrive ? » |
| Activer / désactiver la détection | « Active la détection », « Éteins la caméra » |
| Afficher le trafic | résume les perturbations sur l'itinéraire (ou autour), « inconnu » hors zone couverte, ou indique que le trafic n'est pas configuré |
| Lire la dernière alerte | « Lire la dernière alerte » |
| Ouvrir l'historique / la liste des plaques / les réglages | « Montre-moi l'historique » |
| Couper / activer le guidage vocal | « Coupe le guidage vocal » |
| Vitesse | « Quelle est ma vitesse ? » |
| Aide | « Que peux-tu faire ? » |

## Ajouter une commande

```dart
SentrixCommand(
  id: 'fuel.nearest',                       // identifiant unique
  label: 'Station-service la plus proche',  // affiché dans l'aide
  phrases: ['Station-service la plus proche', 'Je dois faire le plein'],
  keywords: ['station'],                    // facultatif : mots indispensables
  action: (c) async {
    // c.ref donne accès à tous les modules (navigation, plaques…)
    return const CommandResult('Recherche des stations en cours.');
  },
),
```

Aucune autre modification n'est nécessaire : la commande est reconnue, listée dans les réglages
et vérifiée par le test « chaque commande se reconnaît par sa phrase d'exemple ».

## Confidentialité

L'écoute ne démarre que sur appui. La transcription utilise le moteur du système (Google sur Android,
Apple sur iOS), qui peut traiter l'audio en ligne selon le téléphone.

## Annonces des perturbations

Pendant le guidage, SENTRIX annonce chaque perturbation signalée sur l'itinéraire quand elle est à
moins de 5 km devant (« Attention, accident sur la N20 dans 2 kilomètres. »), une seule fois. Les
annonces passent après les consignes de navigation et les alertes de plaques, et le bouton de
coupure du guidage vocal les coupe aussi.
