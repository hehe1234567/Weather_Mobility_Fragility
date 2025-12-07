*** raw data

***1, converting date format
gen date_td = date(date, "YMD")   
format date_td %td                    

gen month=month(date_td)
destring wind_class, replace ignore("级")
destring wind_dir,replace


***2, define weekday
gen dow=dow(date_td)

gen holiday = inlist(date_td, ///
td(29sep2023), td(30sep2023), td(01oct2023), td(02oct2023), td(03oct2023), td(04oct2023), td(05oct2023), td(06oct2023), ///
td(30dec2023), td(31dec2023), td(01jan2024), ///
td(10feb2024), td(11feb2024), td(12feb2024), td(13feb2024), td(14feb2024), td(15feb2024), td(16feb2024), td(17feb2024), ///
td(04apr2024), td(05apr2024), td(06apr2024), ///
td(01may2024), td(02may2024), td(03may2024), td(04may2024), td(05may2024), ///
td(08jun2024), td(09jun2024), td(10jun2024))

gen other_day=1 if holiday==0

gen weekday=1 if dow>0 & dow<6 & other_day==1
replace weekday=0 if weekday==.

replace weekday=1 if other_day == inlist(date_td, ///
td(07oct2023), td(08oct2023), ///
td(04feb2024), td(18feb2024), ///
td(07apr2024), ///
td(28apr2024), td(11may2024))

gen weekend= other_day - weekday
replace weekend=0 if weekend==.


***3, constructing speed - inverse square distance
bys station_id date hour: egen wsum = total(1/(distance_to_station^2))
gen  w = (1/(distance_to_station^2)) / wsum
gen  contrib = w * speed
bys station_id date hour: egen speed_d = total(contrib)

* inverse distance
bys station_id date hour: egen wsum1 = total(1/(distance_to_station))
gen  w1 = (1/(distance_to_station)) / wsum1
gen  contrib1 = w1 * speed
bys station_id date hour: egen speed_d1 = total(contrib1)

* Average speed
bys station_id date hour: egen speed_avg = mean(speed)

* Average speed within 1km 
replace speed=. if distance_to_station>1000
bys station_id date hour: egen speed_avg_1k = mean(speed)

* Speed gap and ratio between two routes
bys station_id road_id date hour: egen speed_min_r = min(speed)
bys station_id road_id date hour: egen speed_max_r = max(speed)

gen speed_gap_r   = speed_max_r - speed_min_r
gen speed_ratio_r = speed_min_r / speed_max_r if speed_max_r>0

* minimum speed at road level
gen contrib_min2 = w * speed_min_r
bys station_id date hour: egen speed_min_d2 = total(contrib_min2)

bys station_id date hour: egen has_min = max(!missing(speed_min_r))
replace speed_min_d2 = . if has_min==0
drop has_min

* speed difference between two routes 
gen contrib_gap2 = w * speed_gap_r
bys station_id date hour: egen gap_d2 = total(contrib_gap2)

bys station_id date hour: egen has_gap = max(!missing(speed_gap_r))
replace gap_d2 = . if has_gap==0
drop has_gap

* speed ratio betwen two routes
gen contrib_ratio2 = w * speed_ratio_r
bys station_id date hour: egen ratio_d2 = total(contrib_ratio2)

bys station_id date hour: egen has_ratio = max(!missing(speed_ratio_r))
replace ratio_d2 = . if has_ratio==0
drop has_ratio


***4 converting air-station level data
drop route_id road_id speed distance_to_station direction_to_station wsum w contrib wsum1 w1 contrib1 speed_min_r speed_max_r speed_gap_r speed_ratio_r contrib_min2 contrib_gap2 contrib_ratio2

duplicates drop

*constructing variables
encode city,gen (city_id)
encode weather, gen (weather_id)

Robustness Check/ Placebo test - 
gen lnspeed_d1=ln(speed_d1)
gen lnspeed_avg=ln(speed_avg)
gen lnspeed_1k=ln(speed_avg_1k)
gen lnspeed_min = ln(speed_min_d2)

gen hour_peak = .
replace hour_peak = 1 if inrange(hour,7,9)    // morning peak
replace hour_peak = 1 if inrange(hour,17,19)  // evening peak
replace hour_peak =0 if hour_peak==.

gen daytime=1 if hour>=7 & hour<= 19
replace daytime=0 if daytime==.

*generate early morning speed
bys station_id date: egen early_speed_d = mean(cond(inrange(hour,1,4), speed_d, .))

*congestion measures
gen gap_ff = early_speed_d - speed_d
gen ln_gap_ff = ln(early_speed_d) - ln(speed_d)
gen congestion_ratio = gap_ff/early_speed_d


***5. Grouping weather variables
gen weather_group = .

* 1. Clear (baseline)
replace weather_group = 1 if weather=="晴"
* 2. Cloud/Fog group
replace weather_group = 2 if inlist(weather, ///
    "多云", "阴", "雾", "大雾", "浓雾")

* 3. Light rain
replace weather_group = 3 if inlist(weather, ///
    "小雨", "中雨")

* 4. Heavy rain
replace weather_group = 4 if inlist(weather, ///
    "大雨", "暴雨")

* 5. Snow
replace weather_group = 5 if inlist(weather, ///
    "小雪","中雪","大雪","暴雪")

* 6. Dust/Haze/Special
replace weather_group = 6 if inlist(weather, ///
    "扬沙", "浮尘", "沙尘暴", "霾", "雨夹雪", "雷阵雨")

label define wgroup ///
    1 "Clear" ///
    2 "Cloud/Fog" ///
    3 "Light rain" ///
    4 "Heavy rain" ///
    5 "Snow" ///
    6 "Dust/Haze/Special"
label values weather_group wgroup

*wind variable
gen wind_group = .

* Group 1: Low wind (0-2)
replace wind_group = 1 if inrange(wind_class, 0, 2)

* Group 2: Moderate wind (3-4)
replace wind_group = 2 if inrange(wind_class, 3, 4)

* Group 3: High wind (5-14)
replace wind_group = 3 if inrange(wind_class, 5, 14)

label define windg ///
    1 "Low wind (0-2)" ///
    2 "Moderate wind (3-4)" ///
    3 "High wind (>=5)"
label values wind_group windg


***6 - Table 1- Baseline
reghdfe lnspeed_d temperature humidity, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_1.xls,keep (temperature humidity)

reghdfe lnspeed_d temperature humidity i.weather_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_1.xls,keep (temperature humidity i.weather_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_1.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group, absorb(station_id dow#hour month) vce(cluster county_id)
outreg2 using table_1.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#date_td hour) vce(cluster county_id)
outreg2 using table_1.xls,keep (temperature humidity i.weather_group i.wind_group)


***7 - Appendix Table A1- robustness
reghdfe lnspeed_d1 temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A1.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_avg temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A1.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_1k temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A1.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_min temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A1.xls,keep (temperature humidity i.weather_group i.wind_group)


***8 Table A2- congestion
reghdfe ln_gap_ff temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A2.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe congestion_ratio temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A2.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe gap_d2 temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A2.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe ratio_d2 temperature humidity i.weather_group i.wind_group, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A2.xls,keep (temperature humidity i.weather_group i.wind_group)



***9 Table A3- peak hour
reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if hour_peak==1, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A3.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if hour_peak==0, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A3.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe congestion_ratio temperature humidity i.weather_group i.wind_group if hour_peak==1, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A3.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe congestion_ratio temperature humidity i.weather_group i.wind_group if hour_peak==0, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A3.xls,keep (temperature humidity i.weather_group i.wind_group)


***10 - Figure 1	
* Panel A
* 1. calculating hour × weather_group 
collapse (mean) speed_d, by(hour weather_group)
* 2. sunny day baseline speed
bysort hour: egen base_clear = max(cond(weather_group==1, speed_d, .))
* 3. relative speed to sunny day
gen diff_speed = speed_d - base_clear
* 4. 5 weather conditions
keep if inlist(weather_group, 2, 3, 4, 5, 6)
* 5. Figure
twoway ///
    (line diff_speed hour if weather_group==5, ///
        lpattern(dash) lwidth(medium) lcolor(blue)) ///
    (line diff_speed hour if weather_group==4, ///
        lpattern(dash) lwidth(medium) lcolor(gs8)) ///
    (line diff_speed hour if weather_group==3, ///
        lpattern(dash) lwidth(medium) lcolor(red)) ///
    (line diff_speed hour if weather_group==2, ///
        lpattern(dash) lwidth(medium) lcolor(green)) ///
    (line diff_speed hour if weather_group==6, ///
        lpattern(dash) lwidth(medium) lcolor(purple)) ///
 , ///
    ytitle("Speed difference vs clear (km/h)") ///
    xtitle("Hour of day") ///
    xlabel(0(2)23, labsize(small)) ///
    legend(order(1 "Snow" 2 "Heavy rain" 3 "Light rain" 4 "Cloud/Fog" 5 "Dust/Haze") ///
           pos(6) ring(0) cols(3) size(small) region(lstyle(none))) ///
    plotregion(margin(10 5 20 5)) ///
    graphregion(margin(5 5 5 5)) ///
    name(fig2_hourly_diff_speed, replace)
	 
*Panel B
preserve
collapse (mean) congestion_ratio, by(hour weather_group)
bysort hour: egen base_clear = max(cond(weather_group==1, congestion_ratio, .))
gen diff_cong = congestion_ratio - base_clear
keep if inlist(weather_group, 2, 3, 4, 5, 6)
label define wlabel 2 "Cloud/Fog" 3 "Light rain" 4 "Heavy rain" 5 "Snow" 6 "Dust/Haze"
label values weather_group wlabel

twoway ///
    (line diff_cong hour if weather_group==5, ///
        lpattern(solid)   lwidth(medthick) lcolor(red)) ///
    (line diff_cong hour if weather_group==4, ///
        lpattern(solid)   lwidth(medium)   lcolor(blue)) ///
    (line diff_cong hour if weather_group==3, ///
        lpattern(dash)    lwidth(medium)   lcolor(gs8)) ///
    (line diff_cong hour if weather_group==2, ///
        lpattern(dash)    lwidth(medium)   lcolor(green)) ///
    (line diff_cong hour if weather_group==6, ///
        lpattern(dash)    lwidth(medium)   lcolor(purple)) ///
 , ///
    ytitle("Congestion increase vs clear") ///
    xtitle("Hour of day") ///
    xlabel(0(2)23, labsize(small)) ///
    legend(order(1 "Snow" 2 "Heavy rain" 3 "Light rain" 4 "Cloud/Fog" 5 "Dust/Haze") ///
           pos(6) ring(0) cols(3) size(small) region(lstyle(none))) ///
    title("Hourly Weather-Induced Congestion Increases") ///
    plotregion(margin(10 5 20 5)) ///
    graphregion(margin(5 5 20 5)) ///
    name(fig_hourly_congestion_diff, replace)


***11 Table A4- more heterogenous effects
gen summer=1 if month<10 & month>3
replace summer=0 if summer==.

* urban
gen urban = strpos(county, "区") > 0

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if weekday==1, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A4.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if weekday==0, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A4.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if daytime==1, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A4.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if daytime==0, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A4.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if summer==1, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A4.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if summer==0, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A4.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if urban==1, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A4.xls,keep (temperature humidity i.weather_group i.wind_group)

reghdfe lnspeed_d temperature humidity i.weather_group i.wind_group if urban==0, absorb(station_id city_id#hour month) vce(cluster county_id)
outreg2 using table_A4.xls,keep (temperature humidity i.weather_group i.wind_group)


***12 - Figure 2
* Panel A
preserve

* 1. light rain + heavy rain, snow
keep if inlist(weather_group, 1, 4, 5)

* 2. 10 decile bin
drop if missing(congestion_ratio) | missing(speed_d)
xtile bin_gap = congestion_ratio, nq(10)

* 3. clear day baseline speed
bysort bin_gap: egen speed_clear = mean(cond(weather_group==1, speed_d, .))
bysort bin_gap: egen base_clear  = max(speed_clear)

* 4. rain and snow
gen rain = inlist(weather_group, 4)
gen snow = (weather_group==5)

* 5. keep observation
keep if rain==1 | snow==1

* 6. relative speed
gen diff_speed = speed_d - base_clear

* 7. bin weather
collapse (mean) diff_speed, by(bin_gap rain snow)

* 8. Nonlinear Effect
twoway ///
    (connected diff_speed bin_gap if snow==1, ///
        msymbol(O)   mcolor(red)   lcolor(red)   lwidth(medthick)) ///
    (connected diff_speed bin_gap if rain==1, ///
        msymbol(T)   mcolor(blue)  lcolor(blue)  lwidth(medthick)) ///
, ///
    legend(order(1 "Snow" 2 "Heavy Rain") ///
           pos(6) ring(0) cols(2)) ///
    xtitle("Congestion Level (Decile of Congestion Ratio)") ///
    ytitle("Speed Reduction vs Clear (km/h)") ///
    xlabel(1(1)10, labsize(small)) ///
    title("Nonlinear Amplification of Weather Effects") ///
    name(fig2_nonlin_congestion, replace)

restore	

* Panel B
preserve

* 1. light rain + heavy rain, snow
keep if inlist(weather_group, 1, 3, 4, 5)

* 2. 10 decile bin
drop if missing(congestion_ratio) | missing(speed_d)
xtile bin_gap = congestion_ratio, nq(10)

* 3. clear day baseline speed
bysort bin_gap: egen speed_clear = mean(cond(weather_group==1, speed_d, .))
bysort bin_gap: egen base_clear  = max(speed_clear)

* 4. rain and snow
gen rain = inlist(weather_group, 3, 4)
gen snow = (weather_group==5)

* 5. keep observation
keep if rain==1 | snow==1

* 6. relative speed
gen diff_speed = speed_d - base_clear

* 7. bin weather
collapse (mean) diff_speed, by(bin_gap rain snow)

* 8. Nonlinear Effect
twoway ///
    (connected diff_speed bin_gap if snow==1, ///
        msymbol(O)   mcolor(red)   lcolor(red)   lwidth(medthick)) ///
    (connected diff_speed bin_gap if rain==1, ///
        msymbol(T)   mcolor(blue)  lcolor(blue)  lwidth(medthick)) ///
, ///
    legend(order(1 "Snow" 2 "Light/Heavy Rain") ///
           pos(6) ring(0) cols(2)) ///
    xtitle("Congestion Level (Decile of Congestion Ratio)") ///
    ytitle("Speed Reduction vs Clear (km/h)") ///
    xlabel(1(1)10, labsize(small)) ///
    title("Nonlinear Amplification of Weather Effects") ///
    name(fig2_nonlin_congestion, replace)

restore	


***13 - Constructing Fragile Index - county level
preserve
gen snow_light  = (weather=="小雪")
gen snow_mod    = (weather=="中雪")
gen snow_heavy  = (weather=="大雪")
gen snow_bliz   = (weather=="暴雪")
gen sleet       = (weather=="雨夹雪")	
	
gen rain_light  = (weather=="小雨")
gen rain_mod    = (weather=="中雨")
gen rain_heavy  = (weather=="大雨")
gen rain_storm  = (weather=="暴雨")
gen rain_thunder= (weather=="雷阵雨")	

gen fog         = (weather=="雾")
gen dense_fog   = (weather=="大雾" | weather=="浓雾")
gen haze        = (weather=="霾")
gen dust_storm  = (weather=="沙尘暴")
gen dust        = (weather=="扬沙" | weather=="浮尘")	
	
gen strong_wind = (wind_class>=4)
gen mid_wind    = (wind_class>=2 & wind_class<4)	
	
collapse (sum) snow_light snow_mod snow_heavy snow_bliz sleet ///
              rain_light rain_mod rain_heavy rain_storm rain_thunder ///
              fog dense_fog haze dust_storm dust ///
          (mean) wind_class ///
          , by(city city_id county county_id)	
	
* Snow Severity
gen snow_sev = 4*snow_bliz  ///
             + 3*snow_heavy ///
             + 2*snow_mod   ///
             + 1*snow_light ///
             + 2*sleet

* Rain Severity
gen rain_sev = 3*rain_storm ///
             + 2*rain_heavy ///
             + 1*rain_mod   ///
             + 0.5*rain_light ///
             + 1*rain_thunder

* Visibility Severity
gen vis_sev = 3*dust_storm ///
            + 2*dust       ///
            + 2*dense_fog  ///
            + 1*fog        ///
            + 1*haze
	
pca snow_sev rain_sev vis_sev
predict weather_index

**back to raw data, computing normalized fragility -- county level
collapse (mean) congestion_ratio, by(city_id county_id)

reg congestion_ratio weather_index, robust
predict fragility_resid, resid

sum fragility_resid
gen fragility_std = (fragility_resid - r(mean)) / r(sd)

sum fragility_std

**merge county level statistics
gen density = pop / area
gen gdp_per=gdp/pop

gen log_pop = ln(pop)
gen log_gdp_per=ln(gdp_per)
gen log_density=ln(density)


***14, Table 2- Column 1- 3, County Level Regression
reg fragility_std log_pop log_gdp_per log_density, cluster(city_id)
outreg2 using table_2.xls,keep (log_pop log_gdp_per log_density)

reghdfe fragility_std log_pop log_gdp_per log_density, absorb(city_id) cluster(city_id)
outreg2 using table_2.xls,keep (log_pop log_gdp_per log_density)

reg fragility_std log_pop log_gdp_per log_density latitude, cluster(city_id)
outreg2 using table_2.xls,keep (log_pop log_gdp_per log_density latitude)


***15 Figure A1 - Panel A - Fragile vs county density 
*county level
preserve

keep county_id fragility_std log_density
drop if missing(fragility_std, log_density)
duplicates drop

twoway ///
    (scatter fragility_std log_density, ///
        msymbol(o) msize(small) mcolor(gs12)) ///
    (lfit fragility_std log_density, ///
        lcolor(black) lwidth(medthick)) ///
, ///
    xtitle("Log population density") ///
    ytitle("Transport fragility (std units)") ///
    title("Panel A. County-level relationship") ///
    name(figA1_county_density, replace)

restore


***16 Figure A2 - Panel A
preserve

keep county_id congestion_ratio weather_index
drop if missing(congestion_ratio, weather_index)
duplicates drop

twoway ///
    (scatter congestion_ratio weather_index, ///
        msymbol(o) msize(small) mcolor(gs10)) ///
    (lfit congestion_ratio weather_index, ///
        lcolor(black) lwidth(medthick)) ///
, ///
    xtitle("Weather exposure index") ///
    ytitle("Average congestion ratio") ///
    title("Panel A. Weather exposure and average congestion") ///
    name(Fig_A2_weather_cong, replace)

restore


***17, generate city level data from county level
gen snow_light  = (weather=="小雪")
gen snow_mod    = (weather=="中雪")
gen snow_heavy  = (weather=="大雪")
gen snow_bliz   = (weather=="暴雪")
gen sleet       = (weather=="雨夹雪")	
	
gen rain_light  = (weather=="小雨")
gen rain_mod    = (weather=="中雨")
gen rain_heavy  = (weather=="大雨")
gen rain_storm  = (weather=="暴雨")
gen rain_thunder= (weather=="雷阵雨")	

gen fog         = (weather=="雾")
gen dense_fog   = (weather=="大雾" | weather=="浓雾")
gen haze        = (weather=="霾")
gen dust_storm  = (weather=="沙尘暴")
gen dust        = (weather=="扬沙" | weather=="浮尘")	
	
gen strong_wind = (wind_class>=4)
gen mid_wind    = (wind_class>=2 & wind_class<4)	
	
collapse (sum) snow_light snow_mod snow_heavy snow_bliz sleet ///
              rain_light rain_mod rain_heavy rain_storm rain_thunder ///
              fog dense_fog haze dust_storm dust ///
          (mean) wind_class ///
          , by(city city_id)	
		
* Snow Severity
gen snow_sev = 4*snow_bliz  ///
             + 3*snow_heavy ///
             + 2*snow_mod   ///
             + 1*snow_light ///
             + 2*sleet

* Rain Severity
gen rain_sev = 3*rain_storm ///
             + 2*rain_heavy ///
             + 1*rain_mod   ///
             + 0.5*rain_light ///
             + 1*rain_thunder

* Visibility Severity
gen vis_sev = 3*dust_storm ///
            + 2*dust       ///
            + 2*dense_fog  ///
            + 1*fog        ///
            + 1*haze
	
pca snow_sev rain_sev vis_sev
predict weather_index

*save city - level data

*back to raw data, computing normalized fragility -- city level
collapse (mean) congestion_ratio, by(city city_id)

**merge 
reg congestion_ratio weather_index, robust
predict fragility_resid, resid

sum fragility_resid
gen fragility_std = (fragility_resid - r(mean)) / r(sd)

sum fragility_std

* 
collapse (mean) latitude longtitude, by(city city_id)

collapse (mean) density [aw=pop] ///
    , by(city city_id)		

save city_level_density, replace
	   
*merge to city level data
 merge 1:1 city using "C:\E\Research\Paper\UnderReview\Speed_pollution\Weather_speed\data\join\city_2023_merge.dta"
 
		
***18, city level data
gen log_pop = ln(pop)
gen log_gdp = ln(gdp)
gen log_gdp_per = ln(gdp_per)
gen log_road = ln(road)
gen log_highway = ln(highway)
gen share_tertiary = gdp_third / gdp		

gen log_density = ln(density)	

*Table 2- Column 4-6
* baseline
reg fragility_std log_pop log_gdp_per log_density latitude, r
outreg2 using table_2.xls,keep (log_pop log_gdp_per log_density latitude)

* industry
reg fragility_std share_tertiary log_pop log_gdp_per latitude, r
outreg2 using table_2.xls,keep (share_tertiary log_pop log_gdp_per latitude)

* road
reg fragility_std log_road log_highway log_density log_pop log_gdp_per, r
outreg2 using table_2.xls,keep (log_road log_highway log_density log_pop log_gdp_per)


***19 Figure A1- Panel B
preserve

keep city city_id fragility_std log_density
drop if missing(fragility_std, log_density)
duplicates drop

twoway ///
    (scatter fragility_std log_density, ///
        msymbol(o) msize(small) mcolor(gs10)) ///
    (lfit fragility_std log_density, ///
        lcolor(black) lwidth(medthick)) ///
, ///
    xtitle("Log population density") ///
    ytitle("Transport fragility (std units)") ///
    title("Panel B. City-level relationship") ///
    name(figA1B_city_density, replace)

restore

***Figure A2 - Panel B
preserve

keep city_id congestion_ratio weather_index
drop if missing(congestion_ratio, weather_index)
duplicates drop

twoway ///
    (scatter congestion_ratio weather_index, ///
        msymbol(o) msize(small) mcolor(gs10)) ///
    (lfit congestion_ratio weather_index, ///
        lcolor(black) lwidth(medthick)) ///
, ///
    xtitle("Weather exposure index") ///
    ytitle("Average congestion ratio") ///
    title("Panel B. Weather exposure and average congestion") ///
    name(FigA2B_weather_cong, replace)

restore


***20 - Figure 3
gen north = inlist(city_id, 5,6,14,16,17,18, 22,30,32,36,38,42,44,47,49)

preserve

keep city_en city_id fragility_std
duplicates drop

* 2. ranking fragility
gsort -fragility_std
gen order = _n

* 3. cities in the north
gen north = inlist(city_id, 5,6,14,16,17,18, 22,30,32,36,38,42,44,47,49)

* 4. city name as value
capture label drop citylbl
label define citylbl 1 "`=city_en[1]'", replace
forvalues i = 2/`=_N' {
    label define citylbl `i' "`=city_en[`i']'", add
}
label values order citylbl

* 5. red-north cities
twoway ///
    (bar fragility_std order if north==0, ///
        horizontal barwidth(0.6) color(gs12)) ///
    (bar fragility_std order if north==1, ///
        horizontal barwidth(0.6) color(red)) ///
, ///
    ylabel(1(1)`=_N', valuelabel labsize(1.5) angle(horizontal)) ///
    ysc(reverse) ///
    legend(order(1 "South cities" 2 "North cities") pos(6) cols(2)) ///
    xtitle("Transport Fragility Index (std units)") ///
    title("City-Level Transport Fragility Ranking") ///
    name(fig3_fragility_ranking, replace)

restore