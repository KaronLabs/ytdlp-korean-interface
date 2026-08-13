#include <iostream>

int run_i18n_tests();
int run_state_token_tests();

int main()
{
	const auto failures = run_i18n_tests() + run_state_token_tests();
	if(failures)
		std::cerr << failures << " localization test(s) failed\n";
	return failures ? 1 : 0;
}
