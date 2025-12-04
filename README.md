# DEV STEPS
1️⃣ HOME & NAVIGATION MODULE
1. Home Dashboard (Page 1)

A high-level KPI overview.

Sections:

Total Units Sold (BMW / MINI)

Average Selling Price

Days to Sell (per model or overall)

Fastest Dealer by Turnover Rate

Inventory Health Summary

Chart: Sales Trend (12–36 months)

Chart: Discount % by Model

Purpose: Give managers a quick health check of the business.

2️⃣ DATA MANAGEMENT MODULE
2. Upload Sales Data

Components:

File Browse → Load CSV into staging table

Data validation:

No negative values

Dealer/model lookup valid

inventory_end ≥ units

blackout_flag only Y/N

Error report (invalid rows)

Button: “Finalize Load” → Moves valid rows to SALES_HISTORY

Purpose: Allows business users to continuously upload historical data.

3. Sales History Report

Interactive Report or Grid

Filters: Dealer, Model, Year, Promo Flag

KPI badges: Units, Revenue, Avg Price, Avg Discount

Link to transaction details

Purpose: Provides full visibility into raw historical data.

3️⃣ SCENARIO PLANNING MODULE
4. Scenario List

List all user-created scenarios.

Columns:

Scenario Name

Status (Draft, Submitted, Approved, Rejected)

Created By

Created Date

Last Modified

Action Buttons → View, Edit, Copy, Submit

5. Scenario Builder (Scenario Details Page)

Tabs inside:

Tab 1: Scenario Overview

Name

Description

Owner

Status

Tab 2: Add Drivers

Users add future planning assumptions:

Price Elasticity (% impact of price on demand)

Promo Uplift (% sales increase from promotions)

Inventory Cap (max inventory allowed)

Dealer / Model filter (optional)

Start & End month

Purpose: Create What-if conditions.

6. Scenario Driver List / Editor

Interactive grid to manage all drivers inside the scenario.

4️⃣ FORECASTING MODULE
7. Run Forecast

User selects:

Scenario ID

Forecasting Method:

Moving Average + Seasonality

Trend + Seasonality

Forecast horizon (months)

Exclude blackout months? (Yes/No)

Buttons:

Run Forecast (calls PL/SQL package)

Recalculate

8. Forecast Review

Components:

Interactive Report of FORECAST_OUTPUT

Summary KPIs:

Forecast Units

Forecast Revenue

Avg Price

Inventory Utilization

Charts:

Forecast Units by Model

Dealer Comparison

Trend Charts: Histogram, Line chart

Purpose: Allows planners to analyze forecast results.

5️⃣ APPROVAL WORKFLOW MODULE
9. Submit Scenario for Approval

Form changes status from DRAFT → SUBMITTED

10. Approver Worklist

For users with APPROVER role.

Columns:

Scenario Name

Submitted By

Date

Buttons:

Approve

Reject

View Details

11. Approval Page

Shows scenario summary

Shows forecast summary

Approve / Reject with comments

6️⃣ AUDIT & SECURITY MODULE
12. Audit Log Viewer

Shows actions captured in AUDIT_LOG:

Who changed what

Old vs new values

When

Filters: Date range, User, Table.

7️⃣ BONUS MODULES (Optional but Recommended)
13. Planned vs Actual Comparison

Charts + Report:

Dealer-wise variance

Model-wise variance

Highlight >10% deviations

14. Master Data Maintenance

(Optional depending on exam requirements)

Pages:

Manage Dealers

Manage Models

Manage Calendar (exclude months, set blackout flags)

# TEST CASES:
DATA UPLOAD:
✅ 1. File Upload Tests
1.1 File Format Validation
Test	Expected Result
Upload a CSV file	Accepted
Upload Excel (.xlsx) even though only CSV expected	Should block OR convert (depending on your design)
Upload a non-data file (PDF, JPG, ZIP)	Error: "Invalid file type"
Upload empty CSV	Error: “No data found”
2️⃣ File Structure Validation Tests
2.1 Missing Columns
Scenario	Expected Result
Column missing (e.g., units)	Reject file, show error report
Extra columns present	Ignore extras or warning — must be consistent
Wrong column order	Should still work (if header-based parsing)
2.2 Incorrect Column Headers
Scenario	Expected Result
Column name = "Unit" instead of "units"	Error: invalid column
Typo in header	Error identifying missing columns
3️⃣ Data Validation Tests (Critical)

These tests must match the business rules given.

3.1 Numeric Validations
Test	Expected Outcome
units < 0	Error: negative units not allowed
net_price < 0	Error
discount > net_price	Error
3.2 Foreign Key Validations
Test	Expected Outcome
dealer_code not found in DEALERS table	Row rejected
model_code not found in MODELS table	Row rejected
3.3 Inventory Rules
Test	Expected Outcome
units > inventory_end	Error: inventory violation
inventory_end = 0 but units > 0	Error
3.4 Blackout Flag
Test	Expected Outcome
blackout_flag not in {Y, N}	Error
blackout_flag = Y → units > 0	Should either error OR warn (your rule: blackout months excluded from forecasting)
4️⃣ Business Logic Validations
4.1 Date Checks
Test	Expected Outcome
month not in calendar table	Reject row
invalid date format	Reject row
4.2 Duplicate Row Checks
Test	Expected Outcome
Two rows with same dealer + model + month	Should show duplicate error
Upload file twice	Should detect duplicates or prompt "Replace / Append?"
5️⃣ Performance & Limit Tests
5.1 File Size
Test	Expected Outcome
Large file 20,000 rows	Should process within reasonable time
Huge file (100k rows)	Should show progress/error
5.2 Concurrent Uploads

Test two users uploading at same time → ensure no lock conflicts in staging tables.

6️⃣ User Experience Tests
6.1 Success Path
Test	Expected Outcome
All valid rows	Data moved to SALES_HISTORY, success message
6.2 Error Report Quality
Test	Expected Outcome
Error messages show row number, reason	User can fix file and re-upload
6.3 Partial Upload
Test	Expected Outcome
Some valid, some invalid rows	Should show summary: X valid, Y invalid
7️⃣ Security Tests
7.1 Authorization
Test	Expected Outcome
Viewer role tries to upload	Access denied
Planner role uploads	Allowed
Approver role uploads	Should still be allowed
7.2 Audit Logging
Test	Expected Outcome
upload action	Logged with username, timestamp
validation errors	Logged (optional but recommended)
8️⃣ Database Integrity Tests
8.1 Staging Table Behavior

After upload:

Staging table populated?

FAILED rows stay in staging table?

CLEAN rows copied to SALES_HISTORY?

Auto cleanup job working?

8.2 Referential Integrity

After successful load:

FK relations maintained

No orphan dealer/model

No missing calendar date

9️⃣ Regression Tests

After each change, re-run:

Upload success (happy path)

Invalid row rejection

Inventory validation

Blackout month validation

Duplicate logic

⭐ BONUS TEST (Highly Recommended) – Required by Your Case Study
"Upload → Validate → Error Report → Fix → Re-upload" cycle

Use a test file with:

3 valid rows

2 invalid dealer codes

1 wrong blackout_flag

1 negative value

1 duplicate

Expected:

Validation step catches 5 errors

Error report shows exact reason per row

Fix and re-upload → Should pass

This end-to-end flow is demonstration quality.
