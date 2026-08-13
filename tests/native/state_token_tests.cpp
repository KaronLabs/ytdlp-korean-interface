#include "state_tokens.hpp"
#include "settings_json.hpp"
#include "subtitle_entry.hpp"

#include <array>
#include <iostream>

namespace
{
	int failures {};

	void expect(bool condition, const char *expression, const char *test)
	{
		if(!condition)
		{
			++failures;
			std::cerr << test << ": expected " << expression << '\n';
		}
	}

	void test_language_defaults_and_accepts_supported_locales()
	{
		expect(normalized_language("") == "en-US", "missing language defaults to en-US", __func__);
		expect(normalized_language("ko-KR") == "ko-KR", "ko-KR persists", __func__);
		expect(normalized_language("fr-FR") == "en-US", "invalid language falls back to en-US", __func__);
	}

	void test_queue_state_round_trip_and_legacy_statuses()
	{
		const std::array states {
			queue_item_state::queued,
			queue_item_state::active,
			queue_item_state::stopped,
			queue_item_state::done,
			queue_item_state::error,
			queue_item_state::skipped,
		};
		for(const auto state : states)
			expect(
				queue_item_state_from_token(queue_item_state_token(state)) == state,
				"saved queue state round-trips",
				__func__
			);

		expect(queue_item_state_from_legacy_status("queued") == queue_item_state::queued, "legacy queued", __func__);
		expect(queue_item_state_from_legacy_status("started") == queue_item_state::active, "legacy started", __func__);
		expect(queue_item_state_from_legacy_status("downloading") == queue_item_state::active, "legacy downloading", __func__);
		expect(queue_item_state_from_legacy_status("processing") == queue_item_state::active, "legacy processing", __func__);
		expect(queue_item_state_from_legacy_status("done") == queue_item_state::done, "legacy done", __func__);
		expect(queue_item_state_from_legacy_status("error") == queue_item_state::error, "legacy error", __func__);
		expect(queue_item_state_from_legacy_status("skipped") == queue_item_state::skipped, "legacy skipped", __func__);
		expect(queue_item_state_from_legacy_status("stopped") == queue_item_state::stopped, "legacy stopped", __func__);
		expect(queue_item_state_from_legacy_status("한국어 표시") == queue_item_state::queued, "unknown visible status is queued", __func__);
	}

	void test_settings_json_round_trip_preserves_language_and_queue_states()
	{
		settings_json_t settings;
		settings.language = "ko-KR";
		settings.unfinished_queue_items = {
			{"", {"duplicate", "duplicate", "skipped-without-sidecar"}},
			{"playlist", {"queued-item"}},
		};
		settings.unfinished_queue_states = {
			{queue_item_state::queued, queue_item_state::stopped, queue_item_state::skipped},
			{queue_item_state::queued},
		};
		nlohmann::json serialized;
		settings.to_json(serialized);
		settings_json_t restored;
		restored.from_json(serialized);
		expect(restored.language == "ko-KR", "ko-KR survives settings round trip", __func__);
		expect(restored.unfinished_queue_items == settings.unfinished_queue_items, "queue URLs preserve order and duplicates", __func__);
		expect(restored.unfinished_queue_states == settings.unfinished_queue_states, "queue states survive without sidecar", __func__);

		serialized.erase("language");
		restored.from_json(serialized);
		expect(restored.language == "en-US", "missing language falls back to en-US", __func__);
		serialized["language"] = "unsupported";
		restored.from_json(serialized);
		expect(restored.language == "en-US", "unsupported language falls back to en-US", __func__);
		serialized["language"] = 1;
		restored.from_json(serialized);
		expect(restored.language == "en-US", "non-string language falls back to en-US", __func__);
	}

	void test_nameless_subtitle_entry_uses_language_fallback()
	{
		const nlohmann::json subtitles = {
			{"en", {{{"url", "http://127.0.0.1/sub.vtt"}, {"ext", "vtt"}, {"protocol", "m3u8_native"}}}},
			{"live_chat", {{{"url", "http://127.0.0.1/chat.json"}}}},
		};
		const auto &formats = subtitles.at("en");
		expect(subtitle_entry_available(formats), "name-less URL subtitle is available", __func__);
		std::string label;
		if(subtitle_entry_available(formats))
			label = subtitle_display_name("en", formats);
		expect(label == "en", "language key is the display fallback", __func__);
		int available {};
		for(auto it {subtitles.begin()}; it != subtitles.end(); ++it)
			if(it.key() != "live_chat" && subtitle_entry_available(*it))
				++available;
		expect(available == 1, "one downloadable language is counted and live_chat is excluded", __func__);

		const nlohmann::json name_only = nlohmann::json::array({{{"name", "English"}}});
		expect(!subtitle_entry_available(name_only), "name-only subtitle is not downloadable", __func__);

		const nlohmann::json inline_data = nlohmann::json::array({{{"data", "WEBVTT"}, {"ext", "vtt"}}});
		expect(subtitle_entry_available(inline_data), "name-less inline subtitle data is available", __func__);
		expect(subtitle_display_name("ko", inline_data) == "ko", "inline subtitle uses language fallback", __func__);
		expect(!subtitle_entry_available(nlohmann::json::array()), "empty format array is unavailable", __func__);
		expect(!subtitle_entry_available(nlohmann::json::array({"malformed"})), "non-object format is unavailable", __func__);
		expect(!subtitle_entry_available(nlohmann::json::array({{{"url", 7}}})), "non-string URL is unavailable", __func__);
	}
}

int run_state_token_tests()
{
	test_language_defaults_and_accepts_supported_locales();
	test_queue_state_round_trip_and_legacy_statuses();
	test_settings_json_round_trip_preserves_language_and_queue_states();
	test_nameless_subtitle_entry_uses_language_fallback();
	return failures;
}
