# =============================================================================
#  Climate sensitivity of norovirus notifications — Republic of Korea, 2005–2024
#  Reproducible analysis code for the manuscript:
#  "Climate Sensitivity of Norovirus in Korea, 2005–2024: An Altered
#   Post-COVID-19 Temperature Response and an Event-Based Heatwave Alert".
#
#  Author : Seongdae Kim      Advisor/corresponding : Byung Chul Chun
#  License: MIT (code).  Data: see "DATA" below.
# -----------------------------------------------------------------------------
#  HOW TO RUN
#    1. Place the input workbook (see DATA) next to this script, or edit RAW_PATH.
#    2. Rscript norovirus_climate_gam.R        # ~3–5 min (permutations/bootstrap)
#    Packages are auto-installed on first run. Tested on R 4.5.
#
#  DATA (not redistributed; no personal identifiers)
#    - Weekly laboratory-confirmed norovirus food-poisoning counts, Korea
#      Ministry of Food and Drug Safety (MFDS) Food Poisoning Statistics System.
#    - Weekly meteorology (temperature, RH, precipitation, wind) + PM10, Korea
#      Meteorological Administration (KMA) Open MET Data Portal.
#    - Single workbook "NORO_GAM_v21_Raw_260520_2356.xlsx", sheet "Weekly_FullData",
#      with columns: year, week, cases, sin52/cos52/sin26/cos26, avg_temp,
#      humidity, pm10, precipitation, and lagged covariates *_lag0..8.
#
#  OUTPUT MAP  (section  ->  manuscript object)
#    [2] Descriptives ............. Table 1, Table 2
#    [3] NB-GAMM + diagnostics ..... model fit; Ljung–Box (Methods)
#    [4] Period × Climate ΔAIC ..... Supplementary Table S1
#    [5] Watson U² + amplitude-free  Table 3 panel A; Supp S3, S5, S7, S8
#    [6] Heatwave dose–response ..... Table 3 panel B; Supp S6 (Holm/BH + perm)
#    [7] DLNM cumulative-lag ........ Table 3 panel C; Supp S2; Supp S4 (abs. humidity)
#    [8] ZINB block bootstrap ....... β stability (Methods)
#    [9] Figure 2 composite ......... Figure 2 (a weekly / b year-COM / c temp–response)
#    [10] Trend/climate sensitivity .. Supplementary Table S9 (heatwave + DLNM robustness)
#  Headline numbers reproduced: Watson U²=18.32 (case-weighted) vs year-unit
#  permutation p≈0.66; heatwave IRRs 2.48 (≥24 °C) to 8.24 (≥28 °C); DLNM Post temp +41% at lag 4.
# =============================================================================

## ---- [0] Setup ---------------------------------------------------------------
pkgs <- c("readxl","dplyr","mgcv","nlme","MASS","splines","dlnm","circular","pscl",
          "ggplot2","patchwork")
inst <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(inst)) install.packages(inst, repos = "https://cloud.r-project.org")
suppressWarnings(suppressMessages(
  for (p in pkgs) library(p, character.only = TRUE)))
set.seed(42)

# config (Set 2 LONG = manuscript main specification)
LAG          <- c(temp = 3, humid = 7, pm10 = 8, precip = 7)
TIME_K       <- c(Overall = 30, Pre = 30, Post = 10)   # time-spline basis dim
DESPIKE_PCT  <- 0.99                                    # winsorization
HEAT_GRID    <- c(24.0, 25.0, 26.0, 26.4, 27.0, 28.0)  # heatwave thresholds (°C)
BOOT_R       <- 200                                     # ZINB block bootstrap
B_PERM       <- 1000                                    # heatwave permutation
B_PLACEBO    <- 300                                     # placebo-boundary null
B_YEARPERM   <- 10000                                   # year-unit permutation

## ---- [1] Load + preprocess ---------------------------------------------------
RAW_FILE <- "NORO_GAM_v21_Raw_260520_2356.xlsx"
# Place the workbook beside this script, edit RAW_PATH, or export NORO_RAW_PATH.
RAW_PATH <- Sys.getenv("NORO_RAW_PATH", unset = RAW_FILE)
stopifnot("Raw workbook not found — put it beside the script or set RAW_PATH/NORO_RAW_PATH" = file.exists(RAW_PATH))

df <- as.data.frame(readxl::read_excel(RAW_PATH, sheet = "Weekly_FullData"))
lagcols <- c(paste0("avg_temp_lag",0:8), paste0("humidity_lag",0:8),
             paste0("pm10_lag",0:8), paste0("precipitation_lag",0:8))
df <- df[complete.cases(df[, lagcols]), ]
df <- df[df$year >= 2005 & df$year <= 2024, ]
df <- df[order(df$year, df$week), ]
df$cases_orig <- df$cases

# winsorize weekly counts at the 99th percentile (Set 2 "De-spiked")
winsor <- function(d, pct = 0.99) {
  thr <- as.numeric(quantile(d$cases, pct, na.rm = TRUE))
  d$cases <- pmin(d$cases, thr); attr(d, "thr") <- thr; d
}
df <- winsor(df, DESPIKE_PCT)

# absolute humidity (g/m^3) from temperature + RH (Magnus/Bolton) — Supp S6
ah <- function(T, RH) 6.112 * exp(17.67*T/(T+243.5)) * RH * 2.1674 / (273.15+T)
for (k in 0:8)
  df[[paste0("AH_lag",k)]] <- ah(df[[paste0("avg_temp_lag",k)]],
                                 df[[paste0("humidity_lag",k)]])

# Pre/Post subsets at the COVID-onset boundary 2020 W09 (785 / 252)
subsets <- function(d, b_year = 2020, b_week = 9) {
  post <- d$year > b_year | (d$year == b_year & d$week >= b_week)
  list(Overall = transform(d,           time_idx = seq_len(nrow(d))),
       Pre     = transform(d[!post, ],  time_idx = seq_len(sum(!post))),
       Post    = transform(d[ post, ],  time_idx = seq_len(sum( post))))
}
SUB <- subsets(df)
cat(sprintf("Analytic weeks: %d (Pre %d / Post %d)\n",
            nrow(df), nrow(SUB$Pre), nrow(SUB$Post)))

## ---- [2] Descriptives → Table 1, Table 2 ------------------------------------
cat("\n[2] Descriptives (Table 1 / Table 2)\n")
tab1 <- data.frame(
  period = c("Overall","Pre-COVID-19","Post-COVID-19"),
  n_weeks = c(nrow(df), nrow(SUB$Pre), nrow(SUB$Post)),
  mean_cases = round(c(mean(df$cases_orig), mean(SUB$Pre$cases_orig),
                       mean(SUB$Post$cases_orig)), 2))
print(tab1, row.names = FALSE)
clim <- c("avg_temp","humidity","precipitation","pm10")
tab2 <- t(sapply(clim, function(v) c(mean = mean(df[[v]]), sd = sd(df[[v]]),
                                     min = min(df[[v]]), max = max(df[[v]]))))
print(round(tab2, 2))

## ---- helper: main NB-GAMM (Set 2 LONG) --------------------------------------
gam_form <- function(humid_term, k_time)
  as.formula(sprintf(paste0("cases ~ s(avg_temp_lag%d,k=6)+%s+s(pm10_lag%d,k=6)+",
                            "s(precipitation_lag%d,k=6)+s(time_idx,k=%d)+",
                            "sin52+cos52+sin26+cos26"),
                     LAG["temp"], humid_term, LAG["pm10"], LAG["precip"], k_time))
fit_gam <- function(d, kt, humid_term = sprintf("s(humidity_lag%d,k=6)", LAG["humid"]))
  mgcv::gam(gam_form(humid_term, kt), family = nb(), data = d, method = "REML")

## ---- [3] Main NB-GAMM (AR(1)) + Ljung–Box diagnostics -----------------------
cat("\n[3] NB-GAMM (Set 2 LONG, AR(1)) + residual diagnostics\n")
main_form <- as.formula(paste0(
  "cases ~ s(avg_temp_lag3,k=6)+s(humidity_lag7,k=6)+s(pm10_lag8,k=6)+",
  "s(precipitation_lag7,k=6)+s(time_idx,k=30)+sin52+cos52+sin26+cos26"))
m_main <- suppressWarnings(suppressMessages(gamm(main_form,           # nb() in gamm uses PQL
               correlation = corAR1(form = ~time_idx),
               family = nb(), data = SUB$Overall, method = "REML")))
res <- residuals(m_main$lme, type = "normalized")
lb  <- sapply(c(12,26,52), function(L) Box.test(res, lag=L, type="Ljung-Box")$p.value)
rho <- tryCatch(coef(m_main$lme$modelStruct$corStruct, unconstrained=FALSE)[[1]],
                error=function(e) NA)
cat(sprintf("  AR(1) rho = %.3f | Ljung–Box p (lag 12/26/52): %.3f / %.3f / %.3f\n",
            rho, lb[1], lb[2], lb[3]))

## ---- [4] Period × Climate interaction ΔAIC (GAMM, AR(1)) → Supp S1 ----------
cat("\n[4] Period × Climate interaction ΔAIC (GAMM AR(1); Supp S1)\n")
dO <- SUB$Overall
dO$period <- factor(ifelse(dO$year < 2020 | (dO$year == 2020 & dO$week <= 8),
                           "Pre","Post"), c("Pre","Post"))
g1_form <- function(int_var = NULL) {       # focal var gets by=period; others common
  vars  <- c("avg_temp_lag3","humidity_lag7","pm10_lag8","precipitation_lag7")
  parts <- vapply(vars, function(v)
    if (!is.null(int_var) && v == int_var) sprintf("s(%s, by=period, k=6) + period", v)
    else sprintf("s(%s, k=6)", v), character(1))
  as.formula(paste("cases ~ s(time_idx, k=30) + sin52 + cos52 +", paste(parts, collapse=" + ")))
}
g1_fit <- function(f) suppressWarnings(suppressMessages(
  gamm(f, correlation=corAR1(form=~time_idx), family=nb(), data=dO, method="REML")))
m0 <- g1_fit(g1_form(NULL))
for (v in c("avg_temp_lag3","humidity_lag7","pm10_lag8")) {
  mi <- g1_fit(g1_form(v))
  cat(sprintf("  %-14s ΔAIC (interaction − null) = %+.1f\n", v, AIC(mi$lme) - AIC(m0$lme)))
}

## ---- circular helpers (Watson U², COM, MVL) ---------------------------------
to_rad  <- function(w) 2*pi*(w-1)/52
to_week <- function(a) ((a/(2*pi))*52) %% 52 + 1
circ_mean <- function(w, wt) to_week(atan2(sum(wt*sin(to_rad(w))), sum(wt*cos(to_rad(w)))))
mvl <- function(w, wt) sqrt(sum(wt*sin(to_rad(w)))^2 + sum(wt*cos(to_rad(w)))^2)/sum(wt)
# Watson two-sample U² between eras; weighted = case-weighted replicates (×10)
watson <- function(d, weighted = TRUE) {
  sp <- aggregate(cases_orig~week, d[d$period=="Pre", ],  mean); names(sp)[2] <- "Pre"
  sq <- aggregate(cases_orig~week, d[d$period=="Post",], mean); names(sq)[2] <- "Post"
  st <- merge(data.frame(week=1:52), merge(sp,sq,by="week",all=TRUE), all.x=TRUE); st[is.na(st)] <- 0
  if (weighted) { rp <- rep(st$week, pmax(round(st$Pre*10),0)); rq <- rep(st$week, pmax(round(st$Post*10),0)) }
  else          { rp <- st$week[st$Pre>0];                       rq <- st$week[st$Post>0] }
  ws <- tryCatch(watson.two.test(circular(to_rad(rp),units="radians"),
                                 circular(to_rad(rq),units="radians")), error=function(e) NULL)
  shift <- (circ_mean(st$week,st$Post) - circ_mean(st$week,st$Pre)) %% 52
  if (shift > 26) shift <- shift - 52
  list(U2 = if(is.null(ws)) NA else as.numeric(ws$statistic), shift = shift,
       mvl_pre = mvl(st$week,st$Pre), mvl_post = mvl(st$week,st$Post))
}

## ---- [5] Watson U² + amplitude-free tests → Table 3A; Supp S7/S9/S10 --------
cat("\n[5] Seasonal-distribution test (Table 3A; amplitude-free Supp S7/S9/S10)\n")
w_wt <- watson(dO, TRUE); w_uw <- watson(dO, FALSE)
cat(sprintf("  Watson U² case-weighted = %.2f | unweighted = %.3f | COM shift %.1f wk\n",
            w_wt$U2, w_uw$U2, w_wt$shift))
# year-unit permutation (amplitude-free, correctly powered) — Supp S10
yr_com <- function(y){ d<-df[df$year==y,]; st<-aggregate(cases_orig~week,d,mean)
  if (nrow(st)<10) NA else circ_mean(st$week, st$cases_orig) }
yrs <- sort(unique(df$year)); com <- sapply(yrs, yr_com)
era <- ifelse(yrs<=2019,"Pre",ifelse(yrs>=2021,"Post",NA)); keep <- !is.na(era)&!is.na(com)
g <- era[keep]; cv <- com[keep]
amean <- function(w) circ_mean(w, rep(1,length(w)))
dwk <- function(a,b){ x<-(a-b)%%52; if(x>26) x<-x-52; x }
obs <- dwk(amean(cv[g=="Post"]), amean(cv[g=="Pre"]))
nullv <- replicate(B_YEARPERM, { gp<-sample(g); dwk(amean(cv[gp=="Post"]), amean(cv[gp=="Pre"])) })
p_year <- (sum(abs(nullv)>=abs(obs))+1)/(B_YEARPERM+1)
cat(sprintf("  Year-unit permutation: shift %+.1f wk, p = %.3f  (Pre %d yr / Post %d yr)\n",
            obs, p_year, sum(g=="Pre"), sum(g=="Post")))
# placebo-boundary null — Supp S9
n <- nrow(df); idx <- 105:(n-105); pl <- numeric(0)
for (b in 1:B_PLACEBO) { i<-sample(idx,1); tmp<-df; tmp$period<-factor(c(rep("Pre",i),rep("Post",n-i)),c("Pre","Post"))
  u<-watson(tmp,TRUE)$U2; if(!is.na(u)) pl<-c(pl,u) }
cat(sprintf("  Placebo-boundary null: observed %.2f vs null mean %.2f, p = %.3f\n",
            w_wt$U2, mean(pl), (sum(pl>=w_wt$U2)+1)/(length(pl)+1)))

## ---- [6] Heatwave dose–response + multiple testing → Table 3B; Supp S8 ------
cat("\n[6] Heatwave dose–response (Table 3B; multiple testing + permutation Supp S8)\n")
heat_event <- function(temp, thr){ h<-as.integer(temp>thr); r<-rle(h==1); ev<-rep(0L,length(h)); pos<-1
  for(i in seq_along(r$lengths)){ if(r$values[i]&&r$lengths[i]>=2) ev[pos:(pos+r$lengths[i]-1)]<-1L; pos<-pos+r$lengths[i] }; ev }
dh <- SUB$Overall; ktH <- min(20, max(4, floor(nrow(dh)/15)))
fit_heat <- function(ev){ dh$ev<-ev
  m<-tryCatch(glm.nb(cases~ev+sin52+cos52+sin26+cos26+time_idx,data=dh),error=function(e)NULL)  # linear time = manuscript heatwave spec
  if(is.null(m)||!"ev"%in%rownames(summary(m)$coef)) return(c(b=NA,irr=NA,lo=NA,hi=NA,p=NA))
  s<-summary(m)$coef["ev",]; c(b=unname(s[1]),irr=unname(exp(s[1])),
    lo=unname(exp(s[1]-1.96*s[2])),hi=unname(exp(s[1]+1.96*s[2])),p=unname(s[4])) }
hw <- do.call(rbind, lapply(HEAT_GRID, function(thr){ ev<-heat_event(dh$avg_temp,thr)
  r<-fit_heat(ev); data.frame(threshold=thr,n_event_wk=sum(ev),IRR=round(r["irr"],3),
    CI=sprintf("[%.2f, %.2f]",r["lo"],r["hi"]),p_raw=signif(r["p"],3),b=r["b"]) }))
hw$p_Holm <- signif(p.adjust(hw$p_raw,"holm"),3); hw$p_BH <- signif(p.adjust(hw$p_raw,"BH"),3)
hw$p_perm <- NA
for (thr in c(27,28)) { ev<-heat_event(dh$avg_temp,thr); ob<-fit_heat(ev)["b"]
  if(!is.na(ob)){ cnt<-sum(replicate(B_PERM, { bb<-fit_heat(sample(ev))["b"]; !is.na(bb)&&abs(bb)>=abs(ob) }))
    hw$p_perm[hw$threshold==thr]<-signif((cnt+1)/(B_PERM+1),3) } }
print(hw[,c("threshold","n_event_wk","IRR","CI","p_raw","p_Holm","p_BH","p_perm")], row.names=FALSE)

## ---- DLNM helper (v9 spec: linear exposure, integer lag) --------------------
dlnm_cum <- function(d, exposure, adjust, upto = 4, lagmax = 8) {
  x <- d[[exposure]]; if (any(is.na(x))) return(c(est=NA,lo=NA,hi=NA))
  cb <- tryCatch(crossbasis(x, lag=c(0,lagmax), argvar=list(fun="lin"),
                            arglag=list(fun="integer")), error=function(e) NULL)
  if (is.null(cb)) return(c(est=NA,lo=NA,hi=NA))
  rhs <- paste("cb + sin52+cos52+sin26+cos26 + time_idx",
               if(length(intersect(adjust,names(d)))) paste("+", paste(intersect(adjust,names(d)),collapse=" + ")) else "")
  m <- tryCatch(glm.nb(as.formula(paste("cases ~", rhs)), data=d), error=function(e) NULL)
  if (is.null(m)) return(c(est=NA,lo=NA,hi=NA))
  cp <- tryCatch(crosspred(cb, m, at=1, cen=0, cumul=TRUE), error=function(e) NULL)
  if (is.null(cp)) return(c(est=NA,lo=NA,hi=NA))
  i <- upto+1
  c(est=as.numeric((cp$cumRRfit[1,i]-1)*100), lo=as.numeric((cp$cumRRlow[1,i]-1)*100),
    hi=as.numeric((cp$cumRRhigh[1,i]-1)*100))
}

## ---- [7] DLNM cumulative-lag → Table 3C; Supp S2; Supp S6 (abs. humidity) ---
cat("\n[7] DLNM cumulative-lag (Table 3C; Supp S2 / S6)\n")
adj_temp <- c("humidity_lag7","pm10_lag8","precipitation_lag7")
adj_ah   <- c("avg_temp_lag3","pm10_lag8","precipitation_lag7")
for (sb in c("Overall","Pre","Post")) {
  t4 <- dlnm_cum(SUB[[sb]], "avg_temp", adj_temp, 4)
  a4 <- dlnm_cum(SUB[[sb]], "AH_lag0",  adj_ah,   4)
  cat(sprintf("  %-7s temp cum-lag4 = %+6.2f%% [%.1f, %.1f] | AH cum-lag4 = %+6.2f%%\n",
              sb, t4["est"], t4["lo"], t4["hi"], a4["est"]))
}

## ---- [8] ZINB block bootstrap (β stability) ---------------------------------
cat("\n[8] ZINB block bootstrap β stability (52-wk blocks, R=200)\n")
vars_b <- c("avg_temp_lag3","humidity_lag7","pm10_lag8","precipitation_lag7")
dO$cases_int <- round(dO$cases)   # zeroinfl needs integer counts (winsor cap is non-integer)
f_zinb <- as.formula(paste("cases_int ~", paste(vars_b,collapse="+"),
            "+ sin52+cos52+sin26+cos26 | 1"))
bs <- 52; nb <- ceiling(nrow(dO)/bs); bm <- matrix(NA, BOOT_R, length(vars_b), dimnames=list(NULL,vars_b))
for (b in 1:BOOT_R) {
  st <- sample(seq_len(nrow(dO)-bs+1), nb, replace=TRUE)
  rows <- unlist(lapply(st, function(s) s:(s+bs-1))); rows <- rows[rows<=nrow(dO)]
  fit <- tryCatch(suppressWarnings(zeroinfl(f_zinb, data=dO[rows,], dist="negbin")), error=function(e) NULL)
  if(!is.null(fit)){ cc<-coef(fit, model="count"); for(v in vars_b) if(v%in%names(cc)) bm[b,v]<-cc[v] }
}
zb <- data.frame(var=vars_b,
  pct_mean=round((exp(colMeans(bm,na.rm=TRUE))-1)*100,2),
  ci_lo=round((exp(apply(bm,2,quantile,.025,na.rm=TRUE))-1)*100,2),
  ci_hi=round((exp(apply(bm,2,quantile,.975,na.rm=TRUE))-1)*100,2))
print(zb, row.names=FALSE)

## ---- [9] Figure 2 (a weekly / b year-COM / c temperature response) ----------
cat("\n[9] Figure 2 composite -> Figure2.png\n")
sp<-aggregate(cases_orig~week,dO[dO$period=="Pre",],mean);names(sp)[2]<-"Pre"
sq<-aggregate(cases_orig~week,dO[dO$period=="Post",],mean);names(sq)[2]<-"Post"
wkm<-merge(merge(data.frame(week=1:52),sp,all.x=TRUE),sq,all.x=TRUE)
wl<-rbind(data.frame(week=wkm$week,mean=wkm$Pre,era="Pre-COVID"),
          data.frame(week=wkm$week,mean=wkm$Post,era="Post-COVID")); wl$era<-factor(wl$era,c("Pre-COVID","Post-COVID"))
pa<-ggplot(wl,aes(week,mean,color=era))+geom_line(linewidth=.8)+scale_color_manual(values=c("#185FA5","#A32D2D"))+
  labs(title="(a) Weekly mean notifications",x="ISO week",y="Mean cases",color=NULL)+theme_minimal(base_size=10)+
  theme(legend.position=c(.5,.92),legend.direction="horizontal")
dd<-data.frame(com=cv,era=factor(g,c("Pre","Post")))
pb<-ggplot(dd,aes(era,com,color=era))+geom_jitter(width=.08,size=2.4,alpha=.85)+
  stat_summary(fun=mean,geom="crossbar",width=.4,color="black",linewidth=.35)+
  scale_color_manual(values=c("#185FA5","#A32D2D"))+
  annotate("text",x=1.5,y=Inf,label=sprintf("permutation p = %.2f (n.s.)",p_year),vjust=1.3,size=3)+
  labs(title="(b) Per-year seasonal center-of-mass",x=NULL,y="Circular COM (ISO week)")+
  theme_minimal(base_size=10)+theme(legend.position="none")
mc<-gam(cases~s(avg_temp_lag3,by=period,k=6)+s(time_idx,k=20)+sin52+cos52+sin26+cos26+period,family=nb(),data=dO)
rng<-range(dO$avg_temp_lag3); nd<-do.call(rbind,lapply(c("Pre","Post"),function(pe)
  data.frame(avg_temp_lag3=seq(rng[1],rng[2],length=120),period=pe,time_idx=median(dO$time_idx),sin52=0,cos52=0,sin26=0,cos26=0)))
nd$period<-factor(nd$period,c("Pre","Post")); pr<-predict(mc,nd,se.fit=TRUE)
nd$fit<-pr$fit-mean(pr$fit); nd$lo<-nd$fit-1.96*pr$se.fit; nd$hi<-nd$fit+1.96*pr$se.fit
nd$era<-factor(ifelse(nd$period=="Pre","Pre-COVID","Post-COVID"),c("Pre-COVID","Post-COVID"))
pc<-ggplot(nd,aes(avg_temp_lag3,fit,color=era,fill=era))+geom_ribbon(aes(ymin=lo,ymax=hi),alpha=.15,color=NA)+
  geom_line(linewidth=.8)+geom_hline(yintercept=0,linetype=2,color="grey50")+
  scale_color_manual(values=c("#185FA5","#A32D2D"))+scale_fill_manual(values=c("#185FA5","#A32D2D"))+
  labs(title="(c) Temperature exposure-response by era",x="Mean temp lag-3 (°C)",y="Log relative rate",color=NULL,fill=NULL)+
  theme_minimal(base_size=10)+theme(legend.position=c(.3,.86))
ggsave("Figure2.png", pa+pb+pc+plot_layout(nrow=1), width=12, height=5, dpi=300)

## ---- [10] Trend & climate sensitivity → Supplementary Table S11 -------------
cat("\n[10] Sensitivity to time-trend specification (Supplementary Table S11)\n")
hw_sens <- function(thr, timeterm, clim=FALSE){
  dh$ev <- heat_event(dh$avg_temp, thr)
  rhs <- paste("ev + sin52+cos52+sin26+cos26 +", timeterm)
  if (clim) rhs <- paste(rhs, "+ s(humidity_lag7,k=6)+s(pm10_lag8,k=6)+s(precipitation_lag7,k=6)")
  m <- tryCatch(gam(as.formula(paste("cases ~", rhs)), family=nb(), data=dh, method="REML"), error=function(e) NULL)
  if (is.null(m)) return(NA)
  s <- summary(m)$p.table; if(!"ev" %in% rownames(s)) return(NA); round(exp(s["ev",1]), 2)
}
cat("  Heatwave IRR  | linear  spline  spline+climate\n")
for (thr in HEAT_GRID)
  cat(sprintf("   >=%.1f C    | %5.2f  %5.2f  %5.2f\n", thr,
      hw_sens(thr,"time_idx"), hw_sens(thr,"s(time_idx,k=30)"), hw_sens(thr,"s(time_idx,k=30)",TRUE)))
dlnm_sens <- function(d, timeterm){
  cb <- crossbasis(d$avg_temp, lag=c(0,8), argvar=list(fun="lin"), arglag=list(fun="integer"))
  rhs <- paste("cb + sin52+cos52+sin26+cos26 + s(humidity_lag7,k=6)+s(pm10_lag8,k=6)+s(precipitation_lag7,k=6) +", timeterm)
  m <- tryCatch(gam(as.formula(paste("cases ~", rhs)), family=nb(), data=d, method="REML"), error=function(e) NULL)
  if (is.null(m)) return(c(NA,NA,NA))
  cp <- tryCatch(crosspred(cb, m, at=1, cen=0, cumul=TRUE), error=function(e) NULL); if(is.null(cp)) return(c(NA,NA,NA))
  c((cp$cumRRfit[1,5]-1)*100, (cp$cumRRlow[1,5]-1)*100, (cp$cumRRhigh[1,5]-1)*100)
}
lin <- dlnm_cum(SUB$Post, "avg_temp", c("humidity_lag7","pm10_lag8","precipitation_lag7"), 4)  # glm.nb (= main, [7])
spl <- dlnm_sens(SUB$Post, "s(time_idx,k=30)")                                                 # gam, penalized-spline trend
cat(sprintf("  DLNM Post temp cum-lag4: main (linear time) %+.1f%% [%.1f, %.1f] | penalized-spline time %+.1f%% [%.1f, %.1f]\n",
    lin[1],lin[2],lin[3], spl[1],spl[2],spl[3]))
cat("  => heatwave IRRs broadly preserved under a penalized-spline trend but attenuated by climate adjustment;\n")
cat("     DLNM Post-era temperature point estimate is stable (~+40%) but its significance is not robust to the trend.\n")

cat("\nDone. Outputs: console tables above + Figure2.png\n")
cat("R/session:", R.version.string, "\n")
