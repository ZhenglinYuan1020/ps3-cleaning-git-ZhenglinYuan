*******************************************************
* PS4/PS5: Real ACS Data Cleaning with Macros (No Git)
* Data: psam_p50.csv (ACS PUMS Vermont person extract)
*******************************************************

clear all
set more off
version 17

*******************************************************
* 1) Initialize + set directory + start log
*******************************************************

* Set working directory (you said you already did this; keep here for reproducibility)
cd "C:\Users\zheng\OneDrive - University of Texas Southwestern\Desktop\2026 Spring Courses\5105 Introduction to Programming and Software Packages\HW4"

* Ensure required folders exist
capture mkdir "logs"
capture mkdir "processed_data"

* Start log
capture log close
log using "logs\ps5.log", replace text

di "=== PS5/PS4 cleaning started on: `c(current_date)' `c(current_time)' ==="
di "Working directory: `c(pwd)'"

*******************************************************
* 2) Import data (do NOT force all columns to strings)
*******************************************************

import delimited "psam_p50.csv", varnames(1) clear
rename *, upper

* Verify > 100 variables

ds
local nvars = r(k)

di "Number of variables in dataset = `nvars'"

assert `nvars' > 100

*******************************************************
* 3) Macros for numeric and categorical vars + cleaning
*******************************************************

* Required numeric subset
local numeric_vars AGEP WAGP WKHP SCHL PINCP POVPIP ESR COW MAR SEX RAC1P HISP ADJINC PWGTP

* Required categorical subset
local categorical_vars NAICSP SOCP

* Display macro contents in the log
di "numeric_vars: `numeric_vars'"
di "categorical_vars: `categorical_vars'"

* --- Loop over numeric_vars ---
foreach v of local numeric_vars {
    capture confirm variable `v'
    if _rc {
        di as error "ERROR: variable `v' not found."
        exit 198
    }

    * If it's string, clean NA/. blanks then destring
    capture confirm string variable `v'
    if !_rc {
        replace `v' = trim(`v')
        replace `v' = "" if inlist(`v', "NA", ".", "")
        destring `v', replace force
    }
    else {
        * already numeric; nothing to do
    }
}

* --- Loop over categorical_vars ---
foreach v of local categorical_vars {
    capture confirm variable `v'
    if _rc {
        di as error "ERROR: variable `v' not found."
        exit 198
    }

    * Ensure string so we can clean formatting consistently
    capture confirm string variable `v'
    if _rc {
        tostring `v', replace usedisplayformat
    }

    * Clean string formatting
    replace `v' = trim(upper(`v'))
    replace `v' = "" if inlist(`v', "NA", ".", "")

    * Encode to new _id var
    encode `v', gen(`v'_id)
}

*******************************************************
* 4) QA checks + save cleaned full file
*******************************************************

* Check missing key fields
misstable summarize SERIALNO SPORDER

* Verify uniqueness of SERIALNO SPORDER
duplicates report SERIALNO SPORDER
capture isid SERIALNO SPORDER
if _rc {
    di as error "ERROR: SERIALNO SPORDER is not unique. Investigate duplicates."
    exit 459
}

save "processed_data\ps5_cleaned_full.dta", replace

*******************************************************
* 5) Sample construction table (postfile) + filters
*******************************************************

tempname posth
tempfile sample_steps

postfile `posth' str40 step_name ///
    long n_remaining long n_excluded using `sample_steps', replace

* Helper locals
local before = _N
post `posth' ("Start: cleaned full") (`before') (0)

* Step 1: keep ages 25–64
local before = _N
keep if inrange(AGEP, 25, 64)
local after = _N
post `posth' ("Keep ages 25-64") (`after') (`before' - `after')

* Step 2: keep WAGP > 0 and WKHP >= 35
local before = _N
keep if WAGP > 0 & WKHP >= 35
local after = _N
post `posth' ("Keep WAGP>0 & WKHP>=35") (`after') (`before' - `after')

* Step 3: keep ESR employed categories (1 or 2)
local before = _N
keep if inlist(ESR, 1, 2)
local after = _N
post `posth' ("Keep ESR in {1,2}") (`after') (`before' - `after')

* Create ln_wage
gen ln_wage = ln(WAGP)

* Step 4: drop missing values in key model covariates + encoded categorical IDs
* (Includes encoded IDs from NAICSP and SOCP per instructions)
local keyvars AGEP WAGP WKHP ESR SCHL PINCP POVPIP SEX COW MAR RAC1P HISP ADJINC PWGTP NAICSP_id SOCP_id ln_wage

local before = _N
foreach v of local keyvars {
    drop if missing(`v')
}
local after = _N
post `posth' ("Drop missing key covariates + cat IDs") (`after') (`before' - `after')

postclose `posth'

* Export sample construction table
use `sample_steps', clear
export delimited using "processed_data\ps5_sample_construction.csv", replace

*******************************************************
* 6) Macros for model specification + QA loops + regressions
*******************************************************

* Reload analysis sample from the cleaned full file to ensure reproducibility
use "processed_data\ps5_cleaned_full.dta", clear

* Re-apply the same sample restrictions (to match the construction output)
keep if inrange(AGEP, 25, 64)
keep if WAGP > 0 & WKHP >= 35
keep if inlist(ESR, 1, 2)

gen ln_wage = ln(WAGP)

* Ensure encoded IDs exist (if someone runs this section alone)
capture confirm variable NAICSP_id
if _rc {
    capture confirm string variable NAICSP
    if _rc tostring NAICSP, replace usedisplayformat
    replace NAICSP = trim(upper(NAICSP))
    replace NAICSP = "" if inlist(NAICSP, "NA", ".", "")
    encode NAICSP, gen(NAICSP_id)
}
capture confirm variable SOCP_id
if _rc {
    capture confirm string variable SOCP
    if _rc tostring SOCP, replace usedisplayformat
    replace SOCP = trim(upper(SOCP))
    replace SOCP = "" if inlist(SOCP, "NA", ".", "")
    encode SOCP, gen(SOCP_id)
}

* Drop missings again
foreach v of local keyvars {
    drop if missing(`v')
}

* Model macros
local outcome ln_wage
local covariates_demo     c.AGEP i.SEX i.MAR i.RAC1P i.HISP
local covariates_humancap i.SCHL c.PINCP c.POVPIP
local covariates_labor    c.WKHP i.ESR i.COW
local covariates_occ      i.NAICSP_id i.SOCP_id

local model_covariates `covariates_demo' `covariates_humancap' `covariates_labor' `covariates_occ'

di "outcome: `outcome'"
di "model_covariates: `model_covariates'"

* QA means/sds loop
local qa_vars AGEP WAGP WKHP PINCP POVPIP
foreach v of local qa_vars {
    quietly summarize `v'
    di "`v'  mean=" %9.3f r(mean) "   sd=" %9.3f r(sd) "   N=" r(N)
}

* Counts for WKHP >= cutoffs
forvalues c = 35(5)60 {
    count if WKHP >= `c'
    di "Count with WKHP >= `c' : " r(N)
}

* Regression specs (use person weight PWGTP as pweight)
estimates clear

regress `outcome' `covariates_demo' [pweight=PWGTP]
estimates store m1

regress `outcome' `covariates_demo' `covariates_humancap' `covariates_labor' [pweight=PWGTP]
estimates store m2

regress `outcome' `model_covariates' [pweight=PWGTP]
estimates store m3

*******************************************************
* 7) Required macro-based keep list + save final analysis data
*******************************************************

local keepvars SERIALNO SPORDER ///
    AGEP WAGP WKHP ln_wage ///
    SCHL PINCP POVPIP ESR COW MAR SEX RAC1P HISP ///
    ADJINC PWGTP ///
    NAICSP_id SOCP_id

* Verify each kept variable exists
foreach v of local keepvars {
    capture confirm variable `v'
    if _rc {
        di as error "ERROR: keep variable `v' not found."
        exit 198
    }
}

* Macro-driven keep (do not hardcode standalone keep list)
keep `keepvars'

save "processed_data\ps5_analysis_data.dta", replace

*******************************************************
* 9) Finalize
*******************************************************

di "=== Done. Outputs written to processed_data/ and logs/ ==="

log close

