import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CANONICAL_REPOSITORY = "KaronLabs/ytdlp-korean-interface"
DIRECT_UPSTREAM = "ErrorFlynn/ytdlp-interface"
UPSTREAM_TAG = "v2.19.1"
UPSTREAM_COMMIT = "2173316ebb5e50af49a2a4e939693fa8c3a3459c"
RELEASE_TAG = "v2.19.1-karon.1"
RELEASE_COMMIT = "c053c1edf5508b05beac1da27ddfcdbefd1bc2bd"
RELEASE_URL = "https://github.com/KaronLabs/ytdlp-korean-interface/releases/tag/v2.19.1-karon.1"
RELEASE_DATE = "2026-08-16"
RELEASE_ASSET = "ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip"
RELEASE_ASSET_URL = (
    "https://github.com/KaronLabs/ytdlp-korean-interface/releases/download/"
    "v2.19.1-karon.1/ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip"
)
CURRENT_RELEASE_TAG = "v2.19.1-karon.2"
CURRENT_RELEASE_ASSET = f"ytdlp-korean-interface-{CURRENT_RELEASE_TAG}-win-x64.zip"
CURRENT_RELEASE_ASSET_URL = (
    f"https://github.com/{CANONICAL_REPOSITORY}/releases/download/"
    f"{CURRENT_RELEASE_TAG}/{CURRENT_RELEASE_ASSET}"
)

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

    def test_citation_records_first_canonical_release(self):
        citation = read("CITATION.cff")
        self.assertIn("license: MIT", citation)
        self.assertIn("repository-code: https://github.com/KaronLabs/ytdlp-korean-interface", citation)
        self.assertIn(f'version: "{RELEASE_TAG}"', citation)
        self.assertIn(f"date-released: {RELEASE_DATE}", citation)

    def test_provenance_records_first_canonical_release_identity(self):
        provenance = read("PROVENANCE.md")
        for value in [RELEASE_TAG, RELEASE_COMMIT, RELEASE_URL]:
            with self.subTest(value=value):
                self.assertIn(value, provenance)
        self.assertNotIn("Current canonical release | None yet", provenance)
        self.assertNotIn("do not invent one", provenance.lower())

    def test_readme_exposes_provenance_records_and_release_download(self):
        readme = read("README.md")
        for value in [
            "[NOTICE](NOTICE)",
            "[PROVENANCE.md](PROVENANCE.md)",
            "[ATTRIBUTION.md](ATTRIBUTION.md)",
            RELEASE_TAG,
            RELEASE_URL,
        ]:
            with self.subTest(value=value):
                self.assertIn(value, readme)
        self.assertNotIn("공개 Release 바이너리가 없습니다", readme)

    def test_readme_has_prominent_direct_windows_binary_download(self):
        readme = read("README.md")
        self.assertIn("Download for Windows", readme)
        self.assertIn(CURRENT_RELEASE_TAG, readme)
        self.assertIn(CURRENT_RELEASE_ASSET, readme)
        self.assertIn(CURRENT_RELEASE_ASSET_URL, readme)
        self.assertIn("Code → Download ZIP", readme)
        self.assertLess(
            readme.index(CURRENT_RELEASE_ASSET_URL),
            readme.index("## 이 프로젝트는 무엇인가요?"),
            "direct Windows binary download must appear before the project introduction",
        )
        self.assertLess(
            readme.index(CURRENT_RELEASE_ASSET_URL),
            readme.index("## 처음 사용하는 방법"),
            "current download must appear before the setup instructions",
        )

    def test_readme_distinguishes_runtime_from_developer_downloads(self):
        readme = read("README.md")
        for phrase in ["약 188MB", "일반 사용자는 이 ZIP 하나만", "ytdlp-interface.exe",
                       "corresponding-sources", "SPDX", "실행용이 아닙니다"]:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, readme)

    def test_readme_describes_current_quality_choices_and_limits(self):
        readme = read("README.md")
        for phrase in ["최대 1080p", "최대 720p", "최고 화질", "MP3", "다운로드 예정 화질",
                       "WebM", "MKV", "재생목록", "라이브", "고급"]:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, readme)

    def test_readme_does_not_call_current_release_unpublished(self):
        readme = read("README.md")
        self.assertNotRegex(readme, r"v2\.19\.1-karon\.2[^\n]{0,100}(?:HOLD|미공개|공개되지|준비 중)")
        self.assertNotIn("다음 릴리스 후보", readme)
        self.assertNotIn("약 2.5GB", readme)
        self.assertNotIn("약 8.8MB", readme)

    def test_readme_preserves_license_boundary_and_gui_waiver(self):
        readme = read("README.md")
        for phrase in ["애플리케이션 소스", "MIT", "GPL-3.0-or-later", "제3자",
                       "소유자 결정으로 생략", "WAIVED_BY_OWNER"]:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, readme)
        self.assertNotRegex(readme, r"(?:패키지|배포 ZIP) 전체(?:가|는) MIT")

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
