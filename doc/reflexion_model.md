# Réflexion sur le Modèle de Forecasting Électoral

**Objectif**: Développer un modèle parcimonieux et agnostique qui démontre la valeur des données médiatiques pour le forecasting électoral municipal.

**Contexte**: 5 jours avant l'élection municipale de Montréal (2 novembre 2025)

---

## Données Disponibles

### 1. Sondages (3 Points Temporels)
- **Sondage 1**: 15-20 septembre Léger (https://lactualite.com/politique/montreal-pourrait-avoir-une-nouvelle-mairesse-et-les-montrealais-sen-balancent-un-peu/)
- **Sondage 2**: Léger (26-30 septembre 2025) - n=500, ±4.4%
- **Sondage 3**: 9 octobre 2025 Segma https://ici.radio-canada.ca/nouvelle/2200097/soraya-rabouin-segma-intentions-vote-boyer-fournier

**Variables par sondage:**
- Intentions de vote (si disponibles)
- Reconnaissance (% qui connaissent le candidat)
- Satisfaction à l'égard de l'administration sortante
- Enjeux les plus importants, décomposition par bases électorales

### 2. Données Médiatiques (Quotidiennes)

**Saillance des candidats/partis** (par jour):
- Martinez Ferrada (Ensemble Montréal)
- Rabouin (Projet Montréal)
- Sauvé (Transition Montréal)
- Thibodeau (Action Montréal)
- Kacou (Futur Montréal)

**Saillance des enjeux** (par jour):
- Coût des loyers / accès à la propriété
- Itinérance / logement social
- Congestion routière / chantiers
- Transport collectif
- Sécurité / criminalité
- Taxes
- Propreté / déneigement
- Autres...

---

## Question de Recherche Centrale

**Comment la saillance médiatique (candidats + enjeux) améliore-t-elle la prédiction électorale au-delà des sondages seuls?**

### Hypothèses à Tester

1. **H1 (Saillance candidate)**: Les candidats avec une saillance médiatique croissante gagnent des points d'intention de vote
2. **H2 (Saillance des enjeux)**: Les candidats associés médiatiquement aux enjeux prioritaires des électeurs bénéficient d'un avantage
3. **H3 (Momentum)**: Les changements temporels de saillance (momentum) prédisent mieux que les niveaux absolus
4. **H4 (Interaction)**: L'effet de la saillance médiatique est amplifié pour les candidats peu connus (faible reconnaissance)

---

## Approches de Modélisation

### Option A: Modèle de Diffusion de l'Information
**Logique**: Les médias influencent l'opinion publique avec un délai (lag)

**Spécification**:
```
Vote_share_t = f(Poll_t-1, Media_salience_t-7:t, Momentum_t)
```

**Avantages**:
- Intuitif: l'information média met du temps à diffuser
- Testable: quel lag optimal? (3 jours? 7 jours?)
- Parcimonieux: quelques paramètres de lag

**Défis**:
- Calibration du lag (arbitraire?)
- Avec 5 jours avant élection, peu de marge pour tester différents lags

---

### Option B: Modèle de Marche Aléatoire Bayésienne
**Logique**: Les intentions de vote évoluent jour par jour, influencées par la saillance médiatique

**Spécification**:
```
Vote_share_t ~ Normal(Vote_share_t-1 + drift_t, σ²)

drift_t = β₁ * Δ_salience_candidate_t +
          β₂ * Σ(salience_issue_i,t * issue_ownership_i)
```

**Variables**:
- `Δ_salience_candidate`: Changement quotidien de saillance du candidat
- `salience_issue_i`: Saillance de l'enjeu i
- `issue_ownership_i`: Score d'association candidat-enjeu (à calculer ou assumer)

**Avantages**:
- Modèle dynamique qui utilise toute la série temporelle
- Incorpore naturellement l'incertitude croissante dans le temps
- Les 3 sondages servent d'ancres pour calibrer le processus

**Défis**:
- Plus complexe à implémenter (State-Space model)
- Requiert assumption sur σ² (volatilité quotidienne)

---

### Option C: Modèle de Régression Simple avec Pooling Temporel
**Logique**: Agrégation de toutes les données sur une fenêtre temporelle pertinente

**Spécification (la plus simple)**:
```r
# Modèle 1: Baseline (poll-only)
Vote_share ~ Poll_favorable + Poll_recognition

# Modèle 2: Hybrid (poll + media)
Vote_share ~ Poll_favorable +
             Poll_recognition +
             Media_salience_avg_7d +
             Media_momentum_7d +
             Issue_match_score
```

**Variables agrégées** (fenêtre 7 derniers jours):
- `Media_salience_avg_7d`: Moyenne de la saillance candidate sur 7 jours
- `Media_momentum_7d`: Tendance linéaire de saillance (pente régression temporelle)
- `Issue_match_score`: Σ(salience_enjeu × priorité_enjeu_sondage × ownership_candidat)

**Avantages**:
- **Ultra-parcimonieux**: 3-5 paramètres au total
- **Interprétable**: chaque coefficient a un sens clair
- **Rapide à estimer**: régression linéaire ou Dirichlet
- **Facile à valider**: compare R² avec et sans média

**Défis**:
- Perd l'information temporelle fine (jour par jour)
- Assume que relation média-vote est stable dans le temps

---

### Option D: Modèle d'Issue Ownership Pondéré
**Logique**: Les médias déterminent quel candidat "possède" quel enjeu, et les électeurs votent selon leurs priorités

**Spécification**:
```
Vote_share_i = Poll_prior_i × exp(Σ_j w_j × ownership_ij × priority_j)

Où:
- ownership_ij = salience_candidate_i_when_issue_j / salience_issue_j_total
- priority_j = % électeurs citant enjeu j comme prioritaire (du sondage)
- w_j = poids à estimer
```

**Exemple concret**:
- Si Rabouin apparaît dans 60% des articles sur "transport collectif"
- Et 27% des électeurs citent transport comme priorité
- Alors Rabouin gagne: 0.60 × 0.27 × w_transport points

**Avantages**:
- **Exploite pleinement la richesse des données d'enjeux**
- Teste mécanisme causal clair: médias → association candidat-enjeu → vote
- Innovation méthodologique (rarement fait au municipal)

**Défis**:
- Requiert données de co-occurrence candidat-enjeu dans articles
- Plus de paramètres (un w_j par enjeu)
- Assume que ownership médiatique = ownership perçue (à valider)

---

## Recommandation: Approche Progressive

### Étape 1: Modèle Baseline (Poll-Only)
**Objectif**: Établir benchmark à battre

```r
# Modèle le plus simple possible
baseline <- lm(vote_intention ~ favorable_pct + recognition_pct,
               data = poll_data,
               weights = 1/sqrt(n_respondents))
```

**Prédiction**: Vote share = f(favorabilité, reconnaissance)

**Métrique**: R² baseline, RMSE baseline

---

### Étape 2: Modèle Hybrid Simple (Option C)
**Objectif**: Ajouter saillance médiatique de manière parcimonieuse

```r
# Variables médias agrégées (7 derniers jours)
media_features <- media_daily %>%
  filter(date >= today() - 7) %>%
  group_by(candidate) %>%
  summarise(
    salience_mean = mean(salience_total),
    salience_trend = coef(lm(salience_total ~ as.numeric(date)))[2],
    salience_volatility = sd(salience_total)
  )

# Modèle hybrid
hybrid_simple <- lm(vote_intention ~
                      favorable_pct +
                      recognition_pct +
                      salience_mean +
                      salience_trend,
                    data = model_data)
```

**Test de valeur ajoutée**:
```r
anova(baseline, hybrid_simple)  # F-test
# Si p < 0.05: média apporte info significative!
```

**Communication**: "L'ajout des données médiatiques améliore la prédiction de X% (ΔR²)"

---

### Étape 3: Enrichissement avec Issue Ownership (Option D)
**Objectif**: Exploiter dimension enjeux si temps/données le permettent

```r
# Calculer ownership scores
issue_ownership <- media_daily %>%
  left_join(issue_salience_daily, by = c("date", "issue")) %>%
  group_by(candidate, issue) %>%
  summarise(
    ownership_score = sum(candidate_salience_when_issue) / sum(issue_salience)
  )

# Pondérer par priorités des électeurs
issue_priorities <- tribble(
  ~issue, ~priority_pct,
  "loyers", 48,
  "itinerance", 38,
  "congestion", 33,
  "transport", 27,
  # ... etc
)

# Score composite
issue_match <- issue_ownership %>%
  left_join(issue_priorities, by = "issue") %>%
  group_by(candidate) %>%
  summarise(
    issue_match_score = sum(ownership_score * priority_pct / 100)
  )

# Modèle enrichi
hybrid_enriched <- lm(vote_intention ~
                        favorable_pct +
                        recognition_pct +
                        salience_mean +
                        salience_trend +
                        issue_match_score,
                      data = model_data)
```

**Test incrémental**:
```r
anova(hybrid_simple, hybrid_enriched)
# L'issue ownership ajoute-t-elle de l'info au-delà de la saillance brute?
```

---

## Questions Pratiques à Résoudre

### 1. Utilisation des 3 Points Temporels de Sondage

**Option A**: Modèle panel avec 3 observations par candidat
```r
# Données empilées
poll_panel <- bind_rows(
  poll_t1 %>% mutate(wave = 1, days_to_election = XX),
  poll_t2 %>% mutate(wave = 2, days_to_election = YY),
  poll_t3 %>% mutate(wave = 3, days_to_election = 5)
)

# Modèle avec effets candidat
lmer(vote_intention ~ salience_mean + salience_trend +
       (1 | candidate) + days_to_election,
     data = poll_panel)
```

**Option B**: Utiliser sondages pour validation croisée temporelle
- Train sur sondages 1+2 → Prédire sondage 3
- Évaluer si médias améliorent prédiction out-of-sample

**Option C**: Moyenne pondérée par récence
```r
poll_weighted <- poll_panel %>%
  group_by(candidate) %>%
  summarise(
    vote_intention_weighted = weighted.mean(
      vote_intention,
      w = exp(-0.1 * days_to_election)  # décroissance exponentielle
    )
  )
```

**Recommandation**: Option B pour validation rigoureuse, puis Option C pour forecast final

---

### 2. Fenêtre Temporelle pour Agrégation Média

**Question**: Quelle période de saillance médiatique est prédictive?

**Test empirique**:
```r
# Tester différentes fenêtres: 3j, 7j, 14j, 30j
windows <- c(3, 7, 14, 30)

results <- map_df(windows, function(w) {
  media_w <- media_daily %>%
    filter(date >= today() - w) %>%
    group_by(candidate) %>%
    summarise(salience_mean = mean(salience_total))

  fit <- lm(vote_intention ~ favorable_pct + salience_mean,
            data = model_data %>% left_join(media_w))

  tibble(
    window = w,
    r_squared = summary(fit)$r.squared,
    coef_media = coef(fit)["salience_mean"]
  )
})

# Visualiser
ggplot(results, aes(x = window, y = r_squared)) +
  geom_line() + geom_point() +
  labs(title = "Fenêtre temporelle optimale pour saillance média")
```

**Hypothèse (littérature)**: Fenêtre 7 jours optimale (Colladon 2020)

---

### 3. Normalisation de la Saillance

**Problème**: Saillance absolue vs relative?

**Option A**: Saillance relative (part du total)
```r
media_daily <- media_daily %>%
  group_by(date) %>%
  mutate(salience_share = salience_total / sum(salience_total))
```

**Option B**: Saillance absolue (volume brut)
- Captures intensité totale de couverture
- Mais confond candidat avec volume global d'actualité politique

**Option C**: Z-score (standardisé par candidat)
```r
media_daily <- media_daily %>%
  group_by(candidate) %>%
  mutate(salience_z = (salience_total - mean(salience_total)) / sd(salience_total))
```

**Recommandation**:
- **Saillance relative** pour modèle principal (sum-to-1 comme intentions de vote)
- **Z-score** pour tester momentum (déviations de la normale)

---

### 4. Traitement de l'Incertitude

**Sources d'incertitude**:
1. **Incertitude de sondage**: ±4.4% (n=500)
2. **Incertitude de mesure**: Saillance médiatique (bruit dans extraction entités)
3. **Incertitude structurelle**: Relation média-vote (force β inconnue)
4. **Incertitude d'indécis**: 50% sans intention claire (selon contexte)

**Approche Bayésienne recommandée**:
```r
library(brms)

# Priors informatifs basés sur littérature
priors <- c(
  prior(normal(0, 0.5), class = "b", coef = "salience_mean"),  # effet modéré
  prior(normal(0, 0.3), class = "b", coef = "salience_trend"), # effet momentum
  prior(exponential(1), class = "sigma")  # erreur résiduelle
)

fit_bayesian <- brm(
  vote_intention ~ favorable_pct + recognition_pct +
                   salience_mean + salience_trend,
  data = model_data,
  prior = priors,
  family = gaussian(),
  chains = 4, iter = 2000
)

# Posterior predictions avec intervalles crédibles
posterior_predict(fit_bayesian, newdata = forecast_data) %>%
  posterior_summary() %>%
  as_tibble() %>%
  mutate(candidate = model_data$candidate)
```

**Output**: Distributions complètes, pas juste point estimates

---

## Proposition de Modèle Final: "Modèle Parcimonieux à 3 Niveaux"

### Niveau 1: Prior (Sondage)
```
π_i ~ Dirichlet(α₀)  # intentions initiales
α₀_i = n_poll × favorable_pct_i
```

### Niveau 2: Signal Média (Saillance)
```
α_i = α₀_i × exp(β₁ × salience_share_i + β₂ × momentum_i)
```

### Niveau 3: Signal Enjeux (Issue Match)
```
α_i = α_i × exp(β₃ × issue_match_score_i)
```

### Estimation
```r
# Préparer données
model_data <- tibble(
  candidate = c("Martinez Ferrada", "Rabouin", "Sauvé", "Thibodeau", "Kacou"),

  # Prior (sondage Léger)
  favorable_pct = c(32, 19, 19, 14, 9),
  recognition_pct = c(47, 39, 33, 25, 20),

  # Niveau 2 (média - derniers 7 jours)
  salience_share = c(...),    # % de couverture
  momentum = c(...),          # Δ saillance

  # Niveau 3 (enjeux - optionnel)
  issue_match_score = c(...)  # ownership × priorités
)

# Modèle Dirichlet-Multinomial
library(DirichletReg)

# Concentration parameters
alpha_matrix <- model_data %>%
  mutate(
    alpha = favorable_pct * exp(
      beta1 * salience_share +
      beta2 * momentum +
      beta3 * issue_match_score
    )
  ) %>%
  select(alpha) %>%
  as.matrix()

# Fit (nécessite données de training, peut simuler avec bootstrap)
fit <- DirichReg(alpha_matrix ~ salience_share + momentum + issue_match_score,
                 data = model_data)
```

---

## Critères de Succès

### Critère 1: Amélioration Prédictive
**Métrique**: ΔR² (hybrid vs baseline)
- **Minimum acceptable**: +5% (R² = 0.65 → 0.70)
- **Bon**: +10% (R² = 0.65 → 0.75)
- **Excellent**: +15% (R² = 0.65 → 0.80)

### Critère 2: Signification Statistique
**Test**: F-test sur modèles emboîtés
- **Seuil**: p < 0.05 pour ajout de variables médiatiques

### Critère 3: Parcimonie
**Métrique**: AIC/BIC
- Modèle hybride doit avoir BIC inférieur au baseline
- Pénalise complexité excessive

### Critère 4: Validation Croisée Temporelle
**Procédure**:
- Train sur sondages 1+2 + média jusqu'à date sondage 3
- Prédire sondage 3
- MAPE < 10%

### Critère 5: Calibration Post-Election
**Métrique**: Coverage des intervalles crédibles
- 50% intervals devraient contenir ~50% des résultats réels
- 90% intervals devraient contenir ~90% des résultats réels

---

## Timeline de Développement

### Jour 1: Exploration + Baseline
- [ ] Charger et nettoyer données saillance média
- [ ] Calculer statistiques descriptives (fenêtres 3j, 7j, 14j)
- [ ] Fit modèle baseline (poll-only)
- [ ] Documenter R² et RMSE baseline

### Jour 2: Modèle Hybrid Simple
- [ ] Ajouter saillance_mean et momentum aux prédicteurs
- [ ] F-test: média améliore prédiction?
- [ ] Tester différentes fenêtres temporelles
- [ ] Sélectionner spécification optimale

### Jour 3: Enrichissement Enjeux (optionnel)
- [ ] Calculer issue ownership scores
- [ ] Tester amélioration incrémentale
- [ ] Si significatif: inclure dans modèle final
- [ ] Si non: rester avec modèle simple

### Jour 4: Validation + Diagnostics
- [ ] Cross-validation temporelle (sondages 1-2 → 3)
- [ ] Bootstrap pour intervalles de confiance
- [ ] Sensitivity analysis (β₁ ± 50%)
- [ ] Documenter robustesse

### Jour 5: Forecast Final + Visualisation
- [ ] Générer prédictions avec incertitude complète
- [ ] Créer figures pour Substack
- [ ] Rédiger méthodologie claire
- [ ] Archiver forecast pour validation post-élection

---

## Questions Ouvertes

1. **Intentions de vote disponibles?** Les 3 sondages rapportent-ils intentions ou seulement favorabilité?
2. **Co-occurrence candidat-enjeu?** Les données média permettent-elles de mesurer quelle candidat est associé à quel enjeu?
3. **Période de couverture?** Depuis quand les données de saillance sont-elles collectées?
4. **Format des données?** CSV/RDS avec quelle structure exactement?
5. **Validation souhaitée?** Cross-validation temporelle ou juste forecast final?

---

## Conclusion Provisoire

**Modèle recommandé**: **Option C (Régression Simple avec Pooling Temporel)**

**Justification**:
- ✅ **Parcimonieux**: 3-5 paramètres seulement
- ✅ **Agnostique**: Pas d'assumptions fortes sur mécanismes causaux
- ✅ **Interprétable**: Chaque coefficient a sens clair pour Substack
- ✅ **Rapide**: Peut être étendu progressivement (baseline → hybrid → enriched)
- ✅ **Validable**: Comparaison claire avec/sans média via F-test
- ✅ **Innovant au municipal**: Démontre valeur données haute fréquence

**Alternative si temps suffisant**: Enrichir avec issue ownership (Option D) pour exploiter pleinement richesse données enjeux

**Prochaine étape**: Clarifier questions ouvertes ci-dessus pour finaliser spécification exacte
