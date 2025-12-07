CREATE OR REPLACE PROCEDURE RUN_FORECAST (

    p_driver_id IN NUMBER
    -- v_method      IN VARCHAR2          -- 'MA_SEASON' or 'TREND_SEASON'
) AS
    ------------------------------------------------------------------
    -- Scenario variables
    ------------------------------------------------------------------
    v_start_month     DATE;
    v_end_month     DATE;
    v_horizon         NUMBER;
    v_elasticity      NUMBER;
    v_promo_uplift    NUMBER;
    v_inventory_cap   NUMBER;
    v_method VARCHAR2(20);
    v_scenario_id NUMBER;
    v_scenario_dealer VARCHAR2(20);

    ------------------------------------------------------------------
    -- Historical arrays
    ------------------------------------------------------------------
    TYPE numlist IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    hist_units       numlist;
    hist_months      numlist;
    season_factor    numlist;

    v_count NUMBER;
    v_avg_units NUMBER;
    v_slope NUMBER;
    v_intercept NUMBER;

    -- v_curr_month DATE := TRUNC(SYSDATE, 'MM');

    v_season_avg NUMBER := 0;

    ------------------------------------------------------------------
    -- Cursor for dealer selection
    ------------------------------------------------------------------
    CURSOR c_dealers IS
    SELECT dealer_code
    FROM bmw_dealers
    WHERE (v_scenario_dealer IS NULL OR dealer_code = v_scenario_dealer);

        
BEGIN
    ------------------------------------------------------------------
    -- Load scenario settings
    ------------------------------------------------------------------

SELECT scenario_id
INTO v_scenario_id
FROM bmw_fp_scenario_drivers
WHERE driver_id = p_driver_id;

    SELECT 
           NVL(price_elasticity,0),
           NVL(promo_uplift,0),
           NVL(inventory_cap,999999),
           FORECAST_METHOD
    INTO   
           v_elasticity,
           v_promo_uplift,
           v_inventory_cap,
           v_method
        
    FROM bmw_fp_scenario_drivers
    WHERE driver_id = p_driver_id
    AND ROWNUM = 1;

    SELECT start_month,
            end_month,
           forecast_horizon,
           dealer_code
    INTO   v_start_month,
            v_end_month,
           v_horizon,
           v_scenario_dealer
    FROM bmw_fp_scenarios
    WHERE scenario_id = v_scenario_id
    AND ROWNUM = 1;

    


    ------------------------------------------------------------------
    -- Remove past forecast results
    ------------------------------------------------------------------
    DELETE FROM bmw_forecast_output 
WHERE scenario_id = v_scenario_id
  AND driver_id   = p_driver_id;


    ------------------------------------------------------------------
    -- Loop through dealers
    ------------------------------------------------------------------
 FOR d IN c_dealers LOOP
    FOR m IN (
        SELECT model_code
        FROM bmw_models
    ) LOOP


        ------------------------------------------------------------------
        -- Load historical sales for dealer
        ------------------------------------------------------------------
        hist_units.DELETE;
        hist_months.DELETE;

        SELECT 
    SUM(units) AS units,
    TO_NUMBER(TO_CHAR(date_value,'YYYYMM')) 
BULK COLLECT INTO hist_units, hist_months
FROM bmw_sales_history
WHERE date_value >= v_start_month
  AND date_value < v_end_month
  AND model_code = m.model_code
  AND (v_scenario_dealer IS NULL OR dealer_code = v_scenario_dealer)
GROUP BY TO_CHAR(date_value,'YYYYMM')
ORDER BY TO_CHAR(date_value,'YYYYMM');


        v_count := hist_units.COUNT;

        ------------------------------------------------------------------
-- FIX MISSING MONTHS (MEAN IMPUTATION)
------------------------------------------------------------------
DECLARE
    v_month_cursor DATE := v_start_month;
    v_last_hist DATE := ADD_MONTHS(v_end_month, -1);
    v_map_units  NUMBER;
    v_map_exists BOOLEAN;
    v_temp_units numlist;
    v_temp_months numlist;
    idx PLS_INTEGER := 0;
BEGIN
    -- Build a complete monthly sequence
    WHILE v_month_cursor <= v_last_hist LOOP
        idx := idx + 1;

        v_map_exists := FALSE;
        v_map_units := 0;

        -- Search if this month exists in BULK COLLECT data
        FOR i IN 1..v_count LOOP
            IF hist_months(i) = TO_NUMBER(TO_CHAR(v_month_cursor,'YYYYMM')) THEN
                v_map_units := hist_units(i);
                v_map_exists := TRUE;
                EXIT;
            END IF;
        END LOOP;

        -- If month missing → mean impute
       IF NOT v_map_exists THEN
    SELECT NVL(AVG(units), 0)
    INTO v_map_units
    FROM bmw_sales_history
    WHERE date_value >= v_start_month
      AND date_value < v_end_month
      AND model_code = m.model_code
      AND (v_scenario_dealer IS NULL OR dealer_code = v_scenario_dealer);
END IF;


        -- Insert into temporary arrays
        v_temp_units(idx) := v_map_units;
        v_temp_months(idx) := TO_NUMBER(TO_CHAR(v_month_cursor,'YYYYMM'));

        v_month_cursor := ADD_MONTHS(v_month_cursor, 1);
    END LOOP;

    -- Overwrite original arrays
    hist_units := v_temp_units;
    hist_months := v_temp_months;
    v_count := idx;
END;

        IF v_count < 6 THEN
            CONTINUE;
        END IF;


        ------------------------------------------------------------------
        -- Compute seasonality factors (average per month)
        ------------------------------------------------------------------
        DECLARE
            s NUMBER;
            c NUMBER;
        BEGIN
            FOR mon IN 1..12 LOOP
                s := 0; c := 0;

                FOR i IN 1..v_count LOOP
                    IF MOD(hist_months(i),100) = mon THEN
                        s := s + hist_units(i);
                        c := c + 1;
                    END IF;
                END LOOP;

                IF c > 0 THEN
                    season_factor(mon) := s/c;
                ELSE
                    season_factor(mon) := 1;
                END IF;
            END LOOP;
        END;

        ------------------------------------------------------------------
        -- Compute seasonality average
        ------------------------------------------------------------------
        v_season_avg := 0;
        FOR mon2 IN 1..12 LOOP
            v_season_avg := v_season_avg + season_factor(mon2);
        END LOOP;
        v_season_avg := v_season_avg / 12;

        ------------------------------------------------------------------
        -- TREND CALCULATION
        ------------------------------------------------------------------
        IF v_method = 'TREND_SEASON' THEN
            DECLARE
                sumX NUMBER := 0;
                sumY NUMBER := 0;
                sumXY NUMBER := 0;
                sumXX NUMBER := 0;
            BEGIN
                FOR i IN 1..v_count LOOP
                    sumX := sumX + i;
                    sumY := sumY + hist_units(i);
                    sumXY := sumXY + (i * hist_units(i));
                    sumXX := sumXX + (i*i);
                END LOOP;

                v_slope :=
                    (v_count * sumXY - sumX * sumY) /
                    (v_count * sumXX - sumX * sumX);

                v_intercept :=
                    (sumY - v_slope * sumX) / v_count;
            END;
        END IF;

        ------------------------------------------------------------------
        -- Moving average baseline
        ------------------------------------------------------------------
        IF v_method = 'MA_SEASON' THEN
            v_avg_units :=
                (hist_units(v_count) +
                 hist_units(v_count-1) +
                 hist_units(v_count-2)) / 3;
        END IF;

      ------------------------------------------------------------------
-- FORECAST LOOP  (DATE-BASED VERSION)
------------------------------------------------------------------
FOR h IN 1..v_horizon LOOP
    DECLARE
        v_fc NUMBER;

        -- Future forecast month: first day of each projected period
        v_future_date DATE := ADD_MONTHS(TRUNC(v_end_month,'MM'), h);

        -- Extract month as number (1–12) for seasonality lookup
        v_month NUMBER := TO_NUMBER(TO_CHAR(v_future_date, 'MM'));
    BEGIN
        ------------------------------------------------------
        -- BASE FORECAST
        ------------------------------------------------------
        IF v_method = 'MA_SEASON' THEN
            v_fc := v_avg_units *
                    (season_factor(v_month) / v_season_avg);
        ELSE
            v_fc :=
                (v_intercept + v_slope*(v_count + h)) *
                (season_factor(v_month) / v_season_avg);
        END IF;

        ------------------------------------------------------
        -- APPLY SCENARIO ADJUSTMENTS
        ------------------------------------------------------
        v_fc := v_fc * (1 + v_promo_uplift);
        v_fc := v_fc * (1 + v_elasticity);

        IF v_fc > v_inventory_cap THEN
            v_fc := v_inventory_cap;
        END IF;

        ------------------------------------------------------
        -- INSERT FORECAST AS DATE TYPE
        ------------------------------------------------------
        INSERT INTO bmw_forecast_output (
            scenario_id, driver_id, dealer_code, date_value,model_code, forecast_units
        ) VALUES (
            v_scenario_id,
            p_driver_id,
            d.dealer_code,
            v_future_date,             -- now a DATE, not a number
            m.model_code,
            ROUND(v_fc)
        );
    END;
END LOOP;
-- END LOOP;
END LOOP;  -- model loop
END LOOP;  -- dealer loop


    COMMIT;
END;


