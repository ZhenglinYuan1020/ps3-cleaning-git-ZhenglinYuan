****************************************************
* Problem Set 5
* Linear Regression Workflow, Margins, Table Export,
* Nonlinear Terms, and Prediction
****************************************************

clear all
set more off

*--------------------------------------------------*
* 1. Initialize and begin logging
*--------------------------------------------------*
cd "C:\Users\zheng\OneDrive - University of Texas Southwestern\Desktop\2026 Spring Courses\5105 Introduction to Programming and Software Packages\HW5"

* Create folders if they do not already exist
capture mkdir logs
capture mkdir processed_data
capture mkdir lecture_6_pset

* Start log
log using logs/ps5.log, replace

*--------------------------------------------------*
* 2. Load data and verify required variables
*--------------------------------------------------*
use "ps5_data.dta", clear

local required_vars SERIALNO SPORDER ln_wage WAGP AGEP SCHL WKHP PINCP POVPIP ESR COW MAR SEX ///
RAC1P HISP PWGTP NAICSP SOCP NAICSP_id SOCP_id

foreach var of local required_vars {
    confirm variable `var'
    di "Verified variable: `var'"
}

*--------------------------------------------------*
* 3. Short warm-up: univariate and bivariate checks
*--------------------------------------------------*

* Summary statistics
summarize ln_wage WAGP AGEP SCHL WKHP PINCP POVPIP

tabstat ln_wage WAGP AGEP SCHL WKHP PINCP POVPIP, ///
    stats(n mean sd min max) columns(statistics)

* Pairwise correlations with significance
pwcorr ln_wage AGEP SCHL WKHP PINCP POVPIP, sig star(0.05)

* Bivariate plot: ln_wage vs AGEP with fitted line
twoway ///
    (scatter ln_wage AGEP) ///
    (lfit ln_wage AGEP), ///
    title("ln(wage) vs Age") ///
    name(ps5_ln_wage_agep_plot, replace)

graph export processed_data/ps5_ln_wage_agep_plot.png, replace

*--------------------------------------------------*
* 4. Macro-driven linear regressions
*--------------------------------------------------*

local outcome "ln_wage"
local covariates_demo "c.AGEP i.SEX i.RAC1P i.HISP i.MAR"
local covariates_humancap "c.SCHL c.PINCP c.POVPIP"
local covariates_labor "c.WKHP i.ESR i.COW"
local covariates_occ "i.NAICSP_id i.SOCP_id"

local model_covariates "`covariates_demo' `covariates_humancap' `covariates_labor' `covariates_occ'"

di "Outcome variable: `outcome'"
di "Model covariates: `model_covariates'"

* Model 1: demographics only
reg `outcome' `covariates_demo', vce(robust)
estimates store m1

* Model 2: demographics + human capital
reg `outcome' `covariates_demo' `covariates_humancap', vce(robust)
estimates store m2

* Model 3: full baseline model
reg `outcome' `model_covariates', vce(robust)
estimates store m3

*--------------------------------------------------*
* 5. Transformations and nonlinear terms
*--------------------------------------------------*

* Create log hours
gen ln_hours = ln(WKHP)

* Nonlinear model with quadratic age and income
reg `outcome' ///
    c.AGEP##c.AGEP ///
    c.PINCP##c.PINCP ///
    c.ln_hours ///
    i.SEX i.RAC1P i.HISP i.MAR ///
    c.SCHL c.POVPIP ///
    i.ESR i.COW ///
    i.NAICSP_id i.SOCP_id, vce(robust)

estimates store m4

* Mark estimation sample for m4
gen byte in_m4_sample = e(sample)

*--------------------------------------------------*
* 6. Interpret nonlinear terms with margins
*--------------------------------------------------*

margins, at(AGEP = (25(5)64))

marginsplot, ///
    title("Predicted ln(wage) by Age from m4") ///
    name(ps5_margins_age_m4, replace)

graph export processed_data/ps5_margins_age_m4.png, replace

*--------------------------------------------------*
* 7. Export regression table with etable
*--------------------------------------------------*
etable, estimates(m1 m2 m3 m4) ///
    keep(AGEP SEX RAC1P HISP MAR SCHL PINCP POVPIP WKHP ESR COW ln_hours) ///
    cstat(_r_b) cstat(_r_se) ///
    mstat(N) mstat(r2) ///
    export(processed_data/ps5_regression_table.docx, replace)
*--------------------------------------------------*
* 8. Basic prediction block
*--------------------------------------------------*

predict ln_wage_hat, xb
predict resid, residuals

gen wage_hat = exp(ln_wage_hat)
gen abs_error = abs(WAGP - wage_hat)

* Summary statistics for residuals and absolute error
summarize resid abs_error

* Correlation between actual wage and predicted wage
corr WAGP wage_hat

* Export prediction output
export delimited using processed_data/ps5_prediction_output.csv, replace

*--------------------------------------------------*
* 9. Required macro-based keep list
*--------------------------------------------------*

local prediction_vars "ln_hours in_m4_sample ln_wage_hat wage_hat resid abs_error"
local keepvars "`required_vars' `prediction_vars'"

keep `keepvars'

foreach var of local keepvars {
    confirm variable `var'
    di "Kept variable verified: `var'"
}

save processed_data/ps5_analysis_with_predictions.dta, replace

*--------------------------------------------------*
* 10. Finalize
*--------------------------------------------------*
log close