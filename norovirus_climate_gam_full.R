# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  NORO_GAM — CONSOLIDATED FULL ANALYSIS CODE  (v4, 2026-06-15)              ║
# ║  Climate sensitivity of norovirus notifications, Republic of Korea         ║
# ║  (NB-GAMM + Watson U² + heatwave dose-response + DLNM, COVID Pre/Post)     ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# Author : Seongdae Kim (Korea University)   Advisor : Byung Chul Chun
# Target : International Journal of Hygiene and Environmental Health (IJHEH)
#
# DATA (pulled in PART 1 below):
#   - Weekly norovirus food-poisoning notifications, MFDS Food Poisoning
#     Statistics System, Republic of Korea, 2005 ISO wk 1 - 2024 ISO wk 52.
#   - Weekly climate (KMA ASOS: temperature, RH, precipitation, wind) + PM10,
#     aggregated to ISO week, lagged 0-8 weeks.
#   - Single input workbook: NORO_GAM_v21_Raw_260520_2356.xlsx (sheet
#     "Weekly_FullData"); auto-located under G.Downloads/미팅기록 or G.Downloads.
#
# STRUCTURE
#   PART 1-11  Main pipeline (data load -> preprocessing -> NB-GAMM -> Watson U²
#              -> Period x Climate interaction -> heatwave grid -> DLNM ->
#              ZINB block bootstrap -> Ljung-Box diagnostics -> figures/tables).
#              [from NORO_FULL_원코드_v9_260530.R]
#   PART 12    Peer-review re-analyses, modules M1-M5 (absolute humidity;
#              Pre/Post boundary robustness + amplitude-free Watson; heatwave
#              multiple-testing + permutation; placebo-boundary falsification;
#              year-unit seasonality permutation).
#              [from NORO_REVIEW_ADDON_v1_260614.R]
#              NOTE: PART 12 reloads the same raw workbook so it can also be run
#              standalone; harmless redundancy with PART 1.
#
# Reproduces the manuscript headline numbers (e.g., Watson U²=18.32 [case-weighted];
# year-unit permutation p=0.66; heatwave IRRs; Post-era DLNM temp +41% at lag 4).
# ════════════════════════════════════════════════════════════════════════════

# =============================================================================
#  NORO — TRUE SINGLE FILE 원코드 (자급자족, 외부 .R 의존 0)
# =============================================================================
#  실행: source("NORO_FULL_SINGLE_260526.R")
#
#  내용 (이 한 파일에 다 들어있음):
#    [§ 0]  WRAPPER HEADER — sink + md log + GAM_논문/ override
#    [§ 1]  PACKAGES + PATHS + CONFIG
#    [§ 2]  DATA LOAD + PREPROCESS (Raw xlsx → 1037주 × 2005-2024)
#    [§ 3]  OUTBREAK TREATMENT (Original + Despiked p99)
#    [§ 4]  HELPER FUNCTIONS (build_formula, fit_gamm, eval_fit, extract_pct1)
#    [§ 5]  STAGE A/B/C + Stage E (lpmatrix delta-method SE)
#    [§ 6]  MAIN FIT LOOP (Outbreak × Subset)
#    [§ 7]  SUPPLEMENTARY (Sec 2~9: Temp seg, GAMM smooth, Harmonic, Humid lag,
#                          DLNM, Wind, Heatwave, Diagnostics)
#    [§ 8]  Fig 1c/2c/3c helper data
#    [§ 9]  PER-SET BUILDERS (Tables xlsx 3 sheets + Figures pdf 3 pages)
#    [§ 10] 4 SETS BUILD LOOP (Set1 LONG·Orig / Set2 LONG·Desp /
#                              Set3 SHORT·Orig / Set4 SHORT·Desp)
#    [§ 11] FOOTER — sink 안전 닫기 + md 푸터 (산출물 리스트)
#
#  출력:
#    xlsx (4) + pdf (4)  → G.Downloads/GAM_논문/
#    md 통합 로그        → G.Downloads/ 루트 (휴대용)
#
#  실행 시간: 40-60분 (Stage B ARMA11 가장 오래)
# =============================================================================

# ─── [§ 0] WRAPPER HEADER ───────────────────────────────────────────────────
.HOME   <- path.expand("~")
.GDRIVE <- file.path(.HOME,
  "Library/CloudStorage/GoogleDrive-wwwwrte@gmail.com",
  "내 드라이브/S.K/G.Downloads")
.GAM_DIR <- file.path(.GDRIVE, "GAM_논문")
if (!dir.exists(.GAM_DIR)) dir.create(.GAM_DIR, recursive = TRUE)

.TS     <- format(Sys.time(), "%y%m%d_%H%M")
.LOG_MD <- file.path(.GDRIVE, sprintf("NORO_GAM_v21_RUN_LOG_%s.md", .TS))

while (sink.number() > 0) sink()

writeLines(c(
  "# NORO GAM 4-set TRUE SINGLE FILE 통합 실행 로그 (v9: SUPPLEMENT 검증 G1-G11+G5+Fig viz inline, COVID-onset boundary)",
  "",
  sprintf("- TS: %s", .TS),
  sprintf("- xlsx/pdf 출력: `%s`", .GAM_DIR),
  sprintf("- md 로그 (이 파일): `%s`", .GDRIVE),
  "",
  "## 4세트 정의",
  "",
  "| Set | Lag | Outbreak |",
  "|---|---|---|",
  "| **Set1** | LONG (lag 0-8) | Original (winsor 없음) |",
  "| **Set2** | LONG | De-spiked (winsor p99) |",
  "| **Set3** | SHORT (lag ≤ 4) | Original |",
  "| **Set4** | SHORT | De-spiked |",
  "",
  "---",
  "",
  "## 실행 로그 (console 출력 그대로)",
  "",
  "```text"
), con = .LOG_MD)

.log_conn <- file(.LOG_MD, open = "a", encoding = "UTF-8")
sink(.log_conn, split = TRUE, type = "output")

on.exit({
  while (sink.number() > 0) sink()
  try(close(.log_conn), silent = TRUE)
  cat("\n```\n\n---\n\n## 완료 + 산출물\n\n",
      file = .LOG_MD, append = TRUE)
  cat(sprintf("- 종료: %s\n\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      file = .LOG_MD, append = TRUE)
  fs <- list.files(.GAM_DIR, pattern = "^NORO_v3_", full.names = FALSE)
  fs <- fs[order(fs)]
  for (f in fs) cat(sprintf("- %s\n", f),
                    file = .LOG_MD, append = TRUE)
}, add = TRUE)

cat("════════════════════════════════════════════════════════════\n")
cat(" NORO TRUE SINGLE FILE 실행 시작\n")
cat(sprintf("   xlsx/pdf : %s\n", .GAM_DIR))
cat(sprintf("   md log   : %s\n", basename(.LOG_MD)))
cat("════════════════════════════════════════════════════════════\n\n")

# ─── [§ 1] PACKAGES ─────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  ensure <- function(pkg) if (!requireNamespace(pkg, quietly=TRUE))
    install.packages(pkg, repos="https://cloud.r-project.org")
  for (p in c("readxl","mgcv","nlme","dplyr","tidyr","ggplot2","scales",
              "splines","MASS","dlnm","segmented","openxlsx","patchwork",
              "lubridate")) ensure(p)
  library(readxl); library(mgcv); library(nlme); library(dplyr); library(tidyr)
  library(ggplot2); library(scales); library(splines); library(MASS)
  library(dlnm); library(segmented); library(openxlsx); library(patchwork)
  library(lubridate)
})

# ─── PATHS ──────────────────────────────────────────────────────────────────
home <- path.expand("~")
gdrive_root <- file.path(home,
  "Library/CloudStorage/GoogleDrive-wwwwrte@gmail.com",
  "내 드라이브/S.K/G.Downloads")
if (!dir.exists(gdrive_root)) gdrive_root <- getwd()
OUT_DIR <- .GAM_DIR     # ★ wrapper override — 산출물 GAM_논문/ 직행
STAMP   <- .TS

RAW_FILE <- "NORO_GAM_v21_Raw_260520_2356.xlsx"
RAW_PATH <- NULL
for (cand in c(file.path(gdrive_root, "미팅기록", RAW_FILE),
                file.path(gdrive_root, RAW_FILE))){
  if (file.exists(cand)) { RAW_PATH <- cand; break }
}
stopifnot(!is.null(RAW_PATH))
cat("Raw input:", RAW_PATH, "\n")

# ─── CONFIG ─────────────────────────────────────────────────────────────────
LAGS <- list(LONG=c(temp=3, humid=7, pm10=8, precip=7),
             SHORT=c(temp=3, humid=4, pm10=4, precip=4))
TIME_K <- c(Overall=30, Pre=30, Post=10)
DESPIKE_PCT  <- 0.99
HEATWAVE_BP  <- 26.4

SETS <- list(
  list(id="Set1", lag="LONG",  outbreak="Original",  label="Lag-kept (LONG) · No winsorize (Original)"),
  list(id="Set2", lag="LONG",  outbreak="De-spiked", label="Lag-kept (LONG) · Winsorize p99 (De-spiked)"),
  list(id="Set3", lag="SHORT", outbreak="Original",  label="Lag-4-max (SHORT) · No winsorize (Original)"),
  list(id="Set4", lag="SHORT", outbreak="De-spiked", label="Lag-4-max (SHORT) · Winsorize p99 (De-spiked)")
)

COL_SUB <- c(Overall="#555555", Pre="#185FA5", Post="#A32D2D")
COL_PER <- c(`Pre-COVID (2005-2019)`="#185FA5", `Post-COVID (2020-2024)`="#A32D2D")
SHAPE_SUB <- c(Overall=22, Pre=21, Post=24)

# ─── [§ 2] DATA LOAD + PREPROCESS ───────────────────────────────────────────
cat("\n[A] Loading Raw xlsx...\n")
df_raw <- read_excel(RAW_PATH, sheet="Weekly_FullData") %>% as.data.frame()
cat("   Raw shape:", nrow(df_raw), "x", ncol(df_raw), "\n")

need_lag <- c(paste0("avg_temp_lag",      0:8),
              paste0("humidity_lag",      0:8),
              paste0("pm10_lag",          0:8),
              paste0("precipitation_lag", 0:8))
need_base <- c("year","week","cases","sin52","cos52","sin26","cos26",
                "avg_temp","humidity","pm10","precipitation")
missing_cols <- setdiff(c(need_base, need_lag), names(df_raw))
if (length(missing_cols)){
  stop("Missing columns: ", paste(missing_cols, collapse=", "))
}
df_raw <- df_raw[complete.cases(df_raw[, need_lag]), ]
df_raw <- df_raw[df_raw$year >= 2005 & df_raw$year <= 2024, ]
cat("   After NA + year filter: N =", nrow(df_raw), "\n")

# ─── [§ 3] OUTBREAK TREATMENT ───────────────────────────────────────────────
cat("\n[B] Outbreak treatment\n")
apply_winsorize <- function(df, pct=0.99){
  thr <- as.numeric(quantile(df$cases, pct, na.rm=TRUE))
  affected <- which(df$cases > thr)
  df$cases_orig <- df$cases
  df$cases <- pmin(df$cases, thr)
  df$despiked <- df$cases_orig > thr
  attr(df, "thr") <- thr
  attr(df, "n_affected") <- length(affected)
  attr(df, "affected_yw") <- paste(sprintf("%d-W%02d", df$year[affected], df$week[affected]),
                                    collapse=", ")
  df
}
df_orig <- df_raw
df_orig$cases_orig <- df_orig$cases
df_orig$despiked   <- FALSE
df_dspk <- apply_winsorize(df_raw, DESPIKE_PCT)
cat(sprintf("   De-spike: thr=%.2f, %d weeks winsorized\n",
            attr(df_dspk,"thr"), attr(df_dspk,"n_affected")))

make_subsets <- function(df){
  # v9 통일: COVID-onset boundary (2020 W08/W09) — 785/252 split (v1.3 manuscript 정합)
  list(
    Overall = df %>% arrange(year, week) %>% mutate(time_idx=row_number()),
    Pre     = df %>% filter(year < 2020 | (year == 2020 & week <= 8)) %>%
                arrange(year, week) %>% mutate(time_idx=row_number()),
    Post    = df %>% filter(year > 2020 | (year == 2020 & week >= 9)) %>%
                arrange(year, week) %>% mutate(time_idx=row_number())
  )
}
DATA_ALL <- list(Original=make_subsets(df_orig), Despiked=make_subsets(df_dspk))
for (ob in names(DATA_ALL))
  for (sb in names(DATA_ALL[[ob]]))
    cat(sprintf("   %s · %s: N=%d\n", ob, sb, nrow(DATA_ALL[[ob]][[sb]])))

# ─── [§ 4] HELPER FUNCTIONS ─────────────────────────────────────────────────
build_formula <- function(L, seas, k_time){
  rhs <- sprintf(paste0("s(avg_temp_lag%d, k=6) + s(humidity_lag%d, k=6) + ",
                         "s(pm10_lag%d, k=6) + s(precipitation_lag%d, k=6) + ",
                         "s(time_idx, k=%d)"),
                  L["temp"], L["humid"], L["pm10"], L["precip"], k_time)
  if (nzchar(seas)) rhs <- paste(rhs, "+", seas)
  as.formula(paste("cases ~", rhs))
}
SEAS <- list(None="", Annual="sin52+cos52",
              TwoHarm="sin52+cos52+sin26+cos26",
              CyclicSpln="s(week, bs='cc', k=8)")
make_corr <- function(name){
  switch(name, None=NULL, AR1=corAR1(form=~time_idx),
         ARMA11=corARMA(form=~time_idx, p=1, q=1),
         AR2=corARMA(form=~time_idx, p=2, q=0), NULL)
}
fit_gamm <- function(f, corr_obj, d, label=""){
  t0 <- Sys.time()
  res <- tryCatch({
    if (is.null(corr_obj)) m <- gamm(f, family=nb(), data=d, method="REML")
    else m <- gamm(f, correlation=corr_obj, family=nb(), data=d, method="REML")
    list(model=m, ok=TRUE, error=NA_character_)
  }, error=function(e) list(model=NULL, ok=FALSE, error=conditionMessage(e)))
  el <- as.numeric(difftime(Sys.time(), t0, units="secs"))
  cat(sprintf("    [%s] %.1fs %s\n", label, el,
              if (res$ok) "OK" else paste0("FAIL: ", substr(res$error,1,80))))
  res
}
eval_fit <- function(fit){
  if (!fit$ok) return(list(aic=NA, edf=NA, lb12=NA, lb26=NA, lb52=NA, rho=NA))
  m <- fit$model
  res <- tryCatch(residuals(m$lme, type="normalized"), error=function(e) NULL)
  if (is.null(res)) return(list(aic=NA, edf=NA, lb12=NA, lb26=NA, lb52=NA, rho=NA))
  rho <- tryCatch({
    cs <- m$lme$modelStruct$corStruct
    if (!is.null(cs)) as.numeric(coef(cs, unconstrained=FALSE))[1] else NA
  }, error=function(e) NA)
  list(aic=AIC(m$lme), edf=sum(summary(m$gam)$s.table[,"edf"]),
       lb12=Box.test(res, lag=12, type="Ljung-Box")$p.value,
       lb26=Box.test(res, lag=26, type="Ljung-Box")$p.value,
       lb52=Box.test(res, lag=52, type="Ljung-Box")$p.value,
       rho=if (is.numeric(rho)) round(rho,4) else NA)
}

# ─── [§ 5] STAGE A/B/C + Stage E ────────────────────────────────────────────
extract_pct1 <- function(fit, var, d, lag_col, sub_name, lag_used){
  na_row <- data.frame(subset=sub_name, variable=var, lag_used=lag_used,
                        pct=NA, lo95=NA, hi95=NA, z=NA, p=NA, stringsAsFactors=FALSE)
  if (is.null(fit) || isFALSE(fit$ok)) return(na_row)
  m <- fit$model; if (is.null(m)) return(na_row)
  numcols <- sapply(d, is.numeric)
  newd0 <- as.data.frame(lapply(d[, numcols, drop=FALSE],
                                  function(x) mean(x, na.rm=TRUE)))
  if (!"year" %in% names(newd0)) newd0$year <- mean(d$year)
  if (!"week" %in% names(newd0)) newd0$week <- 26
  newd1 <- newd0; newd1[[lag_col]] <- newd0[[lag_col]] + 1
  X0 <- tryCatch(predict(m$gam, newdata=newd0, type="lpmatrix"), error=function(e) NULL)
  X1 <- tryCatch(predict(m$gam, newdata=newd1, type="lpmatrix"), error=function(e) NULL)
  if (is.null(X0) || is.null(X1)) return(na_row)
  dvec <- X1 - X0
  beta <- coef(m$gam); V <- vcov(m$gam)
  logIRR <- as.numeric(dvec %*% beta)
  var_log <- as.numeric(dvec %*% V %*% t(dvec))
  if (!is.finite(var_log) || var_log < 0) return(na_row)
  se <- sqrt(var_log); z <- logIRR/se
  data.frame(subset=sub_name, variable=var, lag_used=lag_used,
             pct    = round((exp(logIRR)-1)*100, 2),
             lo95   = round((exp(logIRR-1.96*se)-1)*100, 2),
             hi95   = round((exp(logIRR+1.96*se)-1)*100, 2),
             z      = round(z,2),
             p      = round(2*(1-pnorm(abs(z))), 4),
             stringsAsFactors=FALSE)
}

run_stage_AB_C <- function(d, sname){
  cat(sprintf("\n  [%s] N=%d Stage A/B/C\n", sname, nrow(d)))
  tk <- TIME_K[[sname]]
  # Stage A
  stageA <- list()
  for (cn in names(SEAS)){
    f <- build_formula(LAGS$LONG, SEAS[[cn]], tk)
    fit <- fit_gamm(f, corAR1(form=~time_idx), d, sprintf("A.%s", cn))
    ev <- eval_fit(fit)
    stageA[[cn]] <- list(fit=fit, ev=ev, name=cn)
  }
  aics <- sapply(stageA, function(x) x$ev$aic)
  winA <- if (all(is.na(aics))) "Annual" else names(stageA)[which.min(aics)]
  cat(sprintf("    >> Stage A winner: %s\n", winA))
  # Stage B
  stageB <- list()
  for (cn in c("None","AR1","ARMA11","AR2")){
    f <- build_formula(LAGS$LONG, SEAS[[winA]], tk)
    fit <- fit_gamm(f, make_corr(cn), d, sprintf("B.%s", cn))
    ev <- eval_fit(fit)
    stageB[[cn]] <- list(fit=fit, ev=ev, name=cn)
  }
  ok <- sapply(stageB, function(x){
    !is.na(x$ev$aic) && !is.na(x$ev$lb12) && x$ev$lb12>0.05 &&
    !is.na(x$ev$lb26) && x$ev$lb26>0.05 &&
    !is.na(x$ev$lb52) && x$ev$lb52>0.05
  })
  if (any(ok)) winB <- names(stageB)[ok][which.min(sapply(stageB[ok], function(x) x$ev$aic))]
  else if (any(!sapply(stageB, function(x) is.na(x$ev$aic)))){
    aics_b <- sapply(stageB, function(x) x$ev$aic)
    winB <- names(stageB)[which.min(aics_b)]
  } else winB <- "AR1"
  cat(sprintf("    >> Stage B winner: %s\n", winB))
  # Stage C
  corr_obj <- make_corr(winB)
  f_long  <- build_formula(LAGS$LONG,  SEAS[[winA]], tk)
  f_short <- build_formula(LAGS$SHORT, SEAS[[winA]], tk)
  C_long  <- fit_gamm(f_long,  corr_obj, d, "C.long")
  C_short <- fit_gamm(f_short, corr_obj, d, "C.short")
  list(stageA=stageA, stageB=stageB, winA=winA, winB=winB,
        C_long=C_long, C_short=C_short, data=d)
}

run_stage_E <- function(stageC, d, sname, lag_type){
  L <- LAGS[[toupper(lag_type)]]
  fit <- if (lag_type=="long") stageC$C_long else stageC$C_short
  vars_meta <- list(
    list("Temperature (°C)",     sprintf("avg_temp_lag%d",      L["temp"]),  L["temp"]),
    list("Humidity (%)",         sprintf("humidity_lag%d",      L["humid"]), L["humid"]),
    list("PM10 (µg/m³)",        sprintf("pm10_lag%d",          L["pm10"]),  L["pm10"]),
    list("Precipitation (mm)",   sprintf("precipitation_lag%d", L["precip"]),L["precip"])
  )
  do.call(rbind, lapply(vars_meta, function(v)
    extract_pct1(fit, v[[1]], d, v[[2]], sname, v[[3]])))
}

# ─── [§ 6] MAIN FIT LOOP ────────────────────────────────────────────────────
FITS <- list()
for (ob in names(DATA_ALL)){
  cat(sprintf("\n###### OUTBREAK: %s ######\n", ob))
  FITS[[ob]] <- list()
  for (sb in names(DATA_ALL[[ob]])){
    FITS[[ob]][[sb]] <- run_stage_AB_C(DATA_ALL[[ob]][[sb]], sb)
  }
}
saveRDS(FITS, file.path(OUT_DIR, sprintf("NORO_v3_P08_FITS_%s.rds", STAMP)))
cat("[saved] intermediate FITS RDS\n")

stageE_all <- do.call(rbind, lapply(names(FITS), function(ob){
  do.call(rbind, lapply(names(FITS[[ob]]), function(sb){
    sc <- FITS[[ob]][[sb]]
    rbind(
      cbind(outbreak=ob, spec="LONG",  run_stage_E(sc, sc$data, sb, "long")),
      cbind(outbreak=ob, spec="SHORT", run_stage_E(sc, sc$data, sb, "short"))
    )
  }))
}))
stageE_all$outbreak <- ifelse(stageE_all$outbreak=="Despiked","De-spiked","Original")
cat("Stage E rows:", nrow(stageE_all), "\n")

# ─── [§ 7] SUPPLEMENTARY MODELS ─────────────────────────────────────────────
extract_slope <- function(ms, df_resid){
  sl_raw <- tryCatch(slope(ms), error=function(e) NULL)
  if (is.null(sl_raw)) return(NULL)
  sl <- if (is.list(sl_raw) && !is.data.frame(sl_raw)) sl_raw[[1]] else sl_raw
  if (is.null(sl) || nrow(sl)==0) return(NULL)
  cols <- colnames(sl)
  pick <- function(pats){
    for (p in pats){ h <- grep(p, cols, value=TRUE, ignore.case=TRUE)
      if (length(h)) return(as.numeric(sl[, h[1]])) }
    rep(NA_real_, nrow(sl))
  }
  est <- pick(c("^Est\\.?$","^Estimate$"))
  se  <- pick(c("^St\\.Err\\.?$","^Std\\.\\s*Err","^SE$"))
  lo  <- pick(c("CI.*lo","CI.*\\.l$","^lower$","low$"))
  hi  <- pick(c("CI.*up","CI.*\\.u$","^upper$","high$|^up$"))
  pv  <- pick(c("Pr\\(>","^p\\.?value$","^pval$"))
  if (all(is.na(lo)) && !all(is.na(se))) lo <- est - 1.96*se
  if (all(is.na(hi)) && !all(is.na(se))) hi <- est + 1.96*se
  if (all(is.na(pv)) && !all(is.na(se))){
    tv <- est/se
    pv <- if (!is.na(df_resid) && df_resid>0) 2*pt(-abs(tv), df=df_resid) else 2*(1-pnorm(abs(tv)))
  }
  data.frame(Est=est, SE=se, lo=lo, hi=hi, p=pv, stringsAsFactors=FALSE)
}
fit_temp_seg <- function(d, np=3, min_gap=1.0){
  sd <- d[!is.na(d$avg_temp_lag3),]; sd$log_cases <- log1p(sd$cases)
  m <- lm(log_cases ~ avg_temp_lag3, data=sd)
  bad <- function(ms){
    if (is.null(ms)) return(TRUE)
    bps <- tryCatch(sort(ms$psi[,"Est."]), error=function(e) NULL)
    if (is.null(bps) || length(bps)==0) return(TRUE)
    if (length(bps)>=2 && any(diff(bps)<min_gap)) return(TRUE)
    sl <- tryCatch(extract_slope(ms, ms$df.residual), error=function(e) NULL)
    if (is.null(sl)) return(TRUE)
    any(!is.finite(sl$Est) | abs(sl$Est) > log(10))
  }
  for (try_np in c(np, 2, 1)){
    cand <- tryCatch(suppressWarnings(segmented(m, seg.Z=~avg_temp_lag3, npsi=try_np)),
                      error=function(e) NULL)
    if (!bad(cand)){
      sl_df <- extract_slope(cand, cand$df.residual)
      return(list(model=cand, bps=cand$psi[,"Est."], slopes=sl_df, npsi=try_np))
    }
  }
  NULL
}

# Sec 2 — Temp segmented
cat("\n[G] Supplementary fits — Temp segmented\n")
sec2_list <- list()
for (ob in names(DATA_ALL))
  for (sb in c("Overall","Pre","Post")){
    cat(sprintf("  Temp seg %s %s\n", ob, sb))
    f <- fit_temp_seg(DATA_ALL[[ob]][[sb]], 3)
    if (is.null(f)) next
    sl <- f$slopes; n <- nrow(sl)
    bp_vec <- c(NA, round(f$bps,2))
    if (length(bp_vec)<n) bp_vec <- c(bp_vec, rep(NA, n-length(bp_vec)))
    sec2_list[[paste0(ob,sb)]] <- data.frame(
      outbreak = ifelse(ob=="Despiked","De-spiked","Original"),
      subset=sb, segment=sprintf("Seg %d", seq_len(n)),
      bp_above_C=bp_vec[seq_len(n)],
      pct   = round((exp(sl$Est)-1)*100, 2),
      pct_lo= round((exp(sl$lo)-1)*100, 2),
      pct_hi= round((exp(sl$hi)-1)*100, 2),
      p     = round(sl$p, 4), stringsAsFactors=FALSE)
  }
sec2 <- do.call(rbind, sec2_list)

# Sec 3 — GAMM smooth significance
cat("[G] Sec 3 — GAMM smooth terms\n")
sec3 <- do.call(rbind, lapply(names(FITS), function(ob){
  do.call(rbind, lapply(names(FITS[[ob]]), function(sb){
    do.call(rbind, lapply(c("long","short"), function(lt){
      obj <- if (lt=="long") FITS[[ob]][[sb]]$C_long else FITS[[ob]][[sb]]$C_short
      if (is.null(obj) || isFALSE(obj$ok)) return(NULL)
      s <- summary(obj$model$gam)$s.table
      if (is.null(s)) return(NULL)
      data.frame(outbreak=ifelse(ob=="Despiked","De-spiked","Original"),
                  subset=sb, spec=toupper(lt), term=rownames(s),
                  edf=round(s[,"edf"],3),
                  Fstat=round(s[,"F"],3),
                  p_value=round(s[,"p-value"],4),
                  stringsAsFactors=FALSE)
    }))
  }))
}))

# Sec 4 — Harmonic IRR
cat("[G] Sec 4 — Harmonic IRR\n")
fit_harmonic <- function(d, sub, spec, ob_lbl){
  L <- LAGS[[spec]]
  req <- c("cases", sprintf("avg_temp_lag%d", L["temp"]),
            sprintf("humidity_lag%d", L["humid"]),
            sprintf("pm10_lag%d", L["pm10"]),
            sprintf("precipitation_lag%d", L["precip"]),
            "sin52","cos52","sin26","cos26","time_idx")
  nd <- d[complete.cases(d[, req]),]
  f <- as.formula(sprintf(
    "cases ~ %s + %s + %s + %s + sin52+cos52+sin26+cos26 + ns(time_idx, df=%d)",
    req[2],req[3],req[4],req[5], ifelse(sub=="Post",5,20)))
  m <- tryCatch(glm.nb(f, data=nd), error=function(e) NULL)
  if (is.null(m)) return(NULL)
  s <- summary(m)$coefficients
  do.call(rbind, lapply(c("sin52","cos52","sin26","cos26"), function(tm){
    if (!tm %in% rownames(s)) return(NULL)
    r <- s[tm,]
    data.frame(outbreak=ob_lbl, subset=sub, spec=spec, term=tm,
                IRR=round(exp(r["Estimate"]),3),
                lo =round(exp(r["Estimate"]-1.96*r["Std. Error"]),3),
                hi =round(exp(r["Estimate"]+1.96*r["Std. Error"]),3),
                p  =round(r["Pr(>|z|)"],4), stringsAsFactors=FALSE)
  }))
}
sec4_list <- list()
for (ob in names(DATA_ALL))
  for (sp in c("LONG","SHORT"))
    for (sb in c("Overall","Pre","Post")){
      r <- fit_harmonic(DATA_ALL[[ob]][[sb]], sb, sp,
                          ifelse(ob=="Despiked","De-spiked","Original"))
      if (!is.null(r)) sec4_list[[length(sec4_list)+1]] <- r
    }
sec4 <- do.call(rbind, sec4_list)

# Sec 5 — Humidity lag 0-8
cat("[G] Sec 5 — Humidity lag 0-8\n")
fit_humid_lag <- function(d, sb, ob_lbl){
  do.call(rbind, lapply(0:8, function(L){
    v <- sprintf("humidity_lag%d", L)
    if (!v %in% names(d)) return(NULL)
    dat <- d[, c("cases", v,"sin52","cos52","sin26","cos26","time_idx")]
    names(dat)[2] <- "humid"
    dat <- dat[complete.cases(dat),]
    f <- tryCatch(glm.nb(cases ~ humid + sin52+cos52+sin26+cos26 +
                          ns(time_idx, df=ifelse(sb=="Post",5,20)), data=dat),
                    error=function(e) NULL)
    if (is.null(f)) return(NULL)
    s <- summary(f)$coefficients["humid",]
    data.frame(outbreak=ob_lbl, subset=sb, lag=L,
                IRR=round(exp(s["Estimate"]),4),
                lo =round(exp(s["Estimate"]-1.96*s["Std. Error"]),4),
                hi =round(exp(s["Estimate"]+1.96*s["Std. Error"]),4),
                p  =round(s["Pr(>|z|)"],4))
  }))
}
sec5_list <- list()
for (ob in names(DATA_ALL))
  for (sb in c("Overall","Pre","Post")){
    r <- fit_humid_lag(DATA_ALL[[ob]][[sb]], sb,
                          ifelse(ob=="Despiked","De-spiked","Original"))
    if (!is.null(r)) sec5_list[[length(sec5_list)+1]] <- r
  }
sec5 <- do.call(rbind, sec5_list)

# Sec 5b — DLNM
cat("[G] Sec 5b — DLNM\n")
build_dlnm <- function(d, sb){
  cb <- crossbasis(d$humidity_lag0, lag=c(0,8),
                   argvar=list(fun="ns", df=3),
                   arglag=list(fun="ns", df=3))
  m <- glm.nb(cases ~ cb + sin52+cos52+sin26+cos26 +
                ns(time_idx, df=ifelse(sb=="Post",5,20)), data=d)
  pr <- crosspred(cb, m, at=seq(45,90,by=5),
                  cen=median(d$humidity_lag0, na.rm=TRUE))
  list(cb=cb, model=m, pred=pr)
}
DLNMS <- list()
for (ob in names(DATA_ALL))
  for (sb in c("Overall","Pre","Post")){
    key <- paste0(ob,"_",sb)
    DLNMS[[key]] <- tryCatch(build_dlnm(DATA_ALL[[ob]][[sb]], sb),
                              error=function(e){ cat("DLNM FAIL",key,":",conditionMessage(e),"\n"); NULL })
  }
sec5b <- do.call(rbind, lapply(names(DLNMS), function(k){
  dd <- DLNMS[[k]]; if (is.null(dd)) return(NULL)
  pts <- strsplit(k, "_")[[1]]
  data.frame(outbreak=ifelse(pts[1]=="Despiked","De-spiked","Original"),
              subset=pts[2], humidity=dd$pred$predvar,
              cumul_RR=round(dd$pred$allRRfit,3),
              lo=round(dd$pred$allRRlow,3),
              hi=round(dd$pred$allRRhigh,3))
}))
lagresp <- do.call(rbind, lapply(names(DLNMS), function(k){
  dd <- DLNMS[[k]]; if (is.null(dd)) return(NULL)
  pts <- strsplit(k, "_")[[1]]
  do.call(rbind, lapply(c(60,70,80), function(h){
    i <- which(dd$pred$predvar==h); if (length(i)==0) return(NULL)
    data.frame(outbreak=ifelse(pts[1]=="Despiked","De-spiked","Original"),
                subset=pts[2], humid=h, lag=0:8,
                RR=round(dd$pred$matRRfit[i,],3),
                lo=round(dd$pred$matRRlow[i,],3),
                hi=round(dd$pred$matRRhigh[i,],3))
  }))
}))

# Sec 7 — Wind
cat("[G] Sec 7 — Wind\n")
fit_wind <- function(d, sb, ob_lbl){
  if (!"wind_speed_lag7" %in% names(d)) return(NULL)
  dat <- d[complete.cases(d[, c("cases","wind_speed_lag7","sin52","cos52","sin26","cos26","time_idx")]),]
  m <- tryCatch(glm.nb(cases ~ wind_speed_lag7 + sin52+cos52+sin26+cos26 +
                          ns(time_idx, df=ifelse(sb=="Post",5,20)), data=dat),
                  error=function(e) NULL)
  if (is.null(m)) return(NULL)
  s <- summary(m)$coefficients["wind_speed_lag7",]
  data.frame(outbreak=ob_lbl, subset=sb,
              IRR_per_1mps=round(exp(s["Estimate"]),3),
              lo=round(exp(s["Estimate"]-1.96*s["Std. Error"]),3),
              hi=round(exp(s["Estimate"]+1.96*s["Std. Error"]),3),
              p=round(s["Pr(>|z|)"],4), stringsAsFactors=FALSE)
}
sec7_list <- list()
for (ob in names(DATA_ALL))
  for (sb in c("Overall","Pre","Post")){
    r <- fit_wind(DATA_ALL[[ob]][[sb]], sb,
                  ifelse(ob=="Despiked","De-spiked","Original"))
    if (!is.null(r)) sec7_list[[length(sec7_list)+1]] <- r
  }
sec7 <- do.call(rbind, sec7_list)

# Sec 8 — Heatwave
cat("[G] Sec 8 — Heatwave\n")
fit_heat <- function(d, sb, ob_lbl){
  req <- c("cases","avg_temp_lag3","sin52","cos52","sin26","cos26","time_idx")
  d <- d[, req]
  d <- d[complete.cases(d) & is.finite(d$avg_temp_lag3) & is.finite(d$cases),]
  if (nrow(d) < 50) return(NULL)
  d$heat <- as.integer(d$avg_temp_lag3 > HEATWAVE_BP)
  if (sum(d$heat) < 10) return(NULL)
  rle_h <- rle(d$heat==1); ev <- rep(0,nrow(d)); pos <- 1
  for (i in seq_along(rle_h$lengths)){
    if (rle_h$values[i] && rle_h$lengths[i]>=2)
      ev[pos:(pos+rle_h$lengths[i]-1)] <- 1
    pos <- pos + rle_h$lengths[i]
  }
  d$heat_event <- ev
  if (mean(d$heat_event) < 0.005 || mean(d$heat_event) > 0.99) return(NULL)
  df_full <- min(20, max(4, floor(nrow(d)/15)))
  m <- tryCatch(glm.nb(cases ~ heat_event + sin52+cos52+sin26+cos26 +
                          ns(time_idx, df=df_full), data=d), error=function(e) NULL)
  if (is.null(m) || !"heat_event" %in% rownames(summary(m)$coefficients)) return(NULL)
  s <- summary(m)$coefficients["heat_event",]
  data.frame(outbreak=ob_lbl, subset=sb,
              N_used=nrow(d), N_heat_event_weeks=sum(d$heat_event),
              IRR=round(exp(s["Estimate"]),3),
              lo=round(exp(s["Estimate"]-1.96*s["Std. Error"]),3),
              hi=round(exp(s["Estimate"]+1.96*s["Std. Error"]),3),
              p=round(s["Pr(>|z|)"],4), stringsAsFactors=FALSE)
}
sec8_list <- list()
for (ob in names(DATA_ALL))
  for (sb in c("Overall","Pre","Post")){
    r <- fit_heat(DATA_ALL[[ob]][[sb]], sb,
                  ifelse(ob=="Despiked","De-spiked","Original"))
    if (!is.null(r)) sec8_list[[length(sec8_list)+1]] <- r
  }
sec8 <- do.call(rbind, sec8_list)

# Sec 9 — Stage B Diagnostics
cat("[G] Sec 9 — Diagnostics\n")
sec9 <- do.call(rbind, lapply(names(FITS), function(ob){
  do.call(rbind, lapply(names(FITS[[ob]]), function(sb){
    sc <- FITS[[ob]][[sb]]; win <- sc$winB
    ev <- sc$stageB[[win]]$ev
    data.frame(outbreak=ifelse(ob=="Despiked","De-spiked","Original"),
                subset=sb, winner=win,
                AIC=round(ev$aic,2),
                rho_AR1=ifelse(is.na(ev$rho),"—", as.character(round(ev$rho,4))),
                Ljung_lag12_p=round(ev$lb12,3),
                Ljung_lag26_p=round(ev$lb26,3),
                Ljung_lag52_p=round(ev$lb52,3),
                stringsAsFactors=FALSE)
  }))
}))

# ─── [§ 8] Fig 1c/2c/3c helper data ─────────────────────────────────────────
annual_met <- df_raw %>%
  mutate(period_lbl=ifelse(year<=2019, "Pre-COVID (2005-2019)", "Post-COVID (2020-2024)")) %>%
  group_by(year, period_lbl) %>%
  summarise(avg_temp=mean(avg_temp, na.rm=TRUE),
            humidity=mean(humidity, na.rm=TRUE),
            pm10=mean(pm10, na.rm=TRUE),
            precipitation=mean(precipitation, na.rm=TRUE), .groups="drop")

fit_temp_data <- list()
for (ob in names(DATA_ALL))
  for (sb in c("Overall","Pre","Post")){
    f <- fit_temp_seg(DATA_ALL[[ob]][[sb]], 3)
    if (is.null(f)) next
    d <- DATA_ALL[[ob]][[sb]]
    nx <- data.frame(avg_temp_lag3=seq(min(d$avg_temp_lag3, na.rm=TRUE),
                                          max(d$avg_temp_lag3, na.rm=TRUE), length=150))
    nx$pred <- predict(f$model, newdata=nx)
    nx$outbreak <- ifelse(ob=="Despiked","De-spiked","Original")
    nx$subset <- sb
    fit_temp_data[[length(fit_temp_data)+1]] <- nx
  }
fig2c_data <- do.call(rbind, fit_temp_data)

fig3c <- do.call(rbind, lapply(names(FITS), function(ob){
  do.call(rbind, lapply(names(FITS[[ob]]), function(sb){
    sc <- FITS[[ob]][[sb]]; obj <- sc$C_long
    if (is.null(obj) || isFALSE(obj$ok)) return(NULL)
    m_gam <- obj$model$gam; d <- sc$data
    newd <- data.frame(time_idx=seq(min(d$time_idx), max(d$time_idx), length=400),
      avg_temp_lag3=mean(d$avg_temp_lag3, na.rm=TRUE),
      humidity_lag7=mean(d$humidity_lag7, na.rm=TRUE),
      pm10_lag8=mean(d$pm10_lag8, na.rm=TRUE),
      precipitation_lag7=mean(d$precipitation_lag7, na.rm=TRUE))
    for (cc in c("sin52","cos52","sin26","cos26"))
      if (cc %in% names(d)) newd[[cc]] <- 0
    if ("week" %in% names(d)) newd$week <- 26
    pr <- tryCatch(predict(m_gam, newdata=newd, se.fit=TRUE, type="response"),
                    error=function(e) NULL)
    if (is.null(pr)) return(NULL)
    yr_min <- min(d$year); idx_off <- min(d$time_idx)
    newd$year <- yr_min + (newd$time_idx-idx_off)/52
    data.frame(outbreak=ifelse(ob=="Despiked","De-spiked","Original"),
                subset=sb, year=newd$year,
                fit=pr$fit, lo=pr$fit-1.96*pr$se.fit, hi=pr$fit+1.96*pr$se.fit)
  }))
}))

cat("\n[saved] all fits done. Building 4 sets...\n")

# ─── [§ 9] PER-SET BUILDERS ─────────────────────────────────────────────────
build_t1 <- function(ob_lbl){
  data_ob <- if (ob_lbl=="De-spiked") DATA_ALL$Despiked else DATA_ALL$Original
  case_col <- function(d) if ("cases_orig" %in% names(d)) d$cases_orig else d$cases
  fmt_n <- function(x) format(x, big.mark=",")
  fmt_md <- function(x) sprintf("%g (%g-%g)",
                                  round(median(x,na.rm=TRUE)),
                                  round(quantile(x,0.25,na.rm=TRUE)),
                                  round(quantile(x,0.75,na.rm=TRUE)))
  fmt_msd <- function(x) sprintf("%.1f (%.1f)", mean(x,na.rm=TRUE), sd(x,na.rm=TRUE))
  sb <- data_ob
  rows <- list()
  rows[["Period (years)"]] <- c("2005-2024","2005-2019","2020-2024")
  rows[["Number of weeks"]] <- sapply(sb, function(d) fmt_n(nrow(d)))
  rows[["── Norovirus surveillance ──"]] <- c("","","")
  rows[["  Total cases"]] <- sapply(sb, function(d) fmt_n(sum(case_col(d), na.rm=TRUE)))
  rows[["  Mean cases/wk"]] <- sapply(sb, function(d) sprintf("%.1f", mean(case_col(d), na.rm=TRUE)))
  rows[["  Median (IQR)"]] <- sapply(sb, function(d) fmt_md(case_col(d)))
  rows[["  Zero-week %"]] <- sapply(sb, function(d) sprintf("%.1f", 100*mean(case_col(d)==0, na.rm=TRUE)))
  rows[["  Max weekly cases"]] <- sapply(sb, function(d) fmt_n(max(case_col(d), na.rm=TRUE)))
  if (any(sapply(sb, function(d) "despiked" %in% names(d))))
    rows[["  Despiked (winsor)"]] <- sapply(sb, function(d) fmt_n(sum(d$despiked, na.rm=TRUE)))
  rows[["── Met covariates mean (SD) ──"]] <- c("","","")
  rows[["  Avg temp (°C)"]] <- sapply(sb, function(d) fmt_msd(d$avg_temp))
  rows[["  Humidity (%)"]] <- sapply(sb, function(d) fmt_msd(d$humidity))
  rows[["  Precip (mm/day)"]] <- sapply(sb, function(d) fmt_msd(d$precipitation))
  rows[["  PM10 (μg/m³)"]] <- sapply(sb, function(d) fmt_msd(d$pm10))
  data.frame(Characteristic=names(rows),
              Overall=sapply(rows,`[`,1),
              `Pre-COVID`=sapply(rows,`[`,2),
              `Post-COVID`=sapply(rows,`[`,3),
              check.names=FALSE, row.names=NULL, stringsAsFactors=FALSE)
}

hs_blue   <- createStyle(fgFill="#1F4E79", fontColour="#FFFFFF",
                          halign="center", textDecoration="bold", border="TopBottomLeftRight")
hs_yellow <- createStyle(fgFill="#FFF2CC", textDecoration="bold",
                          halign="left", indent=1, border="TopBottomLeftRight")
hs_band   <- createStyle(fgFill="#F2F2F2", border="TopBottomLeftRight",
                          halign="left", valign="center", wrapText=TRUE)
hs_data   <- createStyle(border="TopBottomLeftRight",
                          halign="center", valign="center", wrapText=TRUE)
hs_data_l <- createStyle(border="TopBottomLeftRight",
                          halign="left", valign="center", wrapText=TRUE)
hs_note   <- createStyle(fgFill="#FFFBE6", fontSize=10,
                          textDecoration="italic", wrapText=TRUE)
hs_title  <- createStyle(fontSize=12, textDecoration="bold")
hs_sub    <- createStyle(fontSize=10, textDecoration="italic", fontColour="#666666")

fmt_pct <- function(rec){
  p <- rec$p; if (is.na(p)) return("")
  s <- if (p<0.05) "★" else if (p<0.10) "†" else ""
  sprintf("%+.2f [%+.2f, %+.2f], p=%.3f %s", rec$pct, rec$lo95, rec$hi95, p, s)
}
fmt_pct_seg <- function(rec){
  p <- rec$p; if (is.na(p)) return("")
  s <- if (p<0.05) "★" else if (p<0.10) "†" else ""
  sprintf("%+.2f [%+.2f, %+.2f], p=%.3f %s", rec$pct, rec$pct_lo, rec$pct_hi, p, s)
}

write_set_xlsx <- function(s){
  lag_lbl <- s$lag; ob_lbl <- s$outbreak; set_lbl <- s$label
  fp <- file.path(OUT_DIR, sprintf("NORO_v3_%s_%s_%s_Tables_%s.xlsx",
                                    s$id, lag_lbl, gsub("-","",ob_lbl), STAMP))
  wb <- createWorkbook()
  addWorksheet(wb, "Table 1")
  tbl1 <- build_t1(ob_lbl)
  writeData(wb, "Table 1",
             sprintf("Table 1. Sample characteristics — %s", set_lbl),
             startRow=1, startCol=1)
  mergeCells(wb, "Table 1", cols=1:4, rows=1)
  addStyle(wb, "Table 1", hs_title, rows=1, cols=1)
  writeData(wb, "Table 1",
             "South Korea 2005–2024. Subsets: Overall (N=1,037) / Pre-COVID (N=777) / Post-COVID (N=260)",
             startRow=2, startCol=1)
  mergeCells(wb, "Table 1", cols=1:4, rows=2)
  addStyle(wb, "Table 1", hs_sub, rows=2, cols=1)
  writeData(wb, "Table 1", t(c("Characteristic","Overall","Pre-COVID","Post-COVID")),
             startRow=4, startCol=1, colNames=FALSE)
  addStyle(wb, "Table 1", hs_blue, rows=4, cols=1:4, gridExpand=TRUE)
  setRowHeights(wb, "Table 1", rows=4, heights=22)
  r <- 5; band <- FALSE
  for (i in seq_len(nrow(tbl1))){
    row <- tbl1[i,]
    ch <- row$Characteristic
    if (grepl("^──", ch)){
      writeData(wb, "Table 1", trimws(gsub("─","", ch)),
                  startRow=r, startCol=1)
      mergeCells(wb, "Table 1", cols=1:4, rows=r)
      addStyle(wb, "Table 1", hs_yellow, rows=r, cols=1:4, gridExpand=TRUE)
      setRowHeights(wb, "Table 1", rows=r, heights=18)
      band <- FALSE
    } else {
      writeData(wb, "Table 1",
                  t(c(row$Characteristic, row$Overall, row[["Pre-COVID"]], row[["Post-COVID"]])),
                  startRow=r, startCol=1, colNames=FALSE)
      style <- if (band) hs_band else hs_data
      addStyle(wb, "Table 1", hs_data_l, rows=r, cols=1)
      addStyle(wb, "Table 1", style, rows=r, cols=2:4, gridExpand=TRUE)
      band <- !band
    }
    r <- r+1
  }
  r <- r+1
  writeData(wb, "Table 1",
              sprintf("This set = %s.", set_lbl),
              startRow=r, startCol=1)
  mergeCells(wb, "Table 1", cols=1:4, rows=r)
  addStyle(wb, "Table 1", hs_note, rows=r, cols=1:4, gridExpand=TRUE)
  setColWidths(wb, "Table 1", cols=1:4, widths=c(42,20,20,20))
  freezePane(wb, "Table 1", firstActiveRow=5)

  addWorksheet(wb, "Table 2")
  writeData(wb, "Table 2",
              sprintf("Table 2. Environmental drivers — %s", set_lbl),
              startRow=1, startCol=1)
  mergeCells(wb, "Table 2", cols=1:5, rows=1); addStyle(wb, "Table 2", hs_title, rows=1, cols=1)
  writeData(wb, "Table 2",
              "★ p<0.05, † p<0.10. NB regression with sin/cos seasonality + ns(time_idx).",
              startRow=2, startCol=1)
  mergeCells(wb, "Table 2", cols=1:5, rows=2); addStyle(wb, "Table 2", hs_sub, rows=2, cols=1)
  writeData(wb, "Table 2",
              t(c("Predictor / Phase","Effect unit","Overall (N=1,037)",
                  "Pre-COVID (N=777)","Post-COVID (N=260)")),
              startRow=4, startCol=1, colNames=FALSE)
  addStyle(wb, "Table 2", hs_blue, rows=4, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 2", rows=4, heights=26)
  r <- 5
  writeData(wb, "Table 2",
              "1. Multivariable ZINB — linear effects (per-1u %change [95% CI])",
              startRow=r, startCol=1)
  mergeCells(wb, "Table 2", cols=1:5, rows=r); addStyle(wb, "Table 2", hs_yellow, rows=r, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 2", rows=r, heights=22); r <- r+1
  unit_lbl <- list("Temperature (°C)"="per +1°C","Humidity (%)"="per +1%",
                    "PM10 (µg/m³)"="per +1 µg/m³","Precipitation (mm)"="per +1 mm")
  sE_f <- stageE_all[stageE_all$outbreak==ob_lbl & stageE_all$spec==lag_lbl,]
  band <- FALSE
  for (v in c("Temperature (°C)","Humidity (%)","PM10 (µg/m³)","Precipitation (mm)")){
    rr <- sE_f[sE_f$variable==v,]
    if (nrow(rr)==0) next
    lag_v <- rr$lag_used[1]
    cells <- c(sprintf("%s (lag %d)", v, lag_v), unit_lbl[[v]])
    for (sb in c("Overall","Pre","Post")){
      rec <- rr[rr$subset==sb,]
      cells <- c(cells, if (nrow(rec)) fmt_pct(rec) else "")
    }
    writeData(wb, "Table 2", t(cells), startRow=r, startCol=1, colNames=FALSE)
    addStyle(wb, "Table 2", hs_data_l, rows=r, cols=1)
    addStyle(wb, "Table 2", if (band) hs_band else hs_data,
              rows=r, cols=2:5, gridExpand=TRUE)
    band <- !band; r <- r+1
  }
  writeData(wb, "Table 2", "2. Temperature segmented (lag 3 — same for LONG·SHORT)",
              startRow=r, startCol=1)
  mergeCells(wb, "Table 2", cols=1:5, rows=r); addStyle(wb, "Table 2", hs_yellow, rows=r, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 2", rows=r, heights=22); r <- r+1
  sec2_f <- sec2[sec2$outbreak==ob_lbl,]; band <- FALSE
  for (sb in c("Overall","Pre","Post")){
    sub_o <- sec2_f[sec2_f$subset==sb,]
    for (i in seq_len(nrow(sub_o))){
      rec <- sub_o[i,]
      bp <- rec$bp_above_C
      bp_str <- if (is.na(bp)) "start" else sprintf("%.1f°C", bp)
      cells <- c(sprintf("%s · %s (BP≥%s)", sb, rec$segment, bp_str), "per +1°C")
      val <- fmt_pct_seg(rec)
      for (sn in c("Overall","Pre","Post"))
        cells <- c(cells, if (sn==sb) val else "")
      writeData(wb, "Table 2", t(cells), startRow=r, startCol=1, colNames=FALSE)
      addStyle(wb, "Table 2", hs_data_l, rows=r, cols=1)
      addStyle(wb, "Table 2", if (band) hs_band else hs_data, rows=r, cols=2:5, gridExpand=TRUE)
      band <- !band; r <- r+1
    }
  }
  writeData(wb, "Table 2", sprintf("3. GAMM smooth term significance (%s lag)", lag_lbl),
              startRow=r, startCol=1)
  mergeCells(wb, "Table 2", cols=1:5, rows=r); addStyle(wb, "Table 2", hs_yellow, rows=r, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 2", rows=r, heights=22); r <- r+1
  sec3_f <- sec3[sec3$outbreak==ob_lbl & sec3$spec==lag_lbl,]
  terms_seen <- unique(sec3_f$term); band <- FALSE
  for (term in terms_seen){
    cells <- c(term, "smooth (edf, F, p)")
    for (sb in c("Overall","Pre","Post")){
      rec <- sec3_f[sec3_f$term==term & sec3_f$subset==sb,]
      if (nrow(rec)){
        p <- rec$p_value
        sig <- if (p<0.05) "★" else if (p<0.10) "†" else ""
        cells <- c(cells, sprintf("edf=%.2f, F=%.2f, p=%.3f %s", rec$edf, rec$Fstat, p, sig))
      } else cells <- c(cells, "")
    }
    writeData(wb, "Table 2", t(cells), startRow=r, startCol=1, colNames=FALSE)
    addStyle(wb, "Table 2", hs_data_l, rows=r, cols=1)
    addStyle(wb, "Table 2", if (band) hs_band else hs_data, rows=r, cols=2:5, gridExpand=TRUE)
    band <- !band; r <- r+1
  }
  writeData(wb, "Table 2", sprintf("4. Seasonal harmonic IRR (%s lag)", lag_lbl),
              startRow=r, startCol=1)
  mergeCells(wb, "Table 2", cols=1:5, rows=r); addStyle(wb, "Table 2", hs_yellow, rows=r, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 2", rows=r, heights=22); r <- r+1
  sec4_f <- sec4[sec4$outbreak==ob_lbl & sec4$spec==lag_lbl,]; band <- FALSE
  for (term in c("sin52","cos52","sin26","cos26")){
    cells <- c(term, "per cycle")
    for (sb in c("Overall","Pre","Post")){
      rec <- sec4_f[sec4_f$term==term & sec4_f$subset==sb,]
      if (nrow(rec)){
        p <- rec$p
        sig <- if (p<0.05) "★" else if (p<0.10) "†" else ""
        cells <- c(cells, sprintf("%.3f [%.3f, %.3f], p=%.3f %s", rec$IRR, rec$lo, rec$hi, p, sig))
      } else cells <- c(cells, "")
    }
    writeData(wb, "Table 2", t(cells), startRow=r, startCol=1, colNames=FALSE)
    addStyle(wb, "Table 2", hs_data_l, rows=r, cols=1)
    addStyle(wb, "Table 2", if (band) hs_band else hs_data, rows=r, cols=2:5, gridExpand=TRUE)
    band <- !band; r <- r+1
  }
  r <- r+1
  writeData(wb, "Table 2", sprintf("This set = %s.", set_lbl), startRow=r, startCol=1)
  mergeCells(wb, "Table 2", cols=1:5, rows=r)
  addStyle(wb, "Table 2", hs_note, rows=r, cols=1:5, gridExpand=TRUE)
  setColWidths(wb, "Table 2", cols=1:5, widths=c(34,20,28,28,28))
  freezePane(wb, "Table 2", firstActiveRow=5)

  addWorksheet(wb, "Table 3")
  writeData(wb, "Table 3", sprintf("Table 3. Supplementary detail — %s", set_lbl),
              startRow=1, startCol=1)
  mergeCells(wb, "Table 3", cols=1:5, rows=1); addStyle(wb, "Table 3", hs_title, rows=1, cols=1)
  writeData(wb, "Table 3",
              "Humidity lag profile · DLNM cumulative · Wind univariate · Heatwave detail · Model diagnostics.",
              startRow=2, startCol=1)
  mergeCells(wb, "Table 3", cols=1:5, rows=2); addStyle(wb, "Table 3", hs_sub, rows=2, cols=1)
  writeData(wb, "Table 3",
              t(c("Predictor / Phase","Effect unit","Overall","Pre-COVID","Post-COVID")),
              startRow=4, startCol=1, colNames=FALSE)
  addStyle(wb, "Table 3", hs_blue, rows=4, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 3", rows=4, heights=24)
  r <- 5
  writeData(wb, "Table 3", "5. Humidity — lag-specific IRR (univariate)",
              startRow=r, startCol=1)
  mergeCells(wb, "Table 3", cols=1:5, rows=r); addStyle(wb, "Table 3", hs_yellow, rows=r, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 3", rows=r, heights=22); r <- r+1
  sec5_f <- sec5[sec5$outbreak==ob_lbl,]; band <- FALSE
  for (lag in 0:8){
    cells <- c(sprintf("Humidity, lag %d", lag), "per +1%")
    for (sb in c("Overall","Pre","Post")){
      rec <- sec5_f[sec5_f$lag==lag & sec5_f$subset==sb,]
      if (nrow(rec)){
        p <- rec$p; sig <- if (p<0.05) "★" else if (p<0.10) "†" else ""
        cells <- c(cells, sprintf("%.3f [%.3f, %.3f], p=%.3f %s", rec$IRR, rec$lo, rec$hi, p, sig))
      } else cells <- c(cells, "")
    }
    writeData(wb, "Table 3", t(cells), startRow=r, startCol=1, colNames=FALSE)
    addStyle(wb, "Table 3", hs_data_l, rows=r, cols=1)
    addStyle(wb, "Table 3", if (band) hs_band else hs_data, rows=r, cols=2:5, gridExpand=TRUE)
    band <- !band; r <- r+1
  }
  writeData(wb, "Table 3", "5b. DLNM cumulative RR (sum lag 0-8) at selected humidity %",
              startRow=r, startCol=1)
  mergeCells(wb, "Table 3", cols=1:5, rows=r); addStyle(wb, "Table 3", hs_yellow, rows=r, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 3", rows=r, heights=22); r <- r+1
  sec5b_f <- sec5b[sec5b$outbreak==ob_lbl,]; band <- FALSE
  for (h in c(55,60,65,70,75,80,85)){
    cells <- c(sprintf("Cumulative RR @ RH=%d%%", h), "vs median RH")
    for (sb in c("Overall","Pre","Post")){
      rec <- sec5b_f[sec5b_f$humidity==h & sec5b_f$subset==sb,]
      if (nrow(rec))
        cells <- c(cells, sprintf("%.3f [%.3f, %.3f]", rec$cumul_RR, rec$lo, rec$hi))
      else cells <- c(cells, "")
    }
    writeData(wb, "Table 3", t(cells), startRow=r, startCol=1, colNames=FALSE)
    addStyle(wb, "Table 3", hs_data_l, rows=r, cols=1)
    addStyle(wb, "Table 3", if (band) hs_band else hs_data, rows=r, cols=2:5, gridExpand=TRUE)
    band <- !band; r <- r+1
  }
  writeData(wb, "Table 3", "7. Wind speed univariate (lag 7) — dropped in main multivariable",
              startRow=r, startCol=1)
  mergeCells(wb, "Table 3", cols=1:5, rows=r); addStyle(wb, "Table 3", hs_yellow, rows=r, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 3", rows=r, heights=22); r <- r+1
  sec7_f <- sec7[sec7$outbreak==ob_lbl,]
  cells <- c("Wind speed, lag 7", "per +1 m/s")
  for (sb in c("Overall","Pre","Post")){
    rec <- sec7_f[sec7_f$subset==sb,]
    if (nrow(rec)){
      p <- rec$p; sig <- if (p<0.05) "★" else if (p<0.10) "†" else ""
      cells <- c(cells, sprintf("%.3f [%.3f, %.3f], p=%.3f %s", rec$IRR_per_1mps, rec$lo, rec$hi, p, sig))
    } else cells <- c(cells, "")
  }
  writeData(wb, "Table 3", t(cells), startRow=r, startCol=1, colNames=FALSE)
  addStyle(wb, "Table 3", hs_data_l, rows=r, cols=1)
  addStyle(wb, "Table 3", hs_data, rows=r, cols=2:5, gridExpand=TRUE); r <- r+1
  writeData(wb, "Table 3", "8. Heatwave events — IRR for ≥2 consecutive weeks > 26.4°C",
              startRow=r, startCol=1)
  mergeCells(wb, "Table 3", cols=1:5, rows=r); addStyle(wb, "Table 3", hs_yellow, rows=r, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 3", rows=r, heights=22); r <- r+1
  sec8_f <- sec8[sec8$outbreak==ob_lbl,]
  cells <- c("Heat event (≥2 consec wks > 26.4°C)", "event sign")
  for (sb in c("Overall","Pre","Post")){
    rec <- sec8_f[sec8_f$subset==sb,]
    if (nrow(rec)){
      p <- rec$p; sig <- if (p<0.05) "★" else if (p<0.10) "†" else ""
      cells <- c(cells, sprintf("IRR %.3f [%.3f, %.3f], p=%.4f %s\nN=%d/%d",
                                  rec$IRR, rec$lo, rec$hi, p, sig,
                                  rec$N_heat_event_weeks, rec$N_used))
    } else cells <- c(cells, "")
  }
  writeData(wb, "Table 3", t(cells), startRow=r, startCol=1, colNames=FALSE)
  setRowHeights(wb, "Table 3", rows=r, heights=40)
  addStyle(wb, "Table 3", hs_data_l, rows=r, cols=1)
  addStyle(wb, "Table 3", hs_data, rows=r, cols=2:5, gridExpand=TRUE); r <- r+1
  writeData(wb, "Table 3", "9. Autocorrelation diagnostics — Stage B winner + Ljung-Box",
              startRow=r, startCol=1)
  mergeCells(wb, "Table 3", cols=1:5, rows=r); addStyle(wb, "Table 3", hs_yellow, rows=r, cols=1:5, gridExpand=TRUE)
  setRowHeights(wb, "Table 3", rows=r, heights=22); r <- r+1
  sec9_f <- sec9[sec9$outbreak==ob_lbl,]
  metric_rows <- list(c("Stage B winner","winner"), c("AIC","AIC"), c("ρ̂ (corAR1)","rho_AR1"),
                       c("Ljung-Box lag 12 p","Ljung_lag12_p"),
                       c("Ljung-Box lag 26 p","Ljung_lag26_p"),
                       c("Ljung-Box lag 52 p","Ljung_lag52_p"))
  band <- FALSE
  for (mr in metric_rows){
    cells <- c(mr[1], "")
    for (sb in c("Overall","Pre","Post")){
      rec <- sec9_f[sec9_f$subset==sb,]
      v <- if (nrow(rec)) rec[[mr[2]]] else ""
      cells <- c(cells, as.character(v))
    }
    writeData(wb, "Table 3", t(cells), startRow=r, startCol=1, colNames=FALSE)
    addStyle(wb, "Table 3", hs_data_l, rows=r, cols=1)
    addStyle(wb, "Table 3", if (band) hs_band else hs_data, rows=r, cols=2:5, gridExpand=TRUE)
    band <- !band; r <- r+1
  }
  r <- r+1
  writeData(wb, "Table 3",
              sprintf("This set = %s. Section 6 (Seasonal split DLNM) excluded due to time-series discontinuity in season subsets.",
                      set_lbl),
              startRow=r, startCol=1)
  mergeCells(wb, "Table 3", cols=1:5, rows=r)
  addStyle(wb, "Table 3", hs_note, rows=r, cols=1:5, gridExpand=TRUE)
  setColWidths(wb, "Table 3", cols=1:5, widths=c(38,16,28,28,28))
  freezePane(wb, "Table 3", firstActiveRow=5)

  saveWorkbook(wb, fp, overwrite=TRUE)
  fp
}

ggtheme <- theme_bw(base_size=10) + theme(
  panel.grid.minor=element_blank(),
  strip.background=element_rect(fill="grey92", color=NA),
  plot.title=element_text(size=11, face="bold"),
  legend.position="bottom")

write_set_pdf <- function(s){
  fp <- file.path(OUT_DIR, sprintf("NORO_v3_%s_%s_%s_Figures_%s.pdf",
                                    s$id, s$lag, gsub("-","",s$outbreak), STAMP))
  ob <- s$outbreak
  data_ob <- if (ob=="De-spiked") DATA_ALL$Despiked else DATA_ALL$Original
  d_all <- data_ob$Overall
  if (!"date_w" %in% names(d_all))
    d_all$date_w <- as.Date(sprintf("%d-01-01", d_all$year)) + (d_all$week-1)*7
  d_all$period <- ifelse(d_all$year<=2019,"Pre","Post")
  ycol <- if (ob=="De-spiked") "cases" else "cases_orig"

  p1a <- ggplot(d_all, aes(x=date_w, y=.data[[ycol]], color=period)) +
    geom_line(linewidth=0.4, alpha=0.85) +
    {if (ob=="De-spiked")
       geom_point(data=d_all[d_all$despiked==TRUE,], aes(y=.data[[ycol]]),
                  color="#A32D2D", size=1.5, shape=4, stroke=1)
    } +
    scale_color_manual(values=c(Pre="#185FA5", Post="#A32D2D")) +
    ggtheme + theme(legend.position="top") +
    labs(title=sprintf("a. Weekly norovirus surveillance — %s cases",
                        ifelse(ob=="De-spiked","winsorized","original")),
         x="Year", y="Weekly cases", color=NULL)
  seas <- d_all %>% group_by(period, week) %>%
    summarise(mean_cases=mean(.data[[ycol]], na.rm=TRUE), .groups="drop")
  p1b <- ggplot(seas, aes(x=week, y=mean_cases, color=period)) +
    geom_line(linewidth=1) +
    scale_color_manual(values=c(Pre="#185FA5", Post="#A32D2D")) +
    scale_x_continuous(breaks=c(1,13,26,39,52)) +
    ggtheme +
    labs(title="b. Seasonal pattern — bipeak", x="Week", y="Mean cases", color=NULL)
  am <- annual_met %>%
    pivot_longer(c(avg_temp,humidity,pm10,precipitation),
                  names_to="variable", values_to="value")
  am$variable <- factor(am$variable,
    levels=c("avg_temp","humidity","pm10","precipitation"),
    labels=c("Avg temp (°C)","Humidity (%)","PM10 (μg/m³)","Precip (mm/day)"))
  p1c <- ggplot(am, aes(x=year, y=value, color=period_lbl)) +
    geom_line(linewidth=0.8) + geom_point(size=1.5) +
    facet_wrap(~variable, nrow=1, scales="free_y") +
    scale_color_manual(values=COL_PER) +
    ggtheme + theme(legend.position="none") +
    labs(title="c. Met covariates — annual means, Pre vs Post-COVID",
         x="Year", y=NULL)
  fig1 <- p1a/p1b/p1c +
    plot_annotation(title=sprintf("Figure 1. Temporal patterns — %s", s$label),
                    theme=theme(plot.title=element_text(size=13, face="bold"))) +
    plot_layout(heights=c(1, 1, 1.1))

  hl <- sec5[sec5$outbreak==ob,]
  hl$sig <- ifelse(hl$p<0.05,"p<0.05", ifelse(hl$p<0.10,"p<0.10","NS"))
  p2a <- ggplot(hl, aes(x=factor(lag), y=IRR, color=subset, shape=subset)) +
    geom_hline(yintercept=1, linetype="dashed", color="grey50") +
    geom_errorbar(aes(ymin=lo, ymax=hi),
                   position=position_dodge(width=0.6), width=0.25) +
    geom_point(position=position_dodge(width=0.6), size=2.5) +
    scale_color_manual(values=COL_SUB) +
    scale_shape_manual(values=SHAPE_SUB) +
    ggtheme +
    labs(title="a. Humidity lag 0–8 IRR", x="Lag (weeks)",
         y="IRR per 1% humidity", color=NULL, shape=NULL)

  lr <- lagresp[lagresp$outbreak==ob & lagresp$humid==70,]
  p2b <- ggplot(lr, aes(x=lag, y=RR, color=subset, fill=subset)) +
    geom_hline(yintercept=1, linetype="dashed", color="grey50") +
    geom_ribbon(aes(ymin=lo, ymax=hi), alpha=0.15, color=NA) +
    geom_line(linewidth=1) +
    scale_color_manual(values=COL_SUB) + scale_fill_manual(values=COL_SUB) +
    ggtheme +
    labs(title="b. DLNM humidity-response (at RH=70%)",
         x="Lag (weeks)", y="RR vs RH=70%", color=NULL, fill=NULL)

  f2c <- fig2c_data[fig2c_data$outbreak==ob,]
  p2c <- ggplot(f2c, aes(x=avg_temp_lag3, y=pred, color=subset)) +
    geom_line(linewidth=1) +
    scale_color_manual(values=COL_SUB) +
    ggtheme +
    labs(title="c. Temperature segmented", x="avg_temp_lag3 (°C)",
         y="log(cases+1)", color=NULL)

  hw <- sec8[sec8$outbreak==ob,]
  p2d <- ggplot(hw, aes(x=IRR, y=subset, color=subset, shape=subset)) +
    geom_vline(xintercept=1, linetype="dashed", color="grey50") +
    geom_errorbarh(aes(xmin=lo, xmax=hi), height=0.3, linewidth=0.9) +
    geom_point(size=4.5, stroke=1.5,
                aes(fill=ifelse(p<0.05, as.character(subset), "white"))) +
    scale_color_manual(values=COL_SUB) +
    scale_fill_manual(values=c(COL_SUB, white="white"), guide="none") +
    scale_shape_manual(values=SHAPE_SUB) +
    scale_x_log10() +
    geom_text(aes(label=sprintf(" IRR %.2f [%.2f, %.2f]\n p=%.4f%s N=%d/%d",
                                 IRR, lo, hi, p,
                                 ifelse(p<0.05," ★", ifelse(p<0.10," †","")),
                                 N_heat_event_weeks, N_used)),
                hjust=0, nudge_x=0.05, size=2.8, color="#222") +
    ggtheme + theme(legend.position="none") +
    labs(title="d. Heatwave events — IRR for ≥2 consec wks > 26.4°C ★",
         x="IRR per heatwave event (log scale, 95% CI)", y=NULL)
  fig2 <- (p2a + p2b) / (p2c + p2d) +
    plot_annotation(title=sprintf("Figure 2. Non-linear environmental effects — %s", s$label),
                    theme=theme(plot.title=element_text(size=13, face="bold")))

  e_f <- stageE_all[stageE_all$outbreak==ob & stageE_all$spec==s$lag,]
  e_f$variable <- factor(e_f$variable,
                          levels=c("Temperature (°C)","Humidity (%)","PM10 (µg/m³)","Precipitation (mm)"))
  p3a <- ggplot(e_f, aes(x=pct, y=variable, color=subset, shape=subset)) +
    geom_vline(xintercept=0, linetype="dashed", color="grey50") +
    geom_errorbarh(aes(xmin=lo95, xmax=hi95),
                   position=position_dodge(width=0.6), height=0.2) +
    geom_point(position=position_dodge(width=0.6), size=3,
                aes(fill=ifelse(p<0.05, as.character(subset), "white"))) +
    scale_color_manual(values=COL_SUB) + scale_shape_manual(values=SHAPE_SUB) +
    scale_fill_manual(values=c(COL_SUB, white="white"), guide="none") +
    ggtheme +
    labs(title="a. Multivariable %change forest — Overall (■) · Pre (●) · Post (▲), filled = p<0.05",
         x="% change per +1 unit [95% CI]", y=NULL, color=NULL, shape=NULL)
  hp <- sec4[sec4$outbreak==ob & sec4$spec==s$lag,]
  hp$term <- factor(hp$term, levels=c("sin52","cos52","sin26","cos26"))
  p3b <- ggplot(hp, aes(x=IRR, y=term, color=subset, shape=subset)) +
    geom_vline(xintercept=1, linetype="dashed", color="grey50") +
    geom_errorbarh(aes(xmin=lo, xmax=hi),
                   position=position_dodge(width=0.6), height=0.2) +
    geom_point(position=position_dodge(width=0.6), size=3,
                aes(fill=ifelse(p<0.05, as.character(subset), "white"))) +
    scale_color_manual(values=COL_SUB) + scale_shape_manual(values=SHAPE_SUB) +
    scale_fill_manual(values=c(COL_SUB, white="white"), guide="none") +
    scale_x_log10() + ggtheme +
    labs(title="b. Seasonal harmonic IRR", x="IRR per harmonic (log scale)",
         y=NULL, color=NULL, shape=NULL)
  tr <- fig3c[fig3c$outbreak==ob & fig3c$subset %in% c("Pre","Post"),]
  p3c <- ggplot(tr, aes(x=year, y=fit, color=subset, fill=subset)) +
    geom_ribbon(aes(ymin=lo, ymax=hi), alpha=0.2, color=NA) +
    geom_line(linewidth=1) +
    scale_color_manual(values=COL_SUB) + scale_fill_manual(values=COL_SUB) +
    ggtheme +
    labs(title="c. Long-term trend s(time_idx) — Pre/Post",
         x="Year", y="Predicted weekly cases", color=NULL, fill=NULL)
  fig3 <- p3a / p3b / p3c +
    plot_annotation(title=sprintf("Figure 3. COVID era restructuring — %s", s$label),
                    theme=theme(plot.title=element_text(size=13, face="bold")))

  pdf(fp, width=13, height=11)
  print(fig1); print(fig2); print(fig3)
  dev.off()
  fp
}

# ─── [§ 10] 4 SETS BUILD LOOP ───────────────────────────────────────────────
cat("\n========================= BUILDING 4 SETS =========================\n")
for (s in SETS){
  cat(sprintf("\n>>> %s (%s · %s)\n", s$id, s$lag, s$outbreak))
  xlsx_fp <- write_set_xlsx(s)
  cat(sprintf("   [Tables] %s\n", basename(xlsx_fp)))
  pdf_fp  <- write_set_pdf(s)
  cat(sprintf("   [Figures] %s\n", basename(pdf_fp)))
}

cat("\n========================= ALL DONE =========================\n")
cat("Outputs in:", OUT_DIR, "\n")
for (s in SETS){
  cat(sprintf("  Set %s (%s · %s):\n", substr(s$id,4,4), s$lag, s$outbreak))
  cat(sprintf("    - NORO_v3_%s_%s_%s_Tables_%s.xlsx\n",
              s$id, s$lag, gsub("-","",s$outbreak), STAMP))
  cat(sprintf("    - NORO_v3_%s_%s_%s_Figures_%s.pdf\n",
              s$id, s$lag, gsub("-","",s$outbreak), STAMP))
}


# ─── [§ 10.5+] SUPPLEMENT G1-G11 + Visualization (v9 — 검증된 코드 inline) ──
cat("\n========================= G1-G11 + VISUALIZATION (v9) =========================\n")
cat("v9: SUPPLEMENT 검증된 코드 inline — NORO Set 2 LONG Despiked main\n\n")

# ─── PACKAGES ───────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  for (.p in c("pscl","dlnm","ggplot2","scales","patchwork")) {
    if (!requireNamespace(.p, quietly=TRUE))
      try(install.packages(.p, repos="https://cran.rstudio.com/"), silent=TRUE)
    suppressWarnings(library(.p, character.only=TRUE))
  }
})
# v9 BUG C FIX: circular auto-install (NORO G5 Watson U²)
if (!requireNamespace("circular", quietly=TRUE))
  try(install.packages("circular", repos="https://cran.rstudio.com/"), silent=TRUE)

# ─── SETUP — NORO LONG main spec ───────────────────────────────────────────
# v9: COVID-onset boundary (week≤8 / week≥9) → 785/252 split — v1.3 manuscript 정합
d_main <- DATA_ALL$Despiked$Overall
d_main$period <- factor(ifelse(d_main$year < 2020 | (d_main$year == 2020 & d_main$week <= 8),
                                "Pre", "Post"), levels=c("Pre","Post"))
d_pre  <- d_main[d_main$period == "Pre",  ]; d_pre$time_idx  <- seq_len(nrow(d_pre))
d_post <- d_main[d_main$period == "Post", ]; d_post$time_idx <- seq_len(nrow(d_post))

# NORO LONG spec — humid lag 7, pm10 lag 8, precip lag 7
f_zinb_noro <- as.formula(paste("cases ~ avg_temp_lag3 + humidity_lag7 + pm10_lag8 +",
                                 "precipitation_lag7 + sin52 + cos52 + sin26 + cos26 + time_idx",
                                 "| 1"))
vars_g4_noro <- c("avg_temp_lag3","humidity_lag7","pm10_lag8","precipitation_lag7")

cat(sprintf("d_main: N=%d, d_pre: N=%d, d_post: N=%d\n",
            nrow(d_main), nrow(d_pre), nrow(d_post)))

# ─── G1 — Period × Climate interactions (3 vars: temp, RH, PM10) ───────────
cat("\n## [G1] Period × Climate (temp/RH/PM10) interaction tests (GAMM, AR1, Set 2 LONG)\n\n```text\n")

build_g1_form <- function(int_var = NULL) {
  base <- "s(time_idx, k=30) + sin52 + cos52"
  vars <- c("avg_temp_lag3", "humidity_lag7", "pm10_lag8", "precipitation_lag7")
  parts <- character()
  for (v in vars) {
    if (!is.null(int_var) && v == int_var) {
      parts <- c(parts, sprintf("s(%s, by=period, k=6) + period", v))
    } else {
      parts <- c(parts, sprintf("s(%s, k=6)", v))
    }
  }
  as.formula(paste("cases ~", paste(c(base, parts), collapse=" + ")))
}

m0_g1 <- tryCatch(
  suppressMessages(suppressWarnings(
    gamm(build_g1_form(NULL), correlation=corAR1(form=~time_idx),
         family=nb(), data=d_main, method="REML"))),
  error=function(e){cat("G1 null ERR:", conditionMessage(e), "\n"); NULL})
if (!is.null(m0_g1)) cat(sprintf("Null model AIC: %.2f\n\n", AIC(m0_g1$lme)))

for (vv in c("avg_temp_lag3", "humidity_lag7", "pm10_lag8")) {
  cat(sprintf("--- G1.%s — period × %s ---\n", sub("_lag.*", "", vv), vv))
  m_int <- tryCatch(
    suppressMessages(suppressWarnings(
      gamm(build_g1_form(vv), correlation=corAR1(form=~time_idx),
           family=nb(), data=d_main, method="REML"))),
    error=function(e){cat("  ERR:", conditionMessage(e), "\n"); NULL})
  if (!is.null(m_int) && !is.null(m0_g1)) {
    aic_i <- AIC(m_int$lme)
    cat(sprintf("  Interaction AIC : %.2f\n", aic_i))
    cat(sprintf("  ΔAIC (int-null) : %+.2f\n", aic_i - AIC(m0_g1$lme)))
    st <- summary(m_int$gam)$s.table
    print(data.frame(term=rownames(st), edf=round(st[,"edf"],3),
                      F=round(st[,"F"],3), p.value=signif(st[,"p-value"],4),
                      sig=ifelse(st[,"p-value"]<0.05,"*",ifelse(st[,"p-value"]<0.10,".",""))),
          row.names=FALSE)
    cat("\n")
  }
}
cat("```\n")

# ─── G2 — Heatwave threshold sensitivity (NORO 24-28°C) ───────────────────
cat("\n## [G2] Heatwave threshold sensitivity (NORO 24/25/26/26.4/27/28 °C)\n\n```text\n")
make_hw_event <- function(d, bp_c) {
  d <- d[order(d$year, d$week), ]
  hot <- d$avg_temp > bp_c
  rl <- rle(hot); in_event <- logical(nrow(d)); pos <- 1
  for (i in seq_along(rl$lengths)) {
    if (rl$values[i] && rl$lengths[i] >= 2)
      in_event[pos:(pos + rl$lengths[i] - 1)] <- TRUE
    pos <- pos + rl$lengths[i]
  }
  in_event
}
hw_res <- data.frame(threshold_C=c(24.0,25.0,26.0,26.4,27.0,28.0), n_event_wk=NA_integer_,
                      IRR=NA_real_, CI_lo=NA_real_, CI_hi=NA_real_, p_val=NA_real_)
for (i in seq_len(nrow(hw_res))) {
  bp <- hw_res$threshold_C[i]
  d_main$hw <- make_hw_event(d_main, bp)
  hw_res$n_event_wk[i] <- sum(d_main$hw)
  if (hw_res$n_event_wk[i] >= 10 && hw_res$n_event_wk[i] <= nrow(d_main) - 10) {
    fit <- tryCatch(glm.nb(cases ~ hw + sin52 + cos52 + sin26 + cos26 + time_idx, data=d_main),
                     error=function(e) NULL)
    if (!is.null(fit)) {
      s <- summary(fit)$coef
      b <- s["hwTRUE","Estimate"]; se <- s["hwTRUE","Std. Error"]
      hw_res$IRR[i] <- exp(b); hw_res$CI_lo[i] <- exp(b-1.96*se)
      hw_res$CI_hi[i] <- exp(b+1.96*se); hw_res$p_val[i] <- s["hwTRUE","Pr(>|z|)"]
    }
  }
}
print(hw_res, row.names=FALSE, digits=3)
cat("```\n")

# ─── G3 — ZINB bootstrap (4 climate vars, v7 BUG A: integer) ──────────────
cat("\n## [G3] ZINB block bootstrap β stability (R=200, 4 climate vars)\n\n```text\n")
set.seed(20260528)
n_boot <- 200; bs <- 52; nrow_d <- nrow(d_main); nb_b <- ceiling(nrow_d/bs)
boot_mat <- matrix(NA_real_, nrow=n_boot, ncol=length(vars_g4_noro),
                    dimnames=list(NULL, vars_g4_noro))
n_fail <- 0
for (b in seq_len(n_boot)) {
  st_i <- sample(seq_len(nrow_d - bs + 1), nb_b, replace=TRUE)
  ix <- unlist(lapply(st_i, function(s) s:(s + bs - 1)))
  ix <- ix[ix <= nrow_d][seq_len(nrow_d)]
  db <- d_main[ix, ]; db$time_idx <- seq_len(nrow(db))
  db$cases <- as.integer(round(db$cases))  # v7 FIX
  fit <- tryCatch(suppressWarnings(zeroinfl(f_zinb_noro, data=db, dist="negbin")),
                   error=function(e) NULL)
  if (!is.null(fit)) {
    cc <- coef(fit, model="count")
    for (v in vars_g4_noro) boot_mat[b, v] <- cc[v]
  } else {
    n_fail <- n_fail + 1
  }
  if (b %% 50 == 0) cat(sprintf("  boot %d/%d (fail %d)\n", b, n_boot, n_fail))
}
boot_pct <- (exp(boot_mat) - 1) * 100
boot_summary <- data.frame(
  Variable=vars_g4_noro,
  Mean_pct=round(apply(boot_pct, 2, mean, na.rm=TRUE), 3),
  SD_pct=round(apply(boot_pct, 2, sd, na.rm=TRUE), 3),
  CI2.5=round(apply(boot_pct, 2, quantile, 0.025, na.rm=TRUE), 3),
  Median=round(apply(boot_pct, 2, quantile, 0.500, na.rm=TRUE), 3),
  CI97.5=round(apply(boot_pct, 2, quantile, 0.975, na.rm=TRUE), 3),
  N_valid=apply(boot_pct, 2, function(x) sum(!is.na(x)))
)
print(boot_summary, row.names=FALSE)
cat(sprintf("\nTotal ZINB failures: %d / %d\n", n_fail, n_boot))
cat("```\n")

# ─── G4 — ZINB Pre/Post Z-test (4 climate vars, integer FIX) ──────────────
cat("\n## [G4] ZINB Pre vs Post β formal contrast (4 climate vars)\n\n```text\n")
d_pre$cases  <- as.integer(round(d_pre$cases))
d_post$cases <- as.integer(round(d_post$cases))
fit_zinb_sub <- function(d) {
  fit <- suppressWarnings(zeroinfl(f_zinb_noro, data=d, dist="negbin"))
  summary(fit)$coefficients$count[vars_g4_noro, ]
}
s_pre  <- tryCatch(fit_zinb_sub(d_pre),  error=function(e){cat("Pre ERR:",conditionMessage(e),"\n"); NULL})
s_post <- tryCatch(fit_zinb_sub(d_post), error=function(e){cat("Post ERR:",conditionMessage(e),"\n"); NULL})
if (!is.null(s_pre) && !is.null(s_post)) {
  contrast <- data.frame(
    Variable=vars_g4_noro,
    Pre_pct=round((exp(s_pre[,"Estimate"])-1)*100, 3),
    Pre_SE=round(s_pre[,"Std. Error"], 4),
    Post_pct=round((exp(s_post[,"Estimate"])-1)*100, 3),
    Post_SE=round(s_post[,"Std. Error"], 4)
  )
  contrast$diff_log <- round(s_post[,"Estimate"] - s_pre[,"Estimate"], 4)
  contrast$SE_diff  <- round(sqrt(s_post[,"Std. Error"]^2 + s_pre[,"Std. Error"]^2), 4)
  contrast$Z        <- round(contrast$diff_log/contrast$SE_diff, 3)
  contrast$p_two    <- round(2*(1-pnorm(abs(contrast$Z))), 4)
  contrast$Sig      <- ifelse(contrast$p_two < 0.05, "*", ifelse(contrast$p_two < 0.10, ".", ""))
  print(contrast, row.names=FALSE)
}
cat("```\n")

# ─── G5 — Seasonality shift quantification (NORO 헤드라인 검증) ────────────
cat("\n## [G5] Seasonality shift quantification — NORO 헤드라인 검증\n\n")
cat("Peak ISO week / Center of mass / Mean vector length / Watson U² test\n\n```text\n")

d_orig_all <- DATA_ALL$Original$Overall
d_orig_all$period <- factor(ifelse(d_orig_all$year < 2020 |
                                     (d_orig_all$year == 2020 & d_orig_all$week <= 8),
                                    "Pre", "Post"), levels = c("Pre", "Post"))

seas_pre <- aggregate(cases_orig ~ week, d_orig_all[d_orig_all$period == "Pre", ],
                       mean, na.rm=TRUE)
seas_post <- aggregate(cases_orig ~ week, d_orig_all[d_orig_all$period == "Post", ],
                        mean, na.rm=TRUE)
names(seas_pre)[2] <- "Pre_mean"
names(seas_post)[2] <- "Post_mean"
seas_tbl <- merge(data.frame(week=1:52), merge(seas_pre, seas_post, by="week", all=TRUE),
                   by="week", all.x=TRUE)
cat("--- Weekly mean cases by ISO week (Pre vs Post) ---\n")
print(seas_tbl, row.names=FALSE, digits=2)

peak_pre  <- seas_tbl$week[which.max(seas_tbl$Pre_mean)]
peak_post <- seas_tbl$week[which.max(seas_tbl$Post_mean)]
cat(sprintf("\n--- Peak ISO week ---\n"))
cat(sprintf("  Pre  peak week : %d (mean = %.2f cases)\n",
            peak_pre, max(seas_tbl$Pre_mean, na.rm=TRUE)))
cat(sprintf("  Post peak week : %d (mean = %.2f cases)\n",
            peak_post, max(seas_tbl$Post_mean, na.rm=TRUE)))
cat(sprintf("  Naive shift    : %d weeks (Post - Pre)\n", peak_post - peak_pre))

to_rad <- function(w) 2*pi*(w-1)/52
to_week <- function(a) ((a / (2*pi)) * 52) %% 52 + 1
circ_mean <- function(w, weights) {
  a <- to_rad(w)
  s <- sum(weights * sin(a), na.rm=TRUE)
  c <- sum(weights * cos(a), na.rm=TRUE)
  to_week(atan2(s, c))
}
mvl_calc <- function(w, weights) {
  a <- to_rad(w)
  s <- sum(weights * sin(a), na.rm=TRUE)
  c <- sum(weights * cos(a), na.rm=TRUE)
  W <- sum(weights, na.rm=TRUE)
  sqrt(s^2 + c^2) / W
}

com_pre  <- circ_mean(seas_tbl$week, seas_tbl$Pre_mean)
com_post <- circ_mean(seas_tbl$week, seas_tbl$Post_mean)
cat(sprintf("\n--- Center of mass (circular weighted mean) ---\n"))
cat(sprintf("  Pre  COM : %.1f\n", com_pre))
cat(sprintf("  Post COM : %.1f\n", com_post))
shift_com <- (com_post - com_pre) %% 52
if (shift_com > 26) shift_com <- shift_com - 52
cat(sprintf("  COM shift: %.1f weeks\n", shift_com))

mvl_pre  <- mvl_calc(seas_tbl$week, seas_tbl$Pre_mean)
mvl_post <- mvl_calc(seas_tbl$week, seas_tbl$Post_mean)
cat(sprintf("\n--- Mean vector length (0=uniform, 1=single peak) ---\n"))
cat(sprintf("  Pre  MVL : %.3f\n", mvl_pre))
cat(sprintf("  Post MVL : %.3f\n", mvl_post))

if (requireNamespace("circular", quietly=TRUE)) {
  suppressPackageStartupMessages(library(circular))
  cat("\n--- Watson U² test (Pre vs Post distribution) ---\n")
  reps_pre  <- rep(seas_tbl$week, pmax(round(seas_tbl$Pre_mean * 10), 0))
  reps_post <- rep(seas_tbl$week, pmax(round(seas_tbl$Post_mean * 10), 0))
  cp <- circular(to_rad(reps_pre),  units="radians")
  cq <- circular(to_rad(reps_post), units="radians")
  ws <- tryCatch(watson.two.test(cp, cq), error=function(e) NULL)
  if (!is.null(ws)) print(ws)
} else {
  cat("\n[skip] circular package not available — Watson test omitted.\n")
}
cat("```\n")

# ─── G6 — Lag profile ──────────────────────────────────────────────────────
cat("\n## [G6] 4 climate vars × lag 0-8 univariate IRR\n\n```text\n")
g6_vars_meta <- list(avg_temp="°C", humidity="%", pm10="μg/m³", precipitation="mm")
g6_all <- list()
for (vn in names(g6_vars_meta)) {
  cat(sprintf("\n--- G6.%s (per +1 %s) ---\n", vn, g6_vars_meta[[vn]]))
  lag_tbl <- data.frame(Lag=0:8, Overall_IRR=NA, Overall_CI95=NA, Overall_p=NA,
                         Pre_IRR=NA, Pre_CI95=NA, Pre_p=NA,
                         Post_IRR=NA, Post_CI95=NA, Post_p=NA)
  for (lag_i in 0:8) {
    var_col <- sprintf("%s_lag%d", vn, lag_i)
    if (!var_col %in% names(d_main)) next
    for (sb in c("Overall","Pre","Post")) {
      d_use <- switch(sb, Overall=d_main, Pre=d_pre, Post=d_post)
      d_use$x_use <- d_use[[var_col]]
      fit <- tryCatch(suppressWarnings(glm.nb(cases ~ x_use + sin52+cos52+sin26+cos26+time_idx, data=d_use)),
                       error=function(e) NULL)
      if (!is.null(fit) && "x_use" %in% rownames(summary(fit)$coef)) {
        s <- summary(fit)$coef
        b <- s["x_use","Estimate"]; se <- s["x_use","Std. Error"]
        lag_tbl[lag_i+1, paste0(sb,"_IRR")]  <- round(exp(b), 4)
        lag_tbl[lag_i+1, paste0(sb,"_CI95")] <- sprintf("[%.4f, %.4f]", exp(b-1.96*se), exp(b+1.96*se))
        lag_tbl[lag_i+1, paste0(sb,"_p")]    <- signif(s["x_use","Pr(>|z|)"], 3)
      }
    }
  }
  print(lag_tbl, row.names=FALSE)
  g6_all[[vn]] <- lag_tbl
}
g6_out <- do.call(rbind, lapply(names(g6_all), function(vn){
  df <- g6_all[[vn]]; df$Variable <- vn; df[, c("Variable", setdiff(names(df), "Variable"))]
}))
write.csv(g6_out, file.path(OUT_DIR, sprintf("NORO_v3_G6_lag_profile_%s.csv", STAMP)), row.names=FALSE)
cat("```\n")

# ─── G7 — Spearman ─────────────────────────────────────────────────────────
cat("\n## [G7] Spearman correlation matrix\n\n```text\n")
sp_vars <- intersect(c("cases","avg_temp","humidity","pm10","precipitation","wind_speed"), names(d_main))
sp_data <- d_main[, sp_vars, drop=FALSE]
sp_mat <- cor(sp_data, method="spearman", use="pairwise.complete.obs")
sp_p <- matrix(NA_real_, length(sp_vars), length(sp_vars), dimnames=list(sp_vars, sp_vars))
for (i in seq_along(sp_vars)) for (j in seq_along(sp_vars)) {
  if (i != j) {
    tst <- tryCatch(suppressWarnings(cor.test(sp_data[[i]], sp_data[[j]], method="spearman", exact=FALSE)), error=function(e) NULL)
    if (!is.null(tst)) sp_p[i,j] <- tst$p.value
  }
}
cat("Spearman ρ:\n"); print(round(sp_mat, 3))
cat("\np-values:\n"); print(signif(sp_p, 3))
g7_long <- expand.grid(Var1=sp_vars, Var2=sp_vars, stringsAsFactors=FALSE)
g7_long$rho <- as.vector(sp_mat); g7_long$p <- as.vector(sp_p)
write.csv(g7_long, file.path(OUT_DIR, sprintf("NORO_v3_G7_spearman_%s.csv", STAMP)), row.names=FALSE)
cat("```\n")

# ─── G8 — GAMM smooth curves (★ C_long for NORO + BUG B FIX) ──────────────
cat("\n## [G8] GAMM smooth curves data export\n\n```text\n")
extract_smooth_data <- function(gam_obj, var_name, n_grid=100) {
  if (is.null(gam_obj) || !var_name %in% names(gam_obj$model)) return(NULL)
  vr <- range(gam_obj$model[[var_name]], na.rm=TRUE)
  if (any(!is.finite(vr))) return(NULL)
  g_vals <- seq(vr[1], vr[2], length.out=n_grid)
  base_row <- gam_obj$model[1,,drop=FALSE]
  for (cn in names(base_row)) if (is.numeric(base_row[[cn]])) base_row[[cn]] <- median(gam_obj$model[[cn]], na.rm=TRUE)
  nd <- base_row[rep(1,length(g_vals)),,drop=FALSE]; nd[[var_name]] <- g_vals
  pred <- tryCatch(predict(gam_obj, newdata=nd, type="terms", se.fit=TRUE), error=function(e) NULL)
  if (is.null(pred)) return(NULL)
  sm_col <- grep(paste0("\\b", var_name, "\\b"), colnames(pred$fit), value=TRUE)
  if (length(sm_col) == 0) return(NULL)
  sm_col <- sm_col[1]
  data.frame(x=g_vals, fit=pred$fit[,sm_col], se=pred$se.fit[,sm_col],
             rr_lo=exp(pred$fit[,sm_col]-1.96*pred$se.fit[,sm_col]),
             rr=exp(pred$fit[,sm_col]),
             rr_hi=exp(pred$fit[,sm_col]+1.96*pred$se.fit[,sm_col]))
}
g8_all <- list()
cli_vars <- c("avg_temp_lag3","humidity_lag7","pm10_lag8","precipitation_lag7")
for (sb in c("Overall","Pre","Post")) {
  fit_obj <- FITS$Despiked[[sb]]$C_long  # NORO uses LONG main
  gam_obj <- fit_obj$model$gam
  if (is.null(gam_obj)) gam_obj <- fit_obj$gam
  if (is.null(gam_obj)) { cat(sprintf("  G8 skip %s\n", sb)); next }
  for (vn in cli_vars) {
    sd <- extract_smooth_data(gam_obj, vn, n_grid=100)
    if (!is.null(sd)) { sd$subset <- sb; sd$variable <- vn; g8_all[[paste(sb,vn,sep="__")]] <- sd }
  }
}
if (length(g8_all) > 0) {
  g8_df <- do.call(rbind, g8_all)
  write.csv(g8_df, file.path(OUT_DIR, sprintf("NORO_v3_G8_smooth_curves_%s.csv", STAMP)), row.names=FALSE)
  cat(sprintf("Smooth curves: %d rows × %d combos\n", nrow(g8_df), length(g8_all)))
} else {
  g8_df <- NULL
  cat("G8 — no smooth curves extracted\n")
}
cat("```\n")

# ─── G9 — Best single lag forest ───────────────────────────────────────────
cat("\n## [G9] Best single lag forest data export\n\n```text\n")
best_lag_df <- data.frame()
for (vn in names(g6_all)) {
  df <- g6_all[[vn]]
  for (sb in c("Overall","Pre","Post")) {
    pcol <- paste0(sb,"_p"); icol <- paste0(sb,"_IRR"); ccol <- paste0(sb,"_CI95")
    if (all(is.na(df[[pcol]]))) next
    best_i <- which.min(df[[pcol]])
    best_lag_df <- rbind(best_lag_df, data.frame(Variable=vn, Subset=sb,
                                                   BestLag=df$Lag[best_i],
                                                   IRR=df[[icol]][best_i],
                                                   CI95=df[[ccol]][best_i],
                                                   p_value=df[[pcol]][best_i]))
  }
}
print(best_lag_df, row.names=FALSE)
write.csv(best_lag_df, file.path(OUT_DIR, sprintf("NORO_v3_G9_best_lag_forest_%s.csv", STAMP)), row.names=FALSE)
cat("```\n")

# ─── G10 — DLNM cumulative (NORO LONG adjust_vars) ──────────────────────────
cat("\n## [G10] DLNM cumulative lag\n\n```text\n")
g10_dlnm_table <- function(d_use, var_name, lag_max=8, adjust_vars=NULL) {
  if (!var_name %in% names(d_use)) return(NULL)
  x_vec <- d_use[[var_name]]
  if (any(is.na(x_vec))) return(NULL)
  cb <- tryCatch(crossbasis(x_vec, lag=c(0,lag_max), argvar=list(fun="lin"), arglag=list(fun="integer")), error=function(e) NULL)
  if (is.null(cb)) return(NULL)
  rhs <- "cb + sin52 + cos52 + sin26 + cos26 + time_idx"
  if (!is.null(adjust_vars)) {
    av <- intersect(adjust_vars, names(d_use))
    if (length(av) > 0) rhs <- paste(rhs, "+", paste(av, collapse=" + "))
  }
  fit <- tryCatch(suppressWarnings(glm.nb(as.formula(paste("cases ~", rhs)), data=d_use)), error=function(e) NULL)
  if (is.null(fit)) return(NULL)
  pred <- tryCatch(crosspred(cb, fit, at=1, cen=0, cumul=TRUE), error=function(e) NULL)
  if (is.null(pred)) return(NULL)
  data.frame(Lag=0:lag_max,
              Single_pct=(as.vector(pred$matRRfit[1,])-1)*100,
              Single_CI_lo=(as.vector(pred$matRRlow[1,])-1)*100,
              Single_CI_hi=(as.vector(pred$matRRhigh[1,])-1)*100,
              Cumul_pct=(as.vector(pred$cumRRfit[1,])-1)*100,
              Cumul_CI_lo=(as.vector(pred$cumRRlow[1,])-1)*100,
              Cumul_CI_hi=(as.vector(pred$cumRRhigh[1,])-1)*100)
}
# NORO LONG spec adjust_vars
g10_specs <- list(
  list(var="avg_temp",      adj=c("humidity_lag7","pm10_lag8","precipitation_lag7")),
  list(var="humidity",      adj=c("avg_temp_lag3","pm10_lag8","precipitation_lag7")),
  list(var="pm10",          adj=c("avg_temp_lag3","humidity_lag7","precipitation_lag7")),
  list(var="precipitation", adj=c("avg_temp_lag3","humidity_lag7","pm10_lag8"))
)
g10_all <- list()
for (spec in g10_specs) {
  for (sb in c("Overall","Pre","Post")) {
    d_use <- switch(sb, Overall=d_main, Pre=d_pre, Post=d_post)
    res <- g10_dlnm_table(d_use, spec$var, lag_max=8, adjust_vars=spec$adj)
    if (!is.null(res)) {
      res$Variable <- spec$var; res$Subset <- sb
      g10_all[[paste(spec$var, sb, sep="__")]] <- res
    }
  }
}
if (length(g10_all) > 0) {
  g10_df <- do.call(rbind, g10_all)
  g10_df <- g10_df[, c("Variable","Subset","Lag","Single_pct","Single_CI_lo","Single_CI_hi","Cumul_pct","Cumul_CI_lo","Cumul_CI_hi")]
  write.csv(g10_df, file.path(OUT_DIR, sprintf("NORO_v3_G10_dlnm_cumulative_%s.csv", STAMP)), row.names=FALSE)
  cat(sprintf("G10 saved: %d rows\n", nrow(g10_df)))
} else {
  g10_df <- NULL
}
cat("```\n")

# ─── G9b — Best cumulative lag ──────────────────────────────────────────────
cat("\n## [G9b] Best CUMULATIVE lag forest\n\n```text\n")
best_cum_df <- data.frame()
if (length(g10_all) > 0) {
  for (key in names(g10_all)) {
    df <- g10_all[[key]]
    df$sig_cum <- !is.na(df$Cumul_CI_lo) & !is.na(df$Cumul_CI_hi) & sign(df$Cumul_CI_lo) == sign(df$Cumul_CI_hi)
    cands <- if (any(df$sig_cum, na.rm=TRUE)) df[df$sig_cum,] else df
    if (nrow(cands) == 0) next
    best_i <- which.max(abs(cands$Cumul_pct))
    best_cum_df <- rbind(best_cum_df, data.frame(
      Variable=unique(df$Variable), Subset=unique(df$Subset),
      BestCumLag=cands$Lag[best_i], Cumul_pct=round(cands$Cumul_pct[best_i],3),
      CI_lo=round(cands$Cumul_CI_lo[best_i],3), CI_hi=round(cands$Cumul_CI_hi[best_i],3),
      Significant=cands$sig_cum[best_i]))
  }
}
print(best_cum_df, row.names=FALSE)
write.csv(best_cum_df, file.path(OUT_DIR, sprintf("NORO_v3_G9b_best_cumlag_forest_%s.csv", STAMP)), row.names=FALSE)
cat("```\n")

# ─── G11 — Full summary statistics (v8 BUG FIX) ─────────────────────────────
cat("\n## [G11] Full summary statistics (Mean/SD/Min/P25/P50/P75/Max)\n\n```text\n")
g11_vars <- intersect(c("cases","avg_temp","humidity","precipitation","wind_speed","pm10"), names(d_main))
g11_summary <- function(d, lbl) {
  out <- data.frame(
    Subset    = character(),
    Variable  = character(),
    N         = integer(),
    Mean      = double(), SD = double(),
    Min       = double(), P25 = double(), P50 = double(), P75 = double(), Max = double(),
    stringsAsFactors = FALSE
  )
  for (v in g11_vars) {
    x <- d[[v]]; x <- x[!is.na(x)]
    if (length(x) == 0) next
    qs <- quantile(x, c(0.25, 0.50, 0.75))
    out <- rbind(out, data.frame(
      Subset = lbl, Variable = v, N = length(x),
      Mean = round(mean(x), 3), SD = round(sd(x), 3),
      Min  = round(min(x), 3), P25 = round(qs[1], 3),
      P50  = round(qs[2], 3), P75 = round(qs[3], 3), Max = round(max(x), 3),
      stringsAsFactors = FALSE
    ))
  }
  out
}
d_orig_for_g11 <- DATA_ALL$Original$Overall
d_orig_for_g11$period <- factor(ifelse(d_orig_for_g11$year < 2020 |
  (d_orig_for_g11$year == 2020 & d_orig_for_g11$week <= 8), "Pre", "Post"), levels=c("Pre","Post"))
g11_all <- rbind(
  g11_summary(d_orig_for_g11,                                  "Overall (Original)"),
  g11_summary(d_orig_for_g11[d_orig_for_g11$period == "Pre",  ], "Pre (Original)"),
  g11_summary(d_orig_for_g11[d_orig_for_g11$period == "Post", ], "Post (Original)")
)
print(g11_all, row.names=FALSE)
write.csv(g11_all, file.path(OUT_DIR, sprintf("NORO_v3_G11_summary_stats_%s.csv", STAMP)), row.names=FALSE)
cat("```\n")

# ─── VISUALIZATION — Fig 0, S1, S2, S3 ──────────────────────────────────────
cat("\n## [Visualization]\n\n")
fig_theme <- theme_bw(base_size=11) + theme(
  panel.grid.minor=element_blank(), panel.grid.major.x=element_blank(),
  strip.background=element_rect(fill="grey90", color=NA), strip.text=element_text(face="bold"),
  legend.position="bottom",
  plot.title=element_text(face="bold", size=13), plot.subtitle=element_text(color="grey40", size=10))
col_sub <- c(Overall="grey30", Pre="#185FA5", Post="#A32D2D")
fill_sub <- c(Overall="grey60", Pre="#185FA5", Post="#A32D2D")

# Fig 0 — 6 panel time series (NORO 26.4°C heatwave line)
cat("```text\n[Fig 0] 6-panel time series...\n")
fig0_make_panel <- function(d, y_col, ylab, color="#333333", show_x=FALSE, label_letter="a", hline_y=NA) {
  d$y_use <- d[[y_col]]
  p <- ggplot(d, aes(x=year + (week-1)/52, y=y_use)) +
    geom_line(color=color, linewidth=0.35) +
    geom_vline(xintercept=2020 + 8/52, linetype="dashed", color="grey50") +
    labs(title=sprintf("(%s) %s", label_letter, ylab), x=if (show_x) "Year" else NULL, y=ylab) +
    theme_bw(base_size=9) +
    theme(plot.title=element_text(face="bold", size=9), panel.grid.minor=element_blank())
  if (!is.na(hline_y)) p <- p + geom_hline(yintercept=hline_y, linetype="dotted", color="red")
  if (!show_x) p <- p + theme(axis.text.x=element_blank(), axis.title.x=element_blank())
  p
}
d_ts <- d_orig_for_g11
p_a <- fig0_make_panel(d_ts, "cases_orig",    "Weekly NORO cases",       "#A32D2D", FALSE, "a")
p_b <- fig0_make_panel(d_ts, "avg_temp",      "Mean temperature (deg C)","#D95F02", FALSE, "b", hline_y=26.4)
p_c <- fig0_make_panel(d_ts, "humidity",      "Relative humidity (%)",   "#1B9E77", FALSE, "c")
p_d <- fig0_make_panel(d_ts, "precipitation", "Precipitation (mm/day)",  "#185FA5", FALSE, "d")
p_e <- NULL
if ("wind_speed" %in% names(d_ts)) p_e <- fig0_make_panel(d_ts, "wind_speed", "Wind speed (m/s)", "#7570B3", FALSE, "e")
p_f <- fig0_make_panel(d_ts, "pm10",          "PM10 (ug/m3)",            "#666666", TRUE,  "f")
panels <- list(p_a, p_b, p_c, p_d, p_e, p_f); panels <- panels[!sapply(panels, is.null)]
fig0 <- Reduce(`/`, panels) + plot_annotation(
  title="Figure 0. Weekly time-series, 2005-2024",
  subtitle="NORO v3 - COVID-19 onset (2020 W09) - 26.4 deg C heatwave reference")
ggsave(file.path(OUT_DIR, sprintf("NORO_v3_Fig_0_timeseries_%s.pdf", STAMP)), fig0, width=10, height=13, units="in")
ggsave(file.path(OUT_DIR, sprintf("NORO_v3_Fig_0_timeseries_%s.png", STAMP)), fig0, width=10, height=13, units="in", dpi=200)
cat("  [saved] Fig 0\n```\n")

# Fig S1
cat("\n```text\n[Fig S1] Best cumulative lag forest...\n")
if (nrow(best_cum_df) > 0) {
  fs1_df <- best_cum_df
  fs1_df$Significant <- as.character(fs1_df$Significant)
  fs1_df$Variable <- factor(fs1_df$Variable,
    levels=c("avg_temp","humidity","pm10","precipitation"),
    labels=c("Temperature","Humidity","PM10","Precipitation"))
  fs1_df$Subset <- factor(fs1_df$Subset, levels=c("Overall","Pre","Post"))
  fs1_df$lab_lag <- sprintf("lag %d", fs1_df$BestCumLag)
  fig_s1 <- ggplot(fs1_df, aes(x=Variable, y=Cumul_pct, ymin=CI_lo, ymax=CI_hi, color=Subset, shape=Significant)) +
    geom_hline(yintercept=0, linetype="dashed", color="grey50") +
    geom_pointrange(position=position_dodge(0.6), size=0.7, fatten=2.5) +
    geom_text(aes(label=lab_lag), position=position_dodge(0.6), vjust=-1.0, size=2.6, show.legend=FALSE) +
    scale_color_manual(values=col_sub) + scale_shape_manual(values=c("TRUE"=16,"FALSE"=1)) +
    labs(title="Figure S1. Best cumulative lag effect by variable",
         subtitle=sprintf("NORO v3 - 2005-2024 (n=%d weeks)", nrow(d_main)),
         x=NULL, y="% change per +1 unit, cumulative (95% CI)") + fig_theme
  ggsave(file.path(OUT_DIR, sprintf("NORO_v3_Fig_S1_best_cumlag_%s.pdf", STAMP)), fig_s1, width=10, height=6)
  ggsave(file.path(OUT_DIR, sprintf("NORO_v3_Fig_S1_best_cumlag_%s.png", STAMP)), fig_s1, width=10, height=6, dpi=200)
  cat("  [saved] Fig S1\n")
}
cat("```\n")

# Fig S2 (NORO LONG lag labels)
cat("\n```text\n[Fig S2] Smooth curves...\n")
if (!is.null(g8_df) && nrow(g8_df) > 0) {
  fs2_df <- g8_df
  fs2_df$variable_label <- factor(fs2_df$variable,
    levels=c("avg_temp_lag3","humidity_lag7","pm10_lag8","precipitation_lag7"),
    labels=c("Temperature (lag 3)","Humidity (lag 7)","PM10 (lag 8)","Precipitation (lag 7)"))
  fs2_df$subset <- factor(fs2_df$subset, levels=c("Overall","Pre","Post"))
  fig_s2 <- ggplot(fs2_df, aes(x=x, y=rr, color=subset, fill=subset)) +
    geom_ribbon(aes(ymin=rr_lo, ymax=rr_hi), alpha=0.18, color=NA) +
    geom_line(linewidth=0.85) + geom_hline(yintercept=1, linetype="dashed", color="grey50") +
    scale_color_manual(values=col_sub) + scale_fill_manual(values=fill_sub) +
    facet_wrap(~variable_label, scales="free_x", ncol=2) +
    labs(title="Figure S2. GAMM smooth exposure-response curves",
         subtitle="NORO v3 - Set 2 LONG Despiked",
         x="Climate variable value", y="Relative Risk (95% CI)") + fig_theme
  ggsave(file.path(OUT_DIR, sprintf("NORO_v3_Fig_S2_smooth_curves_%s.pdf", STAMP)), fig_s2, width=12, height=9)
  ggsave(file.path(OUT_DIR, sprintf("NORO_v3_Fig_S2_smooth_curves_%s.png", STAMP)), fig_s2, width=12, height=9, dpi=200)
  cat("  [saved] Fig S2\n")
} else {
  cat("  Fig S2 skipped (g8_df empty)\n")
}
cat("```\n")

# Fig S3
cat("\n```text\n[Fig S3] DLNM heatmap...\n")
if (!is.null(g10_df) && nrow(g10_df) > 0) {
  fs3_df <- g10_df
  fs3_df$Variable <- factor(fs3_df$Variable,
    levels=c("avg_temp","humidity","pm10","precipitation"),
    labels=c("Temperature","Humidity","PM10","Precipitation"))
  fs3_df$Subset <- factor(fs3_df$Subset, levels=c("Overall","Pre","Post"))
  fig_s3 <- ggplot(fs3_df, aes(x=Lag, y=Variable, fill=Cumul_pct)) +
    geom_tile(color="white", linewidth=0.3) +
    geom_text(aes(label=sprintf("%+.1f", Cumul_pct)), size=2.7, color="black") +
    scale_fill_gradient2(low="#185FA5", mid="white", high="#A32D2D", midpoint=0, name="% change") +
    scale_x_continuous(breaks=0:8) + facet_wrap(~Subset, nrow=1) +
    labs(title="Figure S3. DLNM cumulative effect heatmap", x="Lag (weeks)", y=NULL) + fig_theme +
    theme(panel.grid=element_blank())
  ggsave(file.path(OUT_DIR, sprintf("NORO_v3_Fig_S3_dlnm_heatmap_%s.pdf", STAMP)), fig_s3, width=14, height=5)
  ggsave(file.path(OUT_DIR, sprintf("NORO_v3_Fig_S3_dlnm_heatmap_%s.png", STAMP)), fig_s3, width=14, height=5, dpi=200)
  cat("  [saved] Fig S3\n")
}
cat("```\n")

cat("\n========================= G1-G11 + G5 + VIZ DONE (NORO v9) =========================\n")


# ─── [§ 11] FOOTER ──────────────────────────────────────────────────────────
cat("\n[DONE] NORO TRUE SINGLE FILE 실행 완료.\n")
cat("[on.exit] sink 안전 닫기 + md 푸터 처리됨.\n")
# =============================================================================


# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  PART 12 — PEER-REVIEW RE-ANALYSES (modules M1-M5)                         ║
# ║  Added 2026-06-15 in response to peer/AI review of the IJHEH submission.   ║
# ║  Self-contained: reloads the same raw workbook used in PART 1.             ║
# ╚══════════════════════════════════════════════════════════════════════════╝

# =============================================================================
# NORO REVIEW ADD-ON v1  (260614)  — answers to IJHEH AI-review weaknesses
# Source pipeline: NORO_FULL_원코드_v9_260530.R  (Set2 LONG, Winsorized = manuscript main)
# Self-contained: reloads the same Raw xlsx and replicates v9 preprocessing.
#
#  Module 1  Absolute humidity (AH)        → reviewer B1/D1, Q7
#  Module 2  Pre/Post boundary robustness   → reviewer B3, Q4   (+ unweighted Watson = A1, Q1)
#  Module 3  Heatwave multiple-testing+perm → reviewer A4/B4, Q5
#  Module 4  Falsification: placebo boundary→ reviewer B2, Q8
#
#  Honest reporting: failed fits reported as NA. No fabricated numbers.
# =============================================================================
suppressWarnings(suppressMessages({
  library(readxl); library(dplyr); library(mgcv); library(MASS)
  library(splines); library(dlnm); library(circular)
}))
set.seed(42)
options(stringsAsFactors = FALSE)

# ─── PATHS (mirror v9) ───────────────────────────────────────────────────────
home <- path.expand("~")
gdrive_root <- file.path(home, "Library/CloudStorage/GoogleDrive-wwwwrte@gmail.com",
                         "내 드라이브/S.K/G.Downloads")
if (!dir.exists(gdrive_root)) gdrive_root <- getwd()
RAW_FILE <- "NORO_GAM_v21_Raw_260520_2356.xlsx"
RAW_PATH <- NULL
for (cand in c(file.path(gdrive_root, "미팅기록", RAW_FILE), file.path(gdrive_root, RAW_FILE)))
  if (file.exists(cand)) { RAW_PATH <- cand; break }
stopifnot(!is.null(RAW_PATH))
cat("Raw input:", RAW_PATH, "\n")

# ─── CONFIG (mirror v9) ──────────────────────────────────────────────────────
TIME_K       <- c(Overall = 30, Pre = 30, Post = 10)
DESPIKE_PCT  <- 0.99
HEAT_GRID    <- c(24.0, 25.0, 26.0, 26.4, 27.0, 28.0)
LAG          <- c(temp = 3, humid = 7, pm10 = 8, precip = 7)  # Set2 LONG

# ─── LOAD + PREPROCESS (mirror v9) ───────────────────────────────────────────
df_raw <- as.data.frame(read_excel(RAW_PATH, sheet = "Weekly_FullData"))
need_lag  <- c(paste0("avg_temp_lag", 0:8), paste0("humidity_lag", 0:8),
               paste0("pm10_lag", 0:8), paste0("precipitation_lag", 0:8))
need_base <- c("year","week","cases","sin52","cos52","sin26","cos26",
               "avg_temp","humidity","pm10","precipitation")
stopifnot(length(setdiff(c(need_base, need_lag), names(df_raw))) == 0)
df_raw <- df_raw[complete.cases(df_raw[, need_lag]), ]
df_raw <- df_raw[df_raw$year >= 2005 & df_raw$year <= 2024, ]
cat(sprintf("Analytic weeks: N = %d (%d–%d)\n", nrow(df_raw), min(df_raw$year), max(df_raw$year)))

# winsorize p99 (Set2 De-spiked)
winsor <- function(df, pct = 0.99) {
  thr <- as.numeric(quantile(df$cases, pct, na.rm = TRUE))
  df$cases_orig <- df$cases
  df$cases <- pmin(df$cases, thr)
  df
}
df_dspk <- winsor(df_raw, DESPIKE_PCT)            # main analysis data
df_orig <- df_raw; df_orig$cases_orig <- df_orig$cases

# Absolute humidity (g/m^3) from T (°C) + RH (%): Bolton/Magnus
ah_calc <- function(T, RH) 6.112 * exp(17.67 * T / (T + 243.5)) * RH * 2.1674 / (273.15 + T)
for (k in 0:8)
  df_dspk[[paste0("AH_lag", k)]] <- ah_calc(df_dspk[[paste0("avg_temp_lag", k)]],
                                            df_dspk[[paste0("humidity_lag", k)]])

# subset builder by boundary "year/week" (Post starts AT or AFTER boundary)
make_subsets <- function(df, b_year, b_week) {
  is_post <- df$year > b_year | (df$year == b_year & df$week >= b_week)
  list(Overall = df %>% arrange(year, week) %>% mutate(time_idx = row_number()),
       Pre     = df[!is_post, ] %>% arrange(year, week) %>% mutate(time_idx = row_number()),
       Post    = df[ is_post, ] %>% arrange(year, week) %>% mutate(time_idx = row_number()))
}
SUB <- make_subsets(df_dspk, 2020, 9)             # manuscript boundary 2020 W09

# ─── circular helpers (mirror v9 G5) ─────────────────────────────────────────
to_rad  <- function(w) 2*pi*(w-1)/52
to_week <- function(a) ((a/(2*pi))*52) %% 52 + 1
circ_mean <- function(w, wt){ a<-to_rad(w); to_week(atan2(sum(wt*sin(a),na.rm=TRUE), sum(wt*cos(a),na.rm=TRUE))) }
mvl_calc  <- function(w, wt){ a<-to_rad(w); sqrt(sum(wt*sin(a),na.rm=TRUE)^2+sum(wt*cos(a),na.rm=TRUE)^2)/sum(wt,na.rm=TRUE) }

# Watson U² between two eras given a data frame with $period in {Pre,Post}, weighted (v9) or unweighted
watson_shift <- function(df, weighted = TRUE) {
  sp <- aggregate(cases_orig ~ week, df[df$period=="Pre", ],  mean, na.rm=TRUE); names(sp)[2] <- "Pre_mean"
  sq <- aggregate(cases_orig ~ week, df[df$period=="Post", ], mean, na.rm=TRUE); names(sq)[2] <- "Post_mean"
  st <- merge(data.frame(week=1:52), merge(sp, sq, by="week", all=TRUE), by="week", all.x=TRUE)
  st[is.na(st)] <- 0
  if (weighted) {
    rp <- rep(st$week, pmax(round(st$Pre_mean *10),0)); rq <- rep(st$week, pmax(round(st$Post_mean*10),0))
  } else {                                    # unweighted = each ISO week once (A1 sensitivity)
    rp <- st$week[st$Pre_mean  > 0];          rq <- st$week[st$Post_mean > 0]
  }
  if (length(rp) < 5 || length(rq) < 5) return(list(U2=NA, com_shift=NA, mvl_pre=NA, mvl_post=NA))
  ws <- tryCatch(watson.two.test(circular(to_rad(rp),units="radians"),
                                 circular(to_rad(rq),units="radians")), error=function(e) NULL)
  sft <- (circ_mean(st$week, st$Post_mean) - circ_mean(st$week, st$Pre_mean)) %% 52
  if (sft > 26) sft <- sft - 52
  list(U2 = if(is.null(ws)) NA else as.numeric(ws$statistic),
       com_shift = sft, mvl_pre = mvl_calc(st$week, st$Pre_mean), mvl_post = mvl_calc(st$week, st$Post_mean))
}
# Watson two-sample U² critical values: 0.152 (α=0.10), 0.187 (0.05), 0.268 (0.01), 0.385 (0.001)
wat_sig <- function(U2) if(is.na(U2)) "NA" else if(U2>=.385)"p<0.001" else if(U2>=.268)"p<0.01" else if(U2>=.187)"p<0.05" else if(U2>=.152)"p<0.10" else "n.s."

# main GAMM formula (Set2 LONG)
gam_form <- function(humid_term, k_time)
  as.formula(sprintf("cases ~ s(avg_temp_lag%d,k=6)+%s+s(pm10_lag%d,k=6)+s(precipitation_lag%d,k=6)+s(time_idx,k=%d)+sin52+cos52+sin26+cos26",
                     LAG["temp"], humid_term, LAG["pm10"], LAG["precip"], k_time))

# DLNM cumulative %-change per +1 unit — EXACT mirror of v9 G10 (linear-integer; time_idx linear; linear adjust vars)
dlnm_cum <- function(d, exposure_vec, adjust_vars, upto = 4, lag_max = 8) {
  if (!exposure_vec %in% names(d)) return(c(est=NA, lo=NA, hi=NA))
  x <- d[[exposure_vec]]
  if (any(is.na(x))) return(c(est=NA, lo=NA, hi=NA))
  cb <- tryCatch(crossbasis(x, lag = c(0, lag_max), argvar = list(fun="lin"),
                            arglag = list(fun="integer")), error=function(e) NULL)   # "linear-integer"
  if (is.null(cb)) return(c(est=NA, lo=NA, hi=NA))
  rhs <- "cb + sin52+cos52+sin26+cos26 + time_idx"
  av <- intersect(adjust_vars, names(d))
  if (length(av)) rhs <- paste(rhs, "+", paste(av, collapse=" + "))
  m <- tryCatch(suppressWarnings(glm.nb(as.formula(paste("cases ~", rhs)), data=d)),
                error=function(e) NULL)
  if (is.null(m)) return(c(est=NA, lo=NA, hi=NA))
  cp <- tryCatch(crosspred(cb, m, at=1, cen=0, cumul=TRUE), error=function(e) NULL)
  if (is.null(cp)) return(c(est=NA, lo=NA, hi=NA))
  i <- upto + 1
  c(est=as.numeric((cp$cumRRfit[1,i]-1)*100),
    lo =as.numeric((cp$cumRRlow[1,i]-1)*100),
    hi =as.numeric((cp$cumRRhigh[1,i]-1)*100))
}

cat("\n", strrep("=",78), "\n  NORO REVIEW ADD-ON — results\n", strrep("=",78), "\n", sep="")

# =============================================================================
# MODULE 1 — ABSOLUTE HUMIDITY (reviewer B1/D1, Q7)
# =============================================================================
cat("\n## [M1] Absolute humidity vs relative humidity\n")
m1 <- list()
for (sb in c("Overall","Pre","Post")) {
  d <- SUB[[sb]]; kt <- TIME_K[sb]
  m_rh <- tryCatch(gam(gam_form(sprintf("s(humidity_lag%d,k=6)", LAG["humid"]), kt),
                       family=nb(), data=d, method="REML"), error=function(e) NULL)
  m_ah <- tryCatch(gam(gam_form(sprintf("s(AH_lag%d,k=6)",       LAG["humid"]), kt),
                       family=nb(), data=d, method="REML"), error=function(e) NULL)
  s_ah <- if(!is.null(m_ah)) summary(m_ah) else NULL
  ah_row <- if(!is.null(s_ah)) s_ah$s.table[grep("AH_lag", rownames(s_ah$s.table))[1], ] else c(NA,NA,NA,NA)
  cum <- dlnm_cum(d, "AH_lag0", adjust_vars = c("avg_temp_lag3","pm10_lag8","precipitation_lag7"), upto = 4)
  m1[[sb]] <- data.frame(subset=sb,
     AIC_RH = if(!is.null(m_rh)) round(AIC(m_rh),1) else NA,
     AIC_AH = if(!is.null(m_ah)) round(AIC(m_ah),1) else NA,
     dAIC_AHminusRH = if(!is.null(m_rh)&&!is.null(m_ah)) round(AIC(m_ah)-AIC(m_rh),1) else NA,
     AH_smooth_edf = round(ah_row[1],2), AH_smooth_p = signif(ah_row[4],3),
     AH_DLNM_cum4_pct = round(cum["est"],2),
     AH_DLNM_cum4_CI = sprintf("[%.2f, %.2f]", cum["lo"], cum["hi"]))
}
m1 <- do.call(rbind, m1); print(m1, row.names=FALSE)
cat("Note: dAIC<0 ⇒ AH fits better than RH at equal df. DLNM cum4 = cumulative %Δ per +1 g/m³ over lag 0-4.\n")

# =============================================================================
# MODULE 2 — PRE/POST BOUNDARY ROBUSTNESS (reviewer B3, Q4)  + unweighted Watson (A1, Q1)
# =============================================================================
cat("\n## [M2] Boundary robustness: Watson U² + Post-era temp DLNM across boundaries\n")
boundaries <- list(c(2020,9), c(2021,1), c(2022,1))
m2 <- list()
for (b in boundaries) {
  by <- b[1]; bw <- b[2]; lab <- sprintf("%dW%02d", by, bw)
  do <- df_orig; do$period <- factor(ifelse(do$year>by | (do$year==by & do$week>=bw),"Post","Pre"), c("Pre","Post"))
  w_wt <- watson_shift(do, weighted=TRUE)
  w_uw <- watson_shift(do, weighted=FALSE)
  subs <- make_subsets(df_dspk, by, bw)
  tcum <- dlnm_cum(subs$Post, "avg_temp", adjust_vars = c("humidity_lag7","pm10_lag8","precipitation_lag7"), upto = 4)
  m2[[lab]] <- data.frame(boundary=lab, n_post=nrow(subs$Post),
     U2_weighted=round(w_wt$U2,3), sig_wt=wat_sig(w_wt$U2),
     U2_unweighted=round(w_uw$U2,3), sig_uw=wat_sig(w_uw$U2),
     COM_shift_wk=round(w_wt$com_shift,1),
     MVL_pre=round(w_wt$mvl_pre,3), MVL_post=round(w_wt$mvl_post,3),
     Post_temp_cum4_pct=round(tcum["est"],2),
     Post_temp_cum4_CI=sprintf("[%.2f, %.2f]", tcum["lo"], tcum["hi"]))
}
m2 <- do.call(rbind, m2); print(m2, row.names=FALSE)
cat("Note: main boundary = 2020W09. Stable U²/sig and Post temp emergence across rows ⇒ robust.\n")
cat("      U²_unweighted (each ISO week once, no case-weighting) = reviewer A1 amplitude-free sensitivity.\n")

# =============================================================================
# MODULE 3 — HEATWAVE MULTIPLE-TESTING + PERMUTATION (reviewer A4/B4, Q5)
# =============================================================================
cat("\n## [M3] Heatwave dose-response: multiple-testing correction + permutation stability\n")
d <- SUB$Overall; ktH <- min(20, max(4, floor(nrow(d)/15)))
heat_event_vec <- function(temp, thr) {
  h <- as.integer(temp > thr); r <- rle(h==1); ev <- rep(0L,length(h)); pos <- 1
  for (i in seq_along(r$lengths)) { if (r$values[i] && r$lengths[i]>=2) ev[pos:(pos+r$lengths[i]-1)] <- 1L; pos <- pos+r$lengths[i] }
  ev
}
fit_heat_irr <- function(d, ev) {
  d$heat_event <- ev
  m <- tryCatch(glm.nb(cases ~ heat_event + sin52+cos52+sin26+cos26 + ns(time_idx, df=ktH), data=d), error=function(e) NULL)
  if (is.null(m) || !"heat_event" %in% rownames(summary(m)$coef)) return(c(beta=NA,irr=NA,lo=NA,hi=NA,p=NA,n=sum(ev)))
  s <- summary(m)$coef["heat_event",]
  c(beta=unname(s[1]), irr=unname(exp(s[1])), lo=unname(exp(s[1]-1.96*s[2])),
    hi=unname(exp(s[1]+1.96*s[2])), p=unname(s[4]), n=sum(ev))
}
m3 <- list()
for (thr in HEAT_GRID) {
  ev <- heat_event_vec(d$avg_temp_lag3, thr)
  r <- fit_heat_irr(d, ev)
  m3[[as.character(thr)]] <- data.frame(threshold=thr, n_event_wk=r["n"], IRR=round(r["irr"],3),
     CI=sprintf("[%.2f, %.2f]", r["lo"], r["hi"]), p_raw=signif(r["p"],3), beta=r["beta"])
}
m3 <- do.call(rbind, m3)
m3$p_Holm <- signif(p.adjust(m3$p_raw, "holm"), 3)
m3$p_BH   <- signif(p.adjust(m3$p_raw, "BH"),   3)
# permutation stability for the high thresholds (label shuffle, preserve #event weeks)
B_PERM <- 1000
perm_p <- function(thr) {
  ev <- heat_event_vec(d$avg_temp_lag3, thr); obs <- fit_heat_irr(d, ev)["beta"]
  if (is.na(obs) || sum(ev) < 2) return(NA)
  cnt <- 0L; ok <- 0L
  for (b in 1:B_PERM) {
    evp <- sample(ev)
    bb <- fit_heat_irr(d, evp)["beta"]
    if (!is.na(bb)) { ok <- ok+1L; if (abs(bb) >= abs(obs)) cnt <- cnt+1L }
  }
  if (ok==0) NA else (cnt+1)/(ok+1)
}
m3$p_perm <- NA
for (thr in c(27.0, 28.0)) m3$p_perm[m3$threshold==thr] <- signif(perm_p(thr), 3)
print(m3[, c("threshold","n_event_wk","IRR","CI","p_raw","p_Holm","p_BH","p_perm")], row.names=FALSE)
cat(sprintf("Note: Holm/BH across the 6 thresholds; permutation p (B=%d, label shuffle) for ≥27/≥28°C high-threshold stability.\n", B_PERM))

# =============================================================================
# MODULE 4 — FALSIFICATION: PLACEBO BOUNDARY (reviewer B2, Q8)
# =============================================================================
cat("\n## [M4] Falsification — placebo-boundary null for the Watson U² seasonality shift\n")
do <- df_orig
ord <- do %>% arrange(year, week)
n <- nrow(ord); lo_i <- 105; hi_i <- n-105      # keep ≥~2yr each side
true <- { do$period <- factor(ifelse(do$year>2020 | (do$year==2020 & do$week>=9),"Post","Pre"), c("Pre","Post")); watson_shift(do, TRUE)$U2 }
B_PB <- 500
null_U2 <- numeric(0)
for (b in 1:B_PB) {
  i <- sample(lo_i:hi_i, 1)
  pr <- rep("Pre", n); pr[(i+1):n] <- "Post"
  tmp <- ord; tmp$period <- factor(pr, c("Pre","Post"))
  u <- watson_shift(tmp, TRUE)$U2
  if (!is.na(u)) null_U2 <- c(null_U2, u)
}
emp_p <- (sum(null_U2 >= true) + 1) / (length(null_U2) + 1)
cat(sprintf("  Observed U² at true COVID boundary (2020W09): %.3f (%s)\n", true, wat_sig(true)))
cat(sprintf("  Placebo-boundary null (B=%d valid): mean=%.3f, 95th pct=%.3f, max=%.3f\n",
            length(null_U2), mean(null_U2), quantile(null_U2,.95), max(null_U2)))
cat(sprintf("  Empirical p (random split ≥ observed): %.4f\n", emp_p))
cat("  Interpretation: small p ⇒ the COVID-boundary seasonality shift is NOT an artifact of arbitrary time-splitting.\n")
cat("  (A pathogen-level negative control — a non-climate-sensitive organism — requires external surveillance data not in this file.)\n")

# =============================================================================
# MODULE 5 — VALID seasonality-shift test: YEAR-UNIT permutation (reviewer A1; rescues/retires Pillar A)
#   No case pseudo-replication. Unit = calendar year (Pre ≤2019, Post ≥2021; 2020 excluded as transition).
# =============================================================================
cat("\n## [M5] Year-unit permutation test of the seasonal-distribution shift (amplitude-free)\n")
yr_com <- function(dfy) {
  st <- aggregate(cases_orig ~ week, dfy, mean, na.rm=TRUE)
  if (nrow(st) < 10 || sum(st$cases_orig) <= 0) return(c(com=NA, peak=NA))
  c(com = circ_mean(st$week, st$cases_orig), peak = st$week[which.max(st$cases_orig)])
}
yrs <- sort(unique(df_orig$year))
com_by_year <- t(sapply(yrs, function(y) yr_com(df_orig[df_orig$year==y, ])))
rownames(com_by_year) <- yrs
era  <- ifelse(yrs <= 2019, "Pre", ifelse(yrs >= 2021, "Post", "Excl"))
keep <- era != "Excl" & !is.na(com_by_year[,"com"])
com  <- com_by_year[keep, "com"]; grp <- era[keep]
ang_mean <- function(w) circ_mean(w, rep(1, length(w)))
diff_wk  <- function(a, b){ d <- (a-b) %% 52; if (d > 26) d <- d - 52; d }
obs_pre  <- ang_mean(com[grp=="Pre"]); obs_post <- ang_mean(com[grp=="Post"])
obs_d    <- diff_wk(obs_post, obs_pre)
B5 <- 10000; cnt <- 0L
for (b in 1:B5) {
  gp <- sample(grp)
  dd <- diff_wk(ang_mean(com[gp=="Post"]), ang_mean(com[gp=="Pre"]))
  if (abs(dd) >= abs(obs_d)) cnt <- cnt + 1L
}
p5 <- (cnt + 1) / (B5 + 1)
cat(sprintf("  Units: Pre = %d years (<=2019), Post = %d years (>=2021); 2020 excluded.\n",
            sum(grp=="Pre"), sum(grp=="Post")))
cat("  Per-year circular center-of-mass (COM week) and peak week:\n")
print(round(com_by_year, 1))
cat(sprintf("  Pre mean COM = %.1f wk | Post mean COM = %.1f wk | shift = %+.1f wk\n",
            obs_pre, obs_post, obs_d))
cat(sprintf("  *** Year-unit permutation p (B=%d): %.4f ***\n", B5, p5))
pk <- com_by_year[keep, "peak"]
wp <- tryCatch(suppressWarnings(wilcox.test(pk[grp=="Pre"], pk[grp=="Post"])$p.value), error=function(e) NA)
cat(sprintf("  Secondary peak-week Wilcoxon p = %.4f (Pre median wk %.0f vs Post median wk %.0f)\n",
            wp, median(pk[grp=="Pre"]), median(pk[grp=="Post"])))
cat("  → This is the amplitude-free, correctly-powered test. It REPLACES the case-weighted Watson U² for Pillar A.\n")

cat("\n", strrep("=",78), "\n  ADD-ON COMPLETE\n", strrep("=",78), "\n", sep="")
