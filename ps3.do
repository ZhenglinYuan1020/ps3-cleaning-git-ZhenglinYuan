cd "C:\Users\zheng\OneDrive - University of Texas Southwestern\Desktop\2026 Spring Courses\5105 Introduction to Programming and Software Packages\HW3\pset3_data"

clear all
set more off

import delimited "people_full.csv", clear stringcols(_all) varnames(1)
***Quick sanity checks
describe
count
list in 1/10
misstable summarize
* Trim leading/trailing spaces
replace sex      = strtrim(sex)
replace location = strtrim(location)
* Collapse internal multiple spaces
replace sex      = itrim(sex)
replace location = itrim(location)
* Normalize case
replace sex      = lower(sex)
replace location = lower(location)
***Standardize sex values
replace sex = "female" if sex == "f" | sex == "female"
replace sex = "male"   if sex == "m" | sex == "male"
* Handle missing / invalid entries
replace sex = "" if inlist(sex, ".", "na", "n/a", "unknown", "unk")
tab sex, missing
***Standardize location
* Remove punctuation
replace location = subinstr(location, ".", "", .)
replace location = subinstr(location, ",", "", .)

* Standardize known city variants (edit if more appear)
replace location = "dallas" if inlist(location, "dal", "dallas tx", "dallas texas")

* Handle missing / invalid entries
replace location = "" if inlist(location, ".", "na", "n/a", "unknown", "unk")
tab location, missing

*****Convert the following columns from strings to numeric and handle "NA":person_id household_id age height_cm weight_kg systolic_bp diastolic_bp
* Replace "NA" (and common variants) with empty string
foreach v in person_id household_id age height_cm weight_kg systolic_bp diastolic_bp {
    replace `v' = "" if lower(`v') == "na"
    replace `v' = "" if lower(`v') == "n/a"
    replace `v' = "" if `v' == "."
}
destring person_id household_id, replace
destring age height_cm weight_kg systolic_bp diastolic_bp, replace
describe person_id household_id age height_cm weight_kg systolic_bp diastolic_bp
misstable summarize person_id household_id age height_cm weight_kg systolic_bp diastolic_bp
summarize age height_cm weight_kg systolic_bp diastolic_bp

********Convert date/time fields
* Clean
replace date_str = strtrim(date_str)
replace date_str = "" if lower(date_str) == "na" | lower(date_str) == "n/a" | date_str == "."

* Convert string date (MM/DD/YYYY) -> Stata daily date
gen visit_date = daily(date_str, "MDY")
format visit_date %td

* Check failures (non-missing date_str that didn't convert)
count if date_str != "" & missing(visit_date)
list date_str if date_str != "" & missing(visit_date) in 1/20

* Clean
replace time_str = strtrim(time_str)
replace time_str = "" if lower(time_str) == "na" | lower(time_str) == "n/a" | time_str == "."

* Convert string time -> Stata datetime (ms)
gen double visit_time = clock(time_str, "hms")
format visit_time %tcHH:MM:SS

* Check failures
count if time_str != "" & missing(visit_time)
list time_str if time_str != "" & missing(visit_time) in 1/20
gen people_year = year(visit_date)
tab people_year, missing
summarize visit_date visit_time people_year
list person_id date_str visit_date time_str visit_time people_year in 1/10

*******Run QA checks
* 1) no missing person_id
assert !missing(person_id)
* 2) unique key: person_id people_year
isid person_id people_year
* 3) each non-missing person_id has 5 observations
bysort person_id: assert _N == 5

* Encode sex and location into numeric categorical variables
encode sex, gen(sex_id)
encode location, gen(location_id)

bysort household_id (person_id people_year): gen hh_row = _n
list household_id person_id people_year hh_row in 1/20, sepby(household_id)

bysort household_id: egen hh_mean_age = mean(age)
summarize hh_mean_age
list household_id age hh_mean_age in 1/20, sepby(household_id)

mkdir processed_data
export delimited using "processed_data/ps3_people_clean.csv", replace
import delimited "processed_data/ps3_people_clean.csv", clear
describe



*******************************************************
households.csv (grouped vars, regression, export)
*******************************************************

* Import (all strings)
clear
import delimited "households.csv", clear stringcols(_all) varnames(1)

* Handle "NA" and trim
foreach v in household_id year region_id income hh_size region {
    replace `v' = strtrim(`v')
    replace `v' = itrim(`v')
    replace `v' = "" if inlist(lower(`v'), "na", "n/a", ".")
}

* Convert to numeric
destring household_id year region_id income hh_size, replace

* Encode region
replace region = lower(region)
replace region = "" if region == ""
encode region, gen(region_code)

* Inspect labels
tab region region_code, missing
label list region_code

* Grouped variables
bysort year: egen year_mean_income = mean(income)
bysort region_code year: egen region_year_mean_income = mean(income)
bysort region_code (year): gen region_year_row = _n

* Regression (factor-variable notation)
reg income i.region_code c.hh_size##c.year

* Export cleaned file
capture mkdir processed_data
export delimited using "processed_data/ps3_households_clean.csv", replace

*******************************************************
* Clean and validate regions.csv (panel data)
*******************************************************
* Import (all strings)
clear
import delimited "regions.csv", clear stringcols(_all) varnames(1)

* Trim + handle "NA"
foreach v in region_id year median_income population {
    replace `v' = strtrim(`v')
    replace `v' = itrim(`v')
    replace `v' = "" if inlist(lower(`v'), "na", "n/a", ".")
}

* Convert numeric variables
destring region_id year median_income population, replace

* Drop missing panel keys
drop if missing(region_id) | missing(year)

* Verify unique region_id-year
isid region_id year

* Declare panel structure
xtset region_id year

* Generate YoY change and growth rate (using lag)
gen yoy_change_median_income = median_income - L.median_income
gen median_income_growth_rate = (median_income - L.median_income) / L.median_income

* Panel summaries
xtdescribe
xtsum median_income population yoy_change_median_income median_income_growth_rate

* Export cleaned file

capture mkdir processed_data

export delimited using "processed_data/ps3_regions_clean.csv", replace