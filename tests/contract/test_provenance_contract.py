import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CANONICAL_REPOSITORY = "KaronLabs/ytdlp-korean-interface"
DIRECT_UPSTREAM = "ErrorFlynn/ytdlp-interface"
UPSTREAM_TAG = "v2.19.1"
UPSTREAM_COMMIT = "2173316ebb5e50af49a2a4e939693fa8c3a3459c"

REQUIRED_FILES = [
    "NOTICE",
    "PROVENANCE.md",
    "ATTRIBUTION.md",
    "CITATION.cff",
    "docs/provenance-dispute-response.md",
]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class ProvenanceContractTests(unittest.TestCase):
    def test_required_provenance_files_exist(self):
        for relative_path in REQUIRED_FILES:
            with self.subTest(path=relative_path):
                self.assertTrue((ROOT / relative_path).is_file(), relative_path)

    def test_canonical_repository_is_consistent(self):
        for relative_path in ["NOTICE", "PROVENANCE.md", "ATTRIBUTION.md", "CITATION.cff"]:
            with self.subTest(path=relative_path):
                self.assertIn(CANONICAL_REPOSITORY, read(relative_path))

    def test_direct_upstream_is_explicit(self):
        for relative_path in ["NOTICE", "PROVENANCE.md", "ATTRIBUTION.md"]:
            with self.subTest(path=relative_path):
                self.assertIn(DIRECT_UPSTREAM, read(relative_path))

    def test_provenance_pins_upstream_baseline(self):
        provenance = read("PROVENANCE.md")
        self.assertIn(UPSTREAM_TAG, provenance)
        self.assertIn(UPSTREAM_COMMIT, provenance)

    def test_attribution_preserves_mit_reuse(self):
        attribution = read("ATTRIBUTION.md").lower()
        for phrase in [
            "forks",
            "modifications",
            "commercial use",
            "paid teaching",
            "mit license",
            "not an additional software-license restriction",
        ]:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, attribution)

    def test_citation_is_mit_and_does_not_invent_a_release(self):
        citation = read("CITATION.cff")
        self.assertIn("license: MIT", citation)
        self.assertIn("repository-code: https://github.com/KaronLabs/ytdlp-korean-interface", citation)
        self.assertNotIn("version:", citation)
        self.assertNotIn("v2.19.1-karon.1", citation)

    def test_readme_exposes_provenance_records(self):
        readme = read("README.md")
        for link in [
            "[NOTICE](NOTICE)",
            "[PROVENANCE.md](PROVENANCE.md)",
            "[ATTRIBUTION.md](ATTRIBUTION.md)",
        ]:
            with self.subTest(link=link):
                self.assertIn(link, readme)

    def test_existing_upstream_mit_notice_is_preserved(self):
        license_text = read("LICENSE")
        self.assertIn("Copyright (c) 2021 ErrorFlynn", license_text)
        self.assertIn("Permission is hereby granted, free of charge", license_text)

    def test_dispute_response_is_evidence_first_and_non_retaliatory(self):
        response = read("docs/provenance-dispute-response.md").lower()
        for phrase in ["preserve", "hash", "correction", "platform policy", "harassment", "doxxing"]:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, response)


if __name__ == "__main__":
    unittest.main()
