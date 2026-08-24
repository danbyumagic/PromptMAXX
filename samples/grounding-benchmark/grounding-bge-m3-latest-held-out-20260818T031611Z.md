# Grounding benchmark report

This report measures retrieval against the versioned benchmark queries. It does not measure answer quality.

## Configuration

- Suite: promptmaxx-grounding-demo-suite v1 (Held-out)
- Corpus: promptmaxx-grounding-demo v1
- Embedding model: bge-m3:latest
- Endpoint locality: Local
- Provider/model version: 7907646426070047a77226ac3e684fbbe8410524f7b4a74d02837e43f2146bab
- Dimensions: 1024
- Chunking: size 800, overlap 120
- Retriever: lexical weight 0.150, MMR lambda 0.750, source penalty 0.100
- Retrieval limits: k 3, character budget 2000
- Timestamp: 2026-08-18T03:16:09Z
- Completed: 2026-08-18T03:16:11Z

## Aggregate retrieval metrics

- Cases: 10; evaluated: 10; errors: 0 (errors count as misses in rates)
- Hit rate @ k: 100.0%
- Mean recall @ k: 95.0%
- Source coverage: 100.0%
- Zero-result cases: 0

## Per-case outcomes

| Case | Split | Query | Status | Hit @ k | Recall @ k | Expected sources | Retrieved sources | Retrieved chunks | Error |
| --- | --- | --- | --- | ---: | ---: | --- | --- | --- | --- |
| q-heldout-01 | Held-out | Where does the monitoring team store measurements? | evaluated | yes | 100.0% | demo-water-quality | demo-energy-audit, demo-privacy-retention, demo-water-quality | 93928204aff92bcb015c21f34ee9c301707414d7de1bb3d7f4180ee356df0151, 02cb3d3f40856131fb2943b1c623fafcdb7723ed962c66b875a098c059e00475, 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0 | — |
| q-heldout-02 | Held-out | What happens when a nitrate result is high? | evaluated | yes | 100.0% | demo-water-quality | demo-privacy-retention, demo-release-playbook, demo-water-quality | 93928204aff92bcb015c21f34ee9c301707414d7de1bb3d7f4180ee356df0151, d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0 | — |
| q-heldout-03 | Held-out | How many garden plots are reserved for accessible beds? | evaluated | yes | 100.0% | demo-community-garden | demo-community-garden, demo-library-access, demo-transit-safety | 741275065a6c5051471e6f9daac54cb8212e55a67c26a23a62723ab526804414, 410fe88beb3f91cf50ed8fd6822012d339dee4d43cc13995e16b3f3641fba227, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850 | — |
| q-heldout-04 | Held-out | When is garden compost turned? | evaluated | yes | 100.0% | demo-community-garden | demo-community-garden, demo-release-playbook, demo-transit-safety | 741275065a6c5051471e6f9daac54cb8212e55a67c26a23a62723ab526804414, d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850 | — |
| q-heldout-05 | Held-out | Who can approve a release rollback? | evaluated | yes | 100.0% | demo-release-playbook | demo-privacy-retention, demo-release-playbook, demo-transit-safety | d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850 | — |
| q-heldout-06 | Held-out | When are production changes frozen? | evaluated | yes | 100.0% | demo-release-playbook | demo-energy-audit, demo-privacy-retention, demo-release-playbook | d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0, 02cb3d3f40856131fb2943b1c623fafcdb7723ed962c66b875a098c059e00475 | — |
| q-heldout-07 | Held-out | Where are run traces stored? | evaluated | yes | 100.0% | demo-privacy-retention | demo-privacy-retention, demo-transit-safety, demo-water-quality | 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850, 93928204aff92bcb015c21f34ee9c301707414d7de1bb3d7f4180ee356df0151 | — |
| q-heldout-08 | Held-out | Which controls are described for PromptMAXX records, and what may Harbor members reserve? | evaluated | yes | 100.0% | demo-library-access, demo-privacy-retention | demo-library-access, demo-privacy-retention, demo-release-playbook | 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0, 410fe88beb3f91cf50ed8fd6822012d339dee4d43cc13995e16b3f3641fba227, d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f | — |
| q-heldout-09 | Held-out | What are Harbor Library weekend hours? | evaluated | yes | 100.0% | demo-library-access | demo-library-access, demo-release-playbook, demo-water-quality | 410fe88beb3f91cf50ed8fd6822012d339dee4d43cc13995e16b3f3641fba227, 93928204aff92bcb015c21f34ee9c301707414d7de1bb3d7f4180ee356df0151, d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f | — |
| q-heldout-10 | Held-out | Which access guides mention rooms and accessible beds? | evaluated | yes | 50.0% | demo-community-garden, demo-library-access | demo-emergency-plan, demo-library-access, demo-transit-safety | 410fe88beb3f91cf50ed8fd6822012d339dee4d43cc13995e16b3f3641fba227, f67a82bce95f5fa6b8f242cd3e6d4dc4f64660026c823d5a455d6fdc14f86ebc, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850 | — |
