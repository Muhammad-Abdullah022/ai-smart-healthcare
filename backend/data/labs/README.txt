Punjab Pakistan lab research package — full target geography
Prepared: 2026-11-08

Target geography:
- 10 divisions as supplied by user
- 41 district labels as supplied by user
- 136 unique city/tehsil labels after deduplication

Files:
1. all_target_cities_tehsils.csv
   All requested city/tehsil locations with research status and the official PHC directory as a starting source.
2. sourced_lab_records_starter.csv
   Initial sourced lab records gathered so far. This is NOT a complete list for the full target geography.
3. sourced_test_prices_starter.csv
   Initial published price rows gathered so far. Prices are sourced from listed public pages/PDFs; currentness must be reconfirmed with the branch.

Critical limitation:
The full city list is represented, but the actual lab and price extraction is NOT complete for every city/tehsil. Do not treat zero counts or blank fields as proof that no labs exist. This package explicitly marks gaps rather than inventing data.

Primary source:
Punjab Healthcare Commission registered labs directory:
https://os.phc.org.pk/Registered_Labs.aspx

Price sources included in the starter records may include:
- Chughtai Lab official test list: https://staging.chughtailab.com/test-list/
- THQ Hospital Chishtian pathology page: https://www.thqcht.punjab.gov.pk/pathology
- Punjab Rangers Teaching Hospital: https://prth.com.pk/testpanels/
- Punjab Laboratories & Genetic Centre rate-list PDF:
  https://plgenetics.com/wp-content/uploads/2025/06/Punjab-Lab-Pathology-rate-list-Final-1.pdf

Recommendation:
Use separate tables for locations, labs/branches, standardized tests, lab_test_prices, and sources. Keep branch-specific availability and price validity separate; one chain's central test list does not prove that every branch performs every test at the same price.
