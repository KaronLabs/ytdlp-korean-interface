#include "state_tokens.hpp"

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
}

int run_state_token_tests()
{
	test_language_defaults_and_accepts_supported_locales();
	test_queue_state_round_trip_and_legacy_statuses();
	return failures;
}
