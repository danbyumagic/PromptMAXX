# Grounding benchmark report

This report measures retrieval against the versioned benchmark queries. It does not measure answer quality.

## Configuration

- Suite: promptmaxx-grounding-demo-suite v1 (Tuning)
- Corpus: promptmaxx-grounding-demo v1
- Embedding model: bge-m3:latest
- Endpoint locality: Local
- Provider/model version: 7907646426070047a77226ac3e684fbbe8410524f7b4a74d02837e43f2146bab
- Dimensions: 1024
- Chunking: size 800, overlap 120
- Retriever: lexical weight 0.150, MMR lambda 0.750, source penalty 0.100
- Retrieval limits: k 3, character budget 2000
- Timestamp: 2026-08-18T03:17:02Z
- Completed: 2026-08-18T03:17:03Z

## Aggregate retrieval metrics

- Cases: 10; evaluated: 10; errors: 0 (errors count as misses in rates)
- Hit rate @ k: 100.0%
- Mean recall @ k: 100.0%
- Source coverage: 100.0%
- Zero-result cases: 0

## Per-case outcomes

| Case | Split | Query | Status | Hit @ k | Recall @ k | Expected sources | Retrieved sources | Retrieved chunks | Error |
| --- | --- | --- | --- | ---: | ---: | --- | --- | --- | --- |
| q-tuning-01 | Tuning | How often are Riverbend water samples collected? | evaluated | yes | 100.0% | demo-water-quality | demo-community-garden, demo-privacy-retention, demo-water-quality | 93928204aff92bcb015c21f34ee9c301707414d7de1bb3d7f4180ee356df0151, 741275065a6c5051471e6f9daac54cb8212e55a67c26a23a62723ab526804414, 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0 | — |
| q-tuning-02 | Tuning | Which nitrate reading triggers follow-up? | evaluated | yes | 100.0% | demo-water-quality | demo-privacy-retention, demo-release-playbook, demo-water-quality | 93928204aff92bcb015c21f34ee9c301707414d7de1bb3d7f4180ee356df0151, d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0 | — |
| q-tuning-03 | Tuning | How are Greenfield garden plots assigned? | evaluated | yes | 100.0% | demo-community-garden | demo-community-garden, demo-emergency-plan, demo-release-playbook | 741275065a6c5051471e6f9daac54cb8212e55a67c26a23a62723ab526804414, f67a82bce95f5fa6b8f242cd3e6d4dc4f64660026c823d5a455d6fdc14f86ebc, d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f | — |
| q-tuning-04 | Tuning | When may gardeners water to reduce evaporation? | evaluated | yes | 100.0% | demo-community-garden | demo-community-garden, demo-transit-safety, demo-water-quality | 741275065a6c5051471e6f9daac54cb8212e55a67c26a23a62723ab526804414, 93928204aff92bcb015c21f34ee9c301707414d7de1bb3d7f4180ee356df0151, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850 | — |
| q-tuning-05 | Tuning | What must happen before a Northstar rollout? | evaluated | yes | 100.0% | demo-release-playbook | demo-community-garden, demo-release-playbook, demo-transit-safety | d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850, 741275065a6c5051471e6f9daac54cb8212e55a67c26a23a62723ab526804414 | — |
| q-tuning-06 | Tuning | Who owns the release change window? | evaluated | yes | 100.0% | demo-release-playbook | demo-privacy-retention, demo-release-playbook, demo-transit-safety | d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850 | — |
| q-tuning-07 | Tuning | When do local endpoints keep prompts on the Mac? | evaluated | yes | 100.0% | demo-privacy-retention | demo-emergency-plan, demo-privacy-retention, demo-transit-safety | 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0, f67a82bce95f5fa6b8f242cd3e6d4dc4f64660026c823d5a455d6fdc14f86ebc, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850 | — |
| q-tuning-08 | Tuning | How often is the retention review scheduled? | evaluated | yes | 100.0% | demo-privacy-retention | demo-library-access, demo-privacy-retention, demo-release-playbook | 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0, d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, 410fe88beb3f91cf50ed8fd6822012d339dee4d43cc13995e16b3f3641fba227 | — |
| q-tuning-09 | Tuning | What identification is needed for a Harbor library card? | evaluated | yes | 100.0% | demo-library-access | demo-library-access, demo-release-playbook, demo-transit-safety | 410fe88beb3f91cf50ed8fd6822012d339dee4d43cc13995e16b3f3641fba227, d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, d3757bde85243aceb3a1200b39c18de44d90f8cd3854b4ac22eae3d889e12850 | — |
| q-tuning-10 | Tuning | How many study rooms can a member reserve? | evaluated | yes | 100.0% | demo-library-access | demo-library-access, demo-privacy-retention, demo-release-playbook | 410fe88beb3f91cf50ed8fd6822012d339dee4d43cc13995e16b3f3641fba227, d3198015c625400df7ed3fb4a480247efc60576855c4d79059abca459619f02f, 4fe8888aff70b094fbaf79c7a13aea5b2ae79750c1324b0905657202e90824d0 | — |
