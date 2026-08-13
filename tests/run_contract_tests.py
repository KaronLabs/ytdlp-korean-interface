#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path


TEST_ROOT = Path(__file__).resolve().parent
suite = unittest.defaultTestLoader.discover(TEST_ROOT / "contract", pattern="test_*.py")
result = unittest.TextTestRunner(verbosity=2).run(suite)
sys.exit(not result.wasSuccessful())
