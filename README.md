# Norovirus climate sensitivity — Republic of Korea, 2005–2024

Reproducible R analysis code for the manuscript:
**"Climate Sensitivity of Norovirus in Korea, 2005–2024: Post-COVID-19 Temperature Amplification and an Event-Based Heatwave Alert"** (submitted to the *International Journal of Hygiene and Environmental Health*).

## Contents
- `norovirus_climate_gam_full.R` — full pipeline:
  data loading → preprocessing (ISO-week aggregation, 0–8 wk lags, p99 winsorization) →
  negative-binomial GAMM (Set 2 LONG) → Watson U² circular test (+ amplitude-free
  sensitivity: unweighted, year-unit permutation, placebo boundary) →
  Period × Climate interaction → heatwave dose–response (24–28 °C, with Holm/BH
  multiple-testing correction and label-permutation stability) → DLNM (linear exposure,
  integer lag) → ZINB block bootstrap → Ljung–Box diagnostics → figures/tables →
  peer-review re-analyses (M1 absolute humidity; M2 boundary robustness; M3 heatwave
  multiple testing; M4 placebo falsification; M5 year-unit seasonality permutation).

## Data availability
Weekly laboratory-confirmed norovirus food-poisoning counts are aggregated national
surveillance data (no personal identifiers) from the Korea Ministry of Food and Drug
Safety (MFDS) Food Poisoning Statistics System, available from MFDS. Weekly
meteorological and PM₁₀ data are openly available from the Korea Meteorological
Administration (KMA) Open MET Data Portal. The raw input workbook is not redistributed here.

## Requirements
R ≥ 4.5; packages auto-installed by the script: mgcv, nlme, dlnm, pscl, circular, MASS,
splines, readxl, dplyr, ggplot2, patchwork, scales, lubridate, tidyr, segmented, openxlsx.

## Citation
Kim S, Chun BC. Climate Sensitivity of Norovirus in Korea, 2005–2024 (manuscript under review). Citation to be updated on publication.
