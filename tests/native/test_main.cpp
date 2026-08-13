#include <iostream>

int run_i18n_tests();

int main()
{
	const auto failures = run_i18n_tests();
	if(failures)
		std::cerr << failures << " localization test(s) failed\n";
	return failures ? 1 : 0;
}
