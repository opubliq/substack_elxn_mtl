# Modèles de Séries Temporelles à Implémenter

## Traitement des Indécis

**Approche**: On modélise les intentions de vote de chaque candidat en pourcentage du total incluant les indécis (donc vote shares qui somment à <1). Ensuite, on renormalise uniquement les 5 candidats (excluant indécis) pour obtenir des pourcentages entre candidats qui somment à 1.

Exemple: Si prédictions brutes = {Soraya: 33%, Luc: 18%, Gilbert: 11%, Craig: 6%, JF: 3%, et donc on déduit Indécis: 29%}, on drop indécis puis renormalise: Soraya = 33%/71% = 46.5%, etc.

## Modèle 1: Régression Polynomiale avec Interaction Temps×Média

**Description**: Régression qui modélise l'évolution des intentions de vote comme une fonction polynomiale du temps, avec effet média qui varie temporellement.

**Équation**:
```
vote_i,t = β₀_i + β₁_i·t + β₂_i·t² + β₃_i·salience_i,t + β₄_i·(salience_i,t × t) + ε_i,t

Où:
- vote_i,t = intention de vote pour candidat i au temps t
- t = jours depuis début de campagne
- salience_i,t = saillance média du candidat i au temps t
- ε_i,t ~ N(0, σ²)
```

**Explication**: Le trend temporel est capturé par le polynôme (linéaire + quadratique). L'effet de la saillance média n'est pas constant: il peut s'amplifier ou diminuer avec le temps via le terme d'interaction. Par exemple, la même saillance média peut avoir un effet plus fort à l'approche de l'élection.

---

## Modèle 2: State-Space Model (Kalman Filter)

**Description**: Modèle à état latent où les vraies intentions de vote évoluent quotidiennement selon un processus stochastique, avec drift influencé par les médias. Les polls observés sont des mesures bruitées de cet état latent.

**Équations**:

**Équation d'état** (évolution quotidienne):
```
vote_i,t = vote_i,t-1 + drift_i,t + ε_t

drift_i,t = α_i + β₁_i·salience_i,t + β₂_i·momentum_i,t

ε_t ~ N(0, Q)
```

**Équation d'observation** (polls = snapshots):
```
poll_i,observed = vote_i,t_poll + ν_t

ν_t ~ N(0, R)
```

**Matrices**:
```
États: X_t = [vote_1,t, vote_2,t, ..., vote_6,t]ᵀ

Transition: X_t = X_t-1 + B·Media_t + ε_t
Observation: Y_t = H·X_t + ν_t
```

**Explication**: Entre les polls, les intentions de vote "dérivent" jour après jour selon un random walk avec drift. Le drift n'est pas constant: il dépend de la saillance et du momentum média du jour. Les 4 polls observés servent à calibrer l'état latent via le filtre de Kalman, qui fait du smoothing optimal en tenant compte de l'incertitude.

---

## Modèle 3: Bayesian Structural Time Series (BSTS)

**Description**: Décomposition additive de la série temporelle en composantes structurelles (trend local, régression dynamique, seasonal) avec inférence bayésienne complète.

**Équation**:
```
vote_i,t = μ_i,t + β_t·X_i,t + S_t + ε_t

Composantes:

1. Local Linear Trend (μ_i,t):
   μ_i,t = μ_i,t-1 + δ_i,t-1 + u_t
   δ_i,t = δ_i,t-1 + v_t

   Où δ_i,t = pente (trend velocity)

2. Régression dynamique (β_t·X_i,t):
   β_t ~ N(β_t-1, W)
   X_i,t = [salience_i,t, momentum_i,t, reconnaissance_i,t]

   Coefficients qui évoluent dans le temps

3. Seasonal (S_t): optionnel
   S_t = -Σ(S_t-j) pour j=1..s-1

4. Erreur:
   ε_t ~ N(0, σ²_obs)
```

**Explication**: Le modèle décompose chaque série en un trend qui peut accélérer ou ralentir (local linear trend), un effet de régression sur les médias dont les coefficients varient dans le temps (permet de capturer si l'effet média devient plus fort vers la fin), et une composante seasonale si des patterns hebdomadaires existent. Toute l'inférence est bayésienne via MCMC, ce qui donne des distributions complètes (pas juste point estimates).

---

## Modèle 4: Vector Autoregression (VAR)

**Description**: Système multivarié où chaque série temporelle (candidat) dépend de son propre passé ET du passé de toutes les autres séries, capturant ainsi les effets de substitution entre candidats.

**Équation**:
```
Vote_t = c + A₁·Vote_t-1 + A₂·Vote_t-2 + ... + Aᵨ·Vote_t-p + B·Media_t + ε_t

En notation vectorielle:
┌ vote_1,t ┐   ┌ c₁ ┐   ┌ a₁₁ a₁₂ ... a₁₆ ┐ ┌ vote_1,t-1 ┐   ┌ b₁₁ b₁₂ ┐ ┌ salience_1,t ┐   ┌ ε₁,t ┐
│ vote_2,t │   │ c₂ │   │ a₂₁ a₂₂ ... a₂₆ │ │ vote_2,t-1 │   │ b₂₁ b₂₂ │ │ salience_2,t │   │ ε₂,t │
│    ⋮     │ = │ ⋮  │ + │  ⋮   ⋮   ⋱   ⋮  │·│     ⋮      │ + │  ⋮   ⋮  │·│      ⋮       │ + │  ⋮   │
└ vote_6,t ┘   └ c₆ ┘   └ a₆₁ a₆₂ ... a₆₆ ┘ └ vote_6,t-1 ┘   └ b₆₁ b₆₂ ┘ └ salience_6,t ┘   └ ε₆,t ┘

Où:
- Vote_t = vecteur (6×1) des intentions de vote [5 candidats + indécis]
- A_i = matrices (6×6) des coefficients autorégressifs au lag i
- B = matrice (6×2) des effets média [salience, momentum]
- Media_t = variables exogènes
- ε_t ~ N(0, Σ) avec Σ matrice de covariance (6×6)
```

**Exemple d'interprétation**:
```
vote_soraya,t = a₁₁·vote_soraya,t-1 + a₁₂·vote_luc,t-1 + a₁₃·vote_craig,t-1 +
                a₁₄·vote_gilbert,t-1 + a₁₅·vote_jf,t-1 + a₁₆·indecis_t-1 +
                b₁₁·salience_soraya,t + b₁₂·momentum_soraya,t + ε₁,t
```

**Explication**: Chaque candidat est influencé par son propre passé (a_ii) mais aussi par le passé des autres candidats (a_ij pour i≠j). Par exemple, une baisse des indécis (a_i6 < 0) peut causer une hausse proportionnelle de Soraya (si a_16 > 0). Le modèle capture explicitement les effets de substitution: les électeurs qui quittent un candidat vont vers un autre. Les Impulse Response Functions (IRF) permettent de tracer comment un choc sur un candidat se propage à tous les autres dans le temps.
